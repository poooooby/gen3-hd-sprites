# WoobleView: developer guide

WoobleView's mod id is `gen3-hd-sprites` (the name it shipped under). Sprite mods find it by that
id, so the id stays.

For mod authors and contributors. Players only need the [README](README.md).

## How it works

Gen 3 draws a battle into a 240×160 canvas (Gen 1 into 160×144) and the field into a world canvas, then scales them up
by a whole number, so a sprite shrunk or moved by part of a pixel is resampled on that grid. This
mod lifts tagged sprites off it.

A "pass" is the drawing of one canvas: the battle (from `Battle.draw` to the frame's end), a
Pokédex or summary screen (a "dex" pass, from its `Pokedex.draw` or the summary's draw: FireRed /
LeafGreen's `SummaryMenu.draw`, or the Ruby/Sapphire or Emerald skin the screen stack draws in its
place; inside a battle the battle pass covers it) or the field
(`Renderer:beginWorldPass` … `endWorldPass`). While a pass runs, a draw of a tagged image is
recorded instead of drawn, and everything drawn after it goes to a fresh transparent layer. When
the Renderer blits that canvas to the window (`Renderer:blitCanvas`), the blit becomes: the
canvas, each recorded sprite at window resolution, the next layer, and so on. The game's draw
order is kept exactly: the battle HUD, text box, menus and fades stay on top; in the field, roofs
and tree tops still cover what walks under them, and the player and NPCs still sort against
tagged Pokémon.

**Shaders.** A recorded sprite is drawn later than the game asked, and the game often shares
one shader between draws (both battlers' blend, the stat change's darken and pattern passes).
So `Shader:send` / `sendColor` are wrapped (once, through a probe shader's method table) to
remember what each shader was last sent; each recorded draw keeps a copy and replays it, and
the latest values are put back after the composite or flatten. Two shaders work in the drawn
image's own pixels, which the HD texture would blow up into giant blocks, so for an HD draw
their uniforms are remapped (`PIXEL_SHADERS` in `src/hd.lua`, told apart by their uniforms):

- **The stat-change pattern** (`origin`, `size`, `flip`, `maskTex`; Sand Attack, Growl, any
  stat change): `origin` / `size` are recomputed so each HD texel reads the pattern at the
  battle pixel it covers, `flip` 0 (the mapping's sign mirrors it).
- **Mosaic** (`texSize`, `block`; Transform): the HD texture's size, and `block` in its texels.

**Part of a pic.** A tagged pic drawn through a quad of its own (a `texture` + `quad` spec, the
quad not in `quadPivots`) is part of the pic: the engine draws a pic row by row, each row shifted,
for Rapid Spin, Spite, Extrasensory, Dig and a ghost wave. Each such draw keeps the whole pic's
pivot and draws only the matching strip of the HD frame, so the rows rebuild the frame.

When a frame can't be composited that way it is drawn the usual low-res way, so nothing is ever
lost: a canvas swapped out mid-pass (Ruby/Sapphire/Emerald weather that reads the field), tilt
mode, a battle transition, or more tagged draws in one frame than the cap (8 in battle and the
Pokédex, 12 in the field; `cap(pass)` / `setCap(pass, n)`). Tagged draws with nothing drawn
between them share one layer. A layer is one window-sized canvas, so a high cap costs memory
only in scenes that use it.

## Generations

`src/engine.lua` wraps the Renderer's seams, which the generations that draw through the
Renderer share (Gen 1 and Gen 3). Each generation's own seams are wrapped by its adapter, picked
by `GameVersion.generation()` (`Engine.adapters`, filled in `main.lua`):

- **`src/gen3.lua`:** everything in this guide that names a Gen 3 module (`Battle.draw`, the
  Pokédex and summary screens, `Display.presentUi`, the screen stack, Battle Fit's seams).
- **`src/gen1.lua`:** Red, Blue and Yellow. Wraps `BattleState:drawClassic` (the ORIGINAL
  layout) and starts the battle pass there. The game draws its HUDs and text box into one gray
  canvas with the white field, colours it zone by zone (`drawZonePass`), then draws the Pokémon
  over it; with Battle Fit on the adapter draws the field without them (`drawHUDs` /
  `drawTextArea` shadowed on the battle), then the UI seam, then the HUDs and text box on a
  canvas of their own through the same zone pass. A WIDE battle (`WideBattle.draw`) never
  reaches `drawClassic` and is drawn the game's way, as is a battle another mod draws over a
  world of its own (Terrarium's arena: `renderer.worldOverride` set for the frame). The field
  pass is the shared one (`Renderer:beginWorldPass`, which `OverworldController` calls). A sprite
  mod should tag only what it draws in true colour: in the palette modes the world canvas is
  coloured zone by zone after it is drawn, which a window-resolution draw never reaches (Vivid
  Worlds: OG untags its sheets outside `PaletteFX.honorsTrueColor()`). The screen pass: `Game:draw`
  is wrapped to read the state stack before `Renderer:beginFrame`, and a frame whose lowest drawn
  state is opaque and neither the overworld nor a battle (the intro, the title, Oak's speech, the
  naming screens, the Pokédex, the party, the trainer card, the options, the mod manager, a menu
  over an ORIGINAL battle) is a `"screen"` pass (`Engine.fullScreen`); not while a WIDE or
  world-backed battle is on the stack. A battle is told by its class's own
  `isWideBattleLayout` (a screen's proxy may answer any method name). The SGB palettes colour the
  UI canvas as it is blitted, zone by zone, so a card's blurred backdrop is made from the picture
  blitted once 1:1 through the Renderer's blit (`flattenCard`), and drawn as it is. OG RED's
  object-palette sprites (`PaletteFX.markUiSpriteRedraw`: the intro's, the diploma's, a battle's
  party balls) are drawn again by the Renderer over the blitted canvas, at the letterbox's
  spots: over a filled screen the adapter draws them where the UI went (`Engine.overUi` with
  `hd.uiMap`, which a card and a filled battle record: an upright battle's top band moved up) and
  empties the Renderer's list. The Renderer may blit the UI canvas more than once a frame (a
  docked text box apart): a card is drawn on the first and the rest are taken as done. No
  Pokédex or summary passes yet.
- **`src/gen2.lua`:** Gold, Silver and Crystal. Gold composites its own frame (`Game2`), never
  through the Renderer, and its battle draws the 160×144 panel straight to the window
  (`Chrome.withPanel`). The adapter wraps `BattleState:drawWidescreen` (ORIGINAL layout, white
  background): the scene is drawn into a 160×144 canvas of its own in a battle pass, its parts
  apart for Battle Fit (`drawEnemyHud`, `drawPlayerHud`, `drawBottom` shadowed during
  `drawScene`, then drawn after the UI seam under the exit fade's palette), and the pass is
  composited where the panel would stand (`hd.composite` with a plain scissored blit standing in
  for the Renderer's; `hd.endFrame` after it). A WIDE battle and a black or world background
  (`Game2:paintBattleSurround` paints those around the panel afterwards) are drawn the game's way.
  Layout `"gen2_og"`. The field has no low-res canvas either: `World:draw` draws the map and
  people straight to the window at its zoom, already at window resolution. So the adapter wraps
  `World:drawPeople` in a **direct** field pass (`hd.beginDirect("field")` / `hd.endDirect()`):
  a tagged image is drawn in place at its spec's `scale` about its pivot (`lowPivot`, or the
  quad's feet with `anchor = "feet"`), the way a draw past a pass's cap is; nothing is recorded,
  layered or composited, and the draw order (Crystal's grass over the feet) is the game's.

**Battle layouts.** The battle screen's canvas numbers (`fit.focus`, the HP-box rects, the
enemy's feet, the pads, the side shift's spots, the wallpaper rows...) are a layout:
`hd.layouts[name]`, picked with `hd.useLayout(name)` before a battle pass. `"gen3"` is the table
in `src/hd.lua`; `src/gen1.lua` adds `"gen1_og"` (text box line at row 96, enemy feet at 56, no
pads or wallpaper, no side shift: Gen 1's move animations are placed in the cart's coordinates).

## Battle Fit

A battle pass is cut into the **scene** and the **UI** over it.

- **The UI seam:** `hd.seam("ui")` is called right after `BallOpen.draw`, the last scene draw
  in `Ui.draw` (`src/core/game3/battle/ui.lua`), for singles and doubles alike.
- **The wallpaper and pads:** with Battle Fit on, `BattleChrome.drawTerrain` draws the
  terrain's split art, the same art the intro slide uses:
  - the wallpaper goes to `hd.backdrop`, recorded rather than drawn;
  - the two pads go through `hd.drawStage`.

At composite time:

- **The stage** zooms by `z` about `fit.focus = (120, 112)`, the text box's top centre. The
  stage is the base canvas, the scene's layers and the tagged sprites before the seam.
- **The wallpaper** zooms by `1 - (1 - z) * fit.parallax`. It is drawn straight from its image,
  wrapped horizontally and clamped vertically, so it covers the view.
- **Whole-scene draws in the scene** get a layer of their own that is not zoomed, so they still
  cover everything. These are fill rectangles and non-canvas images covering 240×112 or more,
  such as a move's background or a flash.
- **The UI** is blitted exactly as before.

The target zoom:

- For each tagged draw in the scene, the top of its art is `Y_pivot - (pivotY - spec.top) * size`.
- With `T` the highest of those tops, `target = (112 - margin) / (112 - T)` (`margin = 2`).
- Zoomed about the focus, the enemy's feet line (`fit.feetY = 72`, the bottom of its pic box)
  would sink into the player's HP box. Past the point where it would go below
  `fit.feetMax = 76`, the stage also rises by `lift = 112 + (72 - 112) * z - 76`, which holds the
  feet on 76. The target is then `(76 - margin) / (72 - T)`.
- Either target is clamped to `[zMin, 1]`. `zMin` is 0.4, enough for the very biggest (Lugia,
  Koraidon). The wallpaper does not rise: its rows below y = 112 are hidden by the text box on the cart, so its bottom edge stays on the text box line.
- **The player's own Pokémon** is a tag with `side = "player"` and a `body` box (its resting
  pose). With one in the scene, the camera is the largest zoom, with the least extra rise (up
  to `fit.extraMax`, 48 px), that keeps:
  - **The whole animation on screen, always:** its art top over the whole animation (`top`)
    stays under the screen's top. A head Blacephalon throws only has to stay on the screen.
  - **Headroom:** the resting body's top is no higher than `fit.backTopMin` = 52. That is
    where the tallest cart back sprites start (Tyranitar, Steelix and Meganium: row 0 of the
    64×64 back box, centred at y = 80 + 4). It is 8 px below the enemy's HP box (y 16–44), so
    the head never sits behind it.
  - **The player's own side:** at most `fit.maxHiddenOwn` (30%) of the body under the
    player's HP box plus the text box and everything below it (`fit.ui.player`, `fit.ui.text`).

  Levels are relaxed in order: own side first, then headroom. When no allowed zoom gives the
  headroom, the looser levels only choose the rise at `zMin`, never a closer camera, since the
  limit is still the nearest to the headroom (Eternatus would need about 0.35). If even the
  loosest level fits nothing there, the zoom is `zMin` with no extra rise. Without headroom, at most
  `fit.maxHidden` (half) of the body may sit under the enemy's box. The search steps the zoom
  down from the enemy's own fit in `fit.zStep` (0.005) steps, and the rise in 1 px steps.
  Below about 90% zoom the enemy's feet rise also lifts the player's Pokémon, and the search
  accounts for it. The rise is capped where the enemy's art would leave the screen's top.
  Results are remembered by their inputs, since an animation repeats its frames.
- **Side shift:** zoomed out, the two Pokémon and their pads crowd the middle, so each side
  moves back toward its unzoomed spot. The enemy's spot is x 176 and the player's is x 72;
  the shift is `(spot - 120) * (1 - z) / z`, capped at `fit.shiftMax` (40 canvas px) so an
  effect drawn there stays inside the canvas. It follows the zoom from a battle's first frame,
  so nothing moves when a turn starts. Singles only.
  - **Only a tagged side moves:** a side shifts only when its Pokémon is a tagged draw that
    frame (drawn, or reported by `hd.prefit`). An untagged Pokémon (no sprite mod) is drawn by
    the game where it always is, so its pad and the engine's coordinates stay there too.
  - **The library moves** the Pokémon, the pads (`hd.drawStage(image, x, y, side)`) and the
    trainers. `src/engine.lua` tags the `TrainerPic.front` / `back` images with
    `side, trainer = true`. The player's back pic also gets `pinBottom = 112`. Its frame's
    bottom is put exactly on the text box's line, however the camera moves or its side drops,
    so it still reads as a whole sprite standing behind the box. It moves only side to side,
    and so does the send-out origin (its hand).
  - **The engine's coordinates move too,** before each battle frame:
    - `AnimCoords.SINGLES`, which move animations aim at;
    - `Anim.ENEMY_MON` / `PLAYER_MON` (ball targets, the catch, a switch);
    - `Pokedude.sendOutOrigin`, where the player's ball leaves the trainer's hand.
  - **Double-shift guard:** a Pokémon drawn inside `Anim.drawParticles` (an afterimage, a
    move's copy of it) is flagged `inAnim` and not shifted again.
  - **Not fitted:** trainers are left out of the fit itself.
- **The intro's scrolling grass** (`BattleChrome.drawEntry`): on the cart it is a background
  layer that wraps sideways, but the engine draws it as one screen-wide image. With Battle Fit
  on it goes to `hd.band`, which draws it at the scene's zoom, repeated across the whole view's
  width. It zooms about the text box's line but does not rise with the camera, so its rows stay
  where the cart puts them. Each entry is a strip whose art ends at that line (grass, dunes,
  waves; transparent above and below). On the cart the text box spans the screen and hides
  what is below the line; beside a filled screen's narrower text box the field would show
  there. So a strip that ends on a solid row (`hd.solidRow`: the last row at least nine tenths
  opaque, read back once an image from a canvas) repeats that row from under it down to the
  view's bottom, and grass that sinks out of sight sinks beside the text box. A strip with no
  solid row (the speed lines) is clipped at the line instead.
- **The intro's black bars** (`stage.win0`, two rectangles `ui.lua` draws after the UI seam):
  `src/engine.lua` (`Engine.introWindow`) hands the rows to `hd.window(top, bottom)` each frame.
  With Fill Screen the two rectangles are recorded as one `win0` item instead of drawn in the
  UI's box, and the composite draws them across the whole view, opening about the scene's
  middle row in the view's proportions (shut: the screen is black; open: both reach its edges
  together). They no longer cross the stacked layout's split, so they never unsplit the UI.
  Without Fill Screen they are drawn as the engine drew them.
- **Moves' effects at the canvas's sides** (Fill Screen): the zoomed scene is wider than the
  240-px canvas, so an effect drawn to the canvas's sides would stop there. Two kinds of draw
  in the battle's scene are carried on to the view's sides:
  - **Edge layers:** a filled rectangle or polygon reaching either side, or an image, canvas or
    line spanning the width (Fake Out's black curtains, a procedural wave), goes in a layer of
    its own (`cur.open == "edge"`; `stats().edge` counts them). The composite draws it at the
    scene's zoom through a quad over the whole view, the canvas sampled clamped
    (`drawEdge`), so its first and last columns (and its top row) run on. A sprite only
    crossing a side is not one: it would smear.
  - **Background bands** (`wideBackground`): a quad of an image wrapped `"repeat"` across,
    spanning the width, upright, but not over the whole canvas (Surf's and Muddy Water's wave,
    which the engine draws as up to three bands of its BG tilemap with their own blend). It
    is recorded as a `wide` item with the quad's viewport as drawn (the engine moves one quad
    from band to band) and drawn across the whole view with its shader and blend
    (`drawWide`): the tiles continue sideways. Surf draws its water only down to the text
    box's line (the cart's text box hides the rest), so a band reaching the line continues its
    tiles on down to the view's bottom, beside a filled screen's narrower text box. Nothing
    continues upward past the canvas's top. `stats().wide` counts them.
  - **Whole backgrounds** (a quad the canvas's size, over the whole scene) are left as they
    were: a `screen` layer stretched to cover the view, since many backgrounds hold unrelated
    rows below their visible 160.
  - **Effects that stop at the text box's line:** the cart's colour fade (`P.drawColorEffect`,
    Encore's and Flatter's dimming, through their spotlight's window) covers rows 0 to 112
    only, since the text box hid the rest. A `screen` or `edge` layer whose draws all end on
    the line (`markBottom`: `toLine`, none `below`) runs its last row on from the line down to
    the view's bottom (`runDown`), beside a filled screen's narrower text box. A layer with
    anything below the line (a whole background) does not.
  - `tests/drivers/move_edges.lua` plays every move from both sides and logs which ones
    open edge layers, background bands or whole-scene layers (`stats().screen`), with a
    screenshot of each. In Emerald: edge layers for Fake Out, Encore and Flatter; bands for
    Surf and Muddy Water; whole-scene layers for about 60 moves (Psychic, Night Shade,
    Thunder, Sandstorm...), all of which already cover the view.
- **The player's pad stays tucked** under the text box for scale: on the cart its top 11 of
  32 rows show (`fit.padTop` 101, `fit.padRows` 32).
  - **How:** pulled back, the player's side is lowered by `shift.playerY` (canvas px before the
    zoom) so that only `padRows * (1 - fit.padTuck)` (8 of 32, `padTuck` 0.75) show at `zMin`.
    This blends from the cart's 11 at zoom 1, so nothing jumps, and it cancels the camera's
    rise for that side.
  - **What moves:** the player's pad and Pokémon; the trainer stays anchored to the text box.
    The engine's coordinates go down
    with them: `AnimCoords.SINGLES[0].y` and `Anim.PLAYER_MON.y`.
- **A small back stands behind its pad:** when too little of a back's resting body shows
  above the text box, the Pokémon alone is raised (`shift.playerRaise`) until enough shows.
  A back whose body is at most `fit.wholeBelow` (36 px, before the zoom) tall shows **whole**,
  feet just above the text box (Pikachu, Joltik, Natu). One taller than `fit.cutAbove` (56 px)
  needs only `fit.minVisible` (65%), keeping the over-the-shoulder cut. In between, the share
  blends.
  - **What stays:** its pad and trainer. A back already showing that much is left where it is.
  - **What follows:** the engine's battler coordinates (`AnimCoords.SINGLES[0].y`,
    `Anim.PLAYER_MON.y`) take the raise too, so attacks and the ball land on the Pokémon. The
    send-out origin (the trainer's hand) does not.
  - **In the search:** the camera search places the back with both the drop and the raise.
- **Battlers as they rest:** before the UI seam, `src/engine.lua` (`Engine.prefit`, inside the
  battle's draw) asks `Pokemon.frontPic` / `backPic` for both leads, so a sprite mod hands over
  its battle pics. It hands each to `hd.prefit(side, image, x, y)` at the spot
  `Ui.battlerSpriteCenter` gives (origin 32, 32). The fit uses these resting placements for
  their sides instead of the drawn pics. So in a trainer battle the camera is framed for the
  Pokémon before they are sent out, and a send-out jump or an attack's lunge never moves it.
  Singles only; drawn pics are used where nothing was reported.
- The zoom snaps to the target at a battle's first frame and eases out about 20% per frame.
  The extra rise eases the same way.
- It eases back in about 5% per frame, but only after the target has stayed larger for 45
  frames.
- A frame with no UI seam (the post-catch Pokédex scene) is not zoomed; it fills as a whole
  screen (see Fill Screen).

With no `top`, the frame's own top row counts, empty margin included. Pass `top` (the first
row of art, the highest over the animation) so the camera fits the art and not the frame.

**The player's pad, whole** (`src/pads.lua`). The cart stores only the top 11 rows of the
player's pad, because the rest is always under the text box, and a raised camera would show
that cut. On every FRLG and RSE terrain the player's pad is the same 128×32 oval as the
enemy's, 112 px left and 53 px down. So the enemy pad is copied there, once per terrain:

- Every pixel inside the oval is copied.
- Outside the oval, only pixels that differ from the wallpaper are copied: the rim, tufts and
  rocks. The pad tiles' ground corners would not line up with the wallpaper's 4-row stripes
  53 rows lower.
- Everything else is transparent.

The art is read back from the images the game imported from the player's ROM, so nothing is
shipped. A terrain whose enemy pad does not fill the oval, or is mostly ground, keeps the
game's own pad.

**The ground below the text box.** The wallpaper's own rows end at y 112 (the cart's rows
past it are black, hidden by the text box). Below that line, its ground band, rows `fit.ground`
104-112, repeats down to the view's bottom. So a zoomed-out scene, a filled screen or a text
box moved off the screen (Kanto Gear's "gear" battle view) shows ground, not a black band. A
redraw of the recorded wallpaper image inside the scene is skipped, because the recorded one
already covers the view.

**Fill Screen** (`fit.fill`, option `fill_screen`). The Renderer is asked for the whole view
(`Renderer:frameRects()`, passed to `hd.composite` as `view`):

- **The rows it may use:** `src/engine.lua` (`Engine.usableRows`) passes `view.top` (below the
  safe area's top, a notch) and, on a tall screen with on-screen touch controls and no cutout,
  `view.bottom`: the top of the controls (the highest `TouchControls:layout()` zone except the
  corner hotbar button).
- **Wide** (that area no taller than the canvas's 3:2): the UI keeps the Renderer's
  whole-number scale, docked to the bottom, centred. The scene is scaled about the text box's
  line by the smaller of the height fit `(text box line - top) / (112 * scale)` and the width
  fit, never below 1.
- **Tall ("stacked"):**
  - **The UI** spans the width: `U = width / 240`, rounded to two decimals. A non-whole `U`
    draws each UI layer pixel for pixel at `ceil(U)` into a canvas of its own (`sharpen`),
    which is blitted down smoothly. Every UI pixel is the same width, with edges at most one
    screen pixel soft. The `blit` closure's `zk` keeps a zone list on its pixels.
  - **Two bands:** rows from `fit.split` (66) down (the player's HP box, the text box, the
    menus) dock to `view.bottom`. The rows above (the enemy's HP box, the party balls) are
    blitted, clipped, `dyTop` UI px higher.
    - The fit sees that band at the top of the screen (`fit.uiTopDy`): its HP-box rect and the
      back headroom (`backTopMin`) move up with it.
    - It is drawn lower when the scene stops short of the top, `fit.hugGap` above the highest
      art (`fit.artTop`, from `fitStep`). With no tagged art (no sprite mod) its top is not
      known, so the box keeps its cart spot over the scene, and the block centres as one.
    - **The straddle guard:** a visible UI draw that crosses the split but does not cover the
      whole canvas (the level-up window, the intro's closing wipe) sets `cur.uiStraddle`. That
      frame's UI is drawn in one piece.
  - **The scene** grows by `fit.grow` about the line into the space above, up to the top, its
    sides cropped. It grows only as far as both sides' art (`fit.span`: each side's frame
    across, zoomed, shifted) stays `cropMargin` clear of the edges. It is centred and moved
    sideways only as far as that needs (centred on the art when it is wider than the screen).
    The platforms count as each side's art (`fit.pads`, their ovals across: the enemy's 112 to
    240, the player's 0 to 128), so neither is ever cropped. Until the Pokemon are seen,
    `spanDefault` is the two platforms. `grow` eases like the zoom.
  - **The sides slide in** when the width stops it short of the top: `fitStep` gets the art
    width the growth needs (`fit.wantW`) and moves the enemy left and the player right
    (`shift.enemy` / `shift.player`, so attacks follow).
    - A back whose body's top is below the enemy's feet (`feetY`) may slide until the
      centres line up.
    - One level with the enemy may stand in front of its platform, over up to `overlapFoe`
      (30%) of the enemy's frame.
    - The player's share stops at its own HP box's left edge; the enemy takes the rest.
    - The slide is at most `fit.inwardMax` (48) canvas px in all, so each side stays near
      its own spot.
    - Both Pokémon must be tagged; otherwise nothing slides, and the scene keeps both
      platforms whole at the cart's layout.
  - **`fit.topY`,** the canvas y of the area's top in scene pixels (negative with sky above),
    is the highest art may rise, in `fitZoom` and the solver. So a tall foe rises into the
    sky instead of the camera pulling back.
  - **No controls below** (`view.bottom` nil): the whole block is raised by `fit.raise`,
    settling over a few frames, until the sky over the HP box equals the ground under the text
    box.
- The wallpaper, ground band and intro grass cover the view's full width and height either way.
  When the view reaches above the wallpaper's top row (sky above the battle), the wallpaper is
  scaled up evenly about the text box's line until its top row reaches the screen's top, rather
  than its top row being stretched: its zoom is the larger of the parallax zoom and that one.
- **The fit sees a smaller UI.** Over the bigger scene the UI covers less of it, so its rects,
  `feetMax` and `backTopMin` are shrunk by `fit.uiK = 1/f` about the focus before the search.
  That is why a filled widescreen battle pulls back less.
- **Whole-scene layers** (a move's background, a flash), and UI draws over the whole canvas (a
  fade), get a layer of their own, cover-scaled to the view.
- **Whole screens (`compositeCard`):** an opaque draw over the whole 240×160 canvas after the UI
  seam (the summary, nickname, party, bag, the Pokédex page, evolution, a mod's screen, a fade at
  full black) sets `cur.uiCovers`; a frame with no seam at all is the caught scene. Either is one
  picture:
  - it is scaled as far as it fits the usable rows (`view.top` to `view.bottom`), sharply through
    `sharpen`, centred, or docked above touch controls;
  - tagged draws on it (its Pokémon) go at that scale;
  - the rest of the view is the picture blurred (`fit.cardBlur`): the pass is flattened
    (`flattenCard`), averaged down to a quarter (`blurCard`: each halving with linear filtering is
    an exact 2×2 average), given two Gaussian passes across and down, then blitted dimmed to
    `fit.cardDim` and grown to cover the whole view behind the picture;
  - after the picture and its draws, the backdrop is blitted again through `FEATHER_SRC`, clipped
    to the picture: opaque at an edge with a gap beside it, gone `fit.cardFeather` game pixels in,
    so the picture fades into it (an edge on the view's border does not fade);
  - without the blur (`cardBlur = false`, or a device that cannot make the shader) the view
    continues the picture's edges instead: the flat pass blitted again with one canvas pixel as
    wide or tall as each gap, clipped to it. A clip is cut to whole pixels, so each clip reaches
    over the picture's edge pixel (`ceil` / `floor`), or a column is left unpainted at a scale
    that puts the edge inside a pixel (2560×1369). `stats().card` counts these frames;
  - a half-faded cover is not one: the battle keeps its fill, and the cover spans the view.
- **Double battles (`hd.setDouble`):** `Battle.draw` hands over both sides' HP boxes, from the
  engine's `Healthbox.center`. The foes' feet stop at the top of the player's upper box, a back's
  head stops `doublesGap` under the foes' lower box, and `split` falls between the two sides.
  With no tagged foes the scene is not raised. `tests/drivers/doubles_battle.lua` shows foes of
  each size, one window size a run (`HD_ATTACK=1` adds a turn of moves).
  - **Aim:** `AnimCoords.DOUBLES` follows the side shift, so moves land on the shifted Pokémon.
    The battle draws its battlers from that table too: hd takes the shift back off a tagged one
    when recording it, and while the battle draws, the table's rows are the unshifted ones
    (`Engine.doublesY`), because the game caps how low a double battle's back may stand.
  - **`shiftMax`** is `doublesShiftMax` (16): the outer battlers stand near the canvas's edges,
    and a move's effect is clipped to the canvas.
  - **Tall screens (`sceneUp`):** with the rows to spare, the scene's line stands above the
    player's two HP boxes, so the stack is foes' boxes, scene, player's boxes, text box. `uiY` and
    `uiRect` take it into account. `doublesSlack` lets an HP box's empty rows cross `split`.
- **Boot screens:** a `Display.presentUi` frame of kind `"boot"` (the intro movie, title, main
  menu, options, the professor's speech, the naming screens, a mod's boot screen) is a `boot` pass
  (`hd.enabled.boot`: Battle HD, Battle Fit and Fill Screen all on). It is composited even with
  nothing tagged, always through `compositeCard`. `tests/drivers/boot_cards.lua` plays through
  them with the buttons.
- **Screens over the field:** a frame the display draws with no field behind it, because a
  screen-stack layer is `fullscreen` (the Pokedex, party, bag, options, mods, trainer card,
  region map, PC boxes...), is a `screen` pass. It starts in the `Renderer:beginFrame` wrapper
  when the frame is opaque, no battle is active, `Stack.fullscreen()` holds and the frame is not
  `Display.presentUi`'s (`Engine.presentingUi`). Like a boot pass, it needs `hd.enabled.screen`
  (the same three options), is composited even with nothing tagged, and always goes through
  `compositeCard`. A Pokedex or summary drawn in it is in-pass (`stats().dexInPass`). With
  Pokedex & Summary HD off the pass is `plain`: its tagged images are drawn as they would be
  outside a pass. `stats().screenPasses` counts them. `tests/drivers/field_screens.lua` opens
  each start-menu screen.
- The outward side shift keeps its `shiftMax` cap: effects are still drawn in the 240-px
  canvas. The stacked layout's inward slide needs no cap.

**Safety.** Every engine hook calls into this mod under `pcall`. The first error goes to
`hd.fail(err)`: it is logged once, any pass in flight is flattened back into its canvas, and
nothing more is captured that session (`stats().failed`). `hd.canCapture()` is false when the
engine presents without the Renderer (`Display.planesBroken`, its Android fallback), since a
captured pass would never be composited there.

If `BattleChrome.drawTerrain`, `BattleChrome.terrain` or `BallOpen.draw` is missing,
`fit.available` is false and the option does nothing. The HD sprites are unaffected.

## API (`mod.exports`)

```lua
local hd = mod:find("gen3-hd-sprites")
local ex = hd and hd.exports
if ex and ex.isActive() then
  -- an overworld sheet: drawn where it is drawn, 75% of its size, standing on its feet
  ex.tag(sheetImage, { scale = 0.75, anchor = "feet" })
  -- a battle pic: the engine draws the 64x64 `pic`, this draws `frame` of `page` instead
  ex.tag(pic, { texture = page, quad = frame, pivot = { 47, 90 }, lowPivot = { 32, 32 }, scale = 1 })
end
```

| Field | Meaning |
|---|---|
| `scale` | size multiplier, any value (default 1) |
| `anchor = "feet"` | scale about the bottom-centre of the drawn quad |
| `texture`, `quad` | draw this full-resolution frame in place of the tagged image |
| `pivot` | the point of `texture`/`quad` that stands where the tagged image's `lowPivot` was drawn |
| `lowPivot` | default `{32, 32}`, the engine's battle-pic origin |
| `quadPivots` | `{ [quad] = {x, y, scale} }`: a draw through one of these quads scales about its own quad-local point (and, with `scale`, at its own size; `1` = a slice already drawn at its final size). Read at draw time, so it may grow. Check `features.quadPivots` |
| `filter` | `"nearest"` (default) or `"linear"` |
| `top` | the first row of art in the frame (quad pixels), the highest over the animation: Battle Fit fits the art, not the frame's empty margin (default 0) |
| `side` | `"enemy"` (default) or `"player"`: whose Pokémon the draw is |
| `body` | `{x0, y0, x1, y1}`, side `"player"`: its resting body box (quad pixels). Battle Fit keeps its top at or below the tallest cart back sprite's (y 52) and, when it can, keeps at most 30% of it under the player's HP box and the text box |

Also `untag(image)`, `tagOf(image)` (the spec an image was tagged with, or nil: a mod that
draws a tagged pic outside the battle, field and Pokédex passes can draw the full-resolution
texture itself), `isActive()`, `enabled(pass)`, `setEnabled(pass, on)`, `cap(pass)`,
`setCap(pass, n)`, `features` (`{ quadPivots = true, dex = true, battleFit = true, tagOf = true }`),
`fitEnabled()`, `setFit(on)` (the old `"off"` / `"fit"` / `"tall"` still work), `fillEnabled()`, `setFill(on)`, `sceneZoom()` (the battle scene's zoom this
frame; 1 = none) and `stats()` (`splits`, `composites`, `flattened`, `overCap`, `zoom`,
`zoomTarget`, `lift`, `extraLift`, `hiddenEnemyUI`, `hiddenOwnUI`, `backTop`, `shiftEnemy`, `shiftPlayer`, `dropPlayer`, `raisePlayer`, `fill` (the scene's scale over the Renderer's, 1 = none), `uiScale`, `uiTopDy`, `card`, `grow`, `inward`, `topY`, `uiK`,
`failed`). The export `version` is 2. Tags are weak: an image that is freed drops its tag. Keep the tagged
image itself a real low-res picture: it is what shows whenever a frame falls back.

## Tests

`luajit tests/hd_test.lua` (a fake `love.graphics`; no game needed). Every test file is listed by
exact path in `.modkitignore`. The drivers in `tests/drivers/` run in the game
(`POKEPORT_DRIVER`, each file's header says how) and screenshot what they check; for the Game
Boy games: `gen1_battle.lua` (with `GEN1_INTRO_SHOT` and `GEN1_COLORS`), `gen2_battle.lua`,
`field_gb.lua` (Field HD with Vivid Worlds: OG) and `screens_gb.lua` (Red's whole screens).

Keep [README.md](README.md) describing the mod as it is now (players read it).
