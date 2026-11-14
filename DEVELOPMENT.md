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
  canvas of their own through the same zone pass. A WIDE battle never reaches `drawClassic`:
  the adapter wraps `WideBattle.draw` (304×144, layout `"gen1_wide"`) and starts the battle pass
  there too. Its HUDs and text box are locals of that module, drawn after the Pokémon and the
  move animation; each first asks the battle `statusHUDVisible` / `bottomUIVisible`, so with
  Battle Fit on those are shadowed on the battle for the frame and the first ask is the UI seam
  (the intro's `drawBallRow` calls, which come before the animation, are held until the seam).
  With the EXTENDED HUD (`battle:extendedHUD()`: the HUD in window space) a WIDE battle is
  drawn the game's way, as is a battle another mod draws over a world of its own (Terrarium's
  arena: `renderer.worldOverride` set for the frame). The field
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
  docked text box apart): a card is drawn on the first and the rest are taken as done. The
  Pokédex entry and the summary (`src.ui.DexEntryMenu`, `src.ui.SummaryMenu`) are the adapter's
  `Engine.dexModules`: a dex pass, or with Fill Screen the screen pass already running. Both draw
  their pic mirrored (`sx = -1`), which the full frame follows. Outside the ADVANCED colours a
  sprite mod's pic is in the four shades for the palette to colour, so it is tagged with
  `shades` (below). Through the zones the palette shader keeps a pixel's alpha but not
  premultiplied, so the Renderer's blit of a layer of ours (mostly clear) is done with plain
  alpha blending there (`src/engine.lua`), or each clear pixel would add its zone's darkest
  colour.
- **`src/gen2.lua`:** Gold, Silver and Crystal. Gold composites its own frame (`Game2`), never
  through the Renderer, and its battle draws the 160×144 panel straight to the window
  (`Chrome.withPanel`). The adapter wraps `BattleState:drawWidescreen` (ORIGINAL layout, white
  background): the scene is drawn into a 160×144 canvas of its own in a battle pass, its parts
  apart for Battle Fit (`drawEnemyHud`, `drawPlayerHud`, `drawBottom` shadowed during
  `drawScene`, then drawn after the UI seam under the exit fade's palette), and the pass is
  composited where the panel would stand (`hd.composite` with a plain scissored blit standing in
  for the Renderer's; `hd.endFrame` after it). Layout `"gen2_og"`. A WIDE battle the same way
  through `WideBattle.draw` (a 304×144 canvas, layout `"gen2_wide"`, composited where its 38×18
  tile panel would stand): its field (`WideBattle.drawField`) in `drawScene`, the UI seam, then
  `drawTopHud` / `drawBottomHud` under the exit fade's palette; docked to the window
  (`WideBattle.docked`, the EXTENDED HUD) it is drawn the game's way. A black or world background
  (`Game2:paintBattleSurround` paints those around the panel afterwards) is drawn the game's way.
  A state over a battle (a script's message: the party, the PACK and the battle's other screens
  are opaque and cover it) makes Gold draw the stack again where the panel stands, the battle
  first (`BattleState:draw`). Once the adapter has filled the screen with the battle that frame
  (`hd.uiMap` is this pass's; `Game2:draw` is wrapped to count frames), that draw is skipped and
  the transform moved to where the battle's UI went, so the message box lands on the battle's
  own (over a WIDE battle, 72 canvas pixels in, the 160-wide panel's place in its 304). The field has no low-res canvas either: `World:draw` draws the map and
  people straight to the window at its zoom, already at window resolution. So the adapter wraps
  `World:drawPeople` in a **direct** field pass (`hd.beginDirect("field")` / `hd.endDirect()`):
  a tagged image is drawn in place at its spec's `scale` about its pivot (`lowPivot`, or the
  quad's feet with `anchor = "feet"`), the way a draw past a pass's cap is; nothing is recorded,
  layered or composited, and the draw order (Crystal's grass over the feet) is the game's. The
  summary and the Pokédex (`SummaryMenu:drawPanel`, `PokedexMenu:drawPanel`, which both their
  `draw` and `drawWidescreen` call) are direct dex passes the same way. Under the GbcPalette shader
  (DMG, CLASSIC, a custom palette) a `shades` frame is drawn as its shades for that shader to
  colour.

**Battle layouts.** The battle screen's canvas numbers (`fit.focus`, the HP-box rects, the
enemy's feet, the pads, the side shift's spots, the wallpaper rows...) are a layout:
`hd.layouts[name]`, picked with `hd.useLayout(name)` before a battle pass. `"gen3"` is the table
in `src/hd.lua`; `src/gen1.lua` adds `"gen1_og"` (text box line at row 96, enemy feet at 56, no
pads or wallpaper, no side shift: Gen 1's move animations are placed in the cart's coordinates)
and `"gen1_wide"` (304×144: the line at row 104, each side's 160×144 placement moved into its
region, the player's by (20, 8) and the enemy's by (136, 0)); `src/gen2.lua` adds `"gen2_og"`
and `"gen2_wide"` (the ORIGINAL's scene moved right by 72, the player's HUD by 144). A WIDE
canvas is wider than 16:9, so on a wide screen Fill Screen uses the stacked arrangement (the
UI across the width, the enemy's HP box up at the top, the scene growing between).

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

## Battle Scene (Gen 3)

**Battle Scene: OVERWORLD** (`battle_scene`, `Engine.Scene`, `hd.scene`) replaces the battle's
wallpaper and pads with the map around the player, in 2.5D. It needs Battle Fit (it rides the
battle pass) and is Gen 3 only. Modules in `src/scene/`, loaded by `main.lua` and handed to
`init.lua`:

- `cells.lua`: once per battle (a new `Battle._st`), a 61x65 window of cells around the player
  (`Map.worldMidAt` for art; collision and behaviour through the cell's own map: the primary
  layout, a connection found as `fromDir` finds it, `Map.world`). Kinds: floor, grass, sand,
  water, blocked (`CollPermissions.isWall`), void (off every map indoors); each keeps its
  `coll` and `beh`. Nothing without a model stands up (Emerald 3DS's rule). In Kanto's games
  trees stand too: each column's run of blocked cells with a tree's metatile (`env.stands`: a
  primary tileset's, half its drawn pixels leaves, something on its upper layer) stands as cards
  on the run's southern edge, at most 6 high. In Hoenn's `env.stands` is always false (its trees
  are models; Mossdeep's half-grass ledges passed the leaves test). Rocks, cliffs, unmodelled
  buildings lie flat.
- `signs.lua`: signposts (Emerald 3DS's `voxel_cells.py` rules, `voxel_sign_mask.py`,
  `gen_voxel_sign_masks.py`, `voxel_sign.c`): a blocked cell open west, east and south that is a
  sign event of its map (`env.signAt`, from the maps' `bgEvents`), or a drawing that is no
  mountain (the General tileset's rock 0x064-0x0BF in Hoenn, a tile drawn mostly in the
  mountain's colours, a corner of its outline), no cover (upper layer down the cell), no
  foliage, no house (the mass above a house door: `env.doorAt` warps on a door behaviour) and not
  a column run; a cell drawn as a sign event that stands open on three sides anywhere in the game
  (`signPosts` in `init.lua`: every outdoor map's sign events, read once a game; its metatile or
  its upper layer) with walkable ground south; a lamp drawn as a free one against a house's wall.
  Never a model's cell. Its silhouette (upper layer, lower-layer
  pixels the clean ground beside it does not draw, closed off from the border), a head from the
  north cell's upper layer (a lantern), the ground its cell and its head's are laid with
  (`cell.groundMid`); `Signs.emit` builds each 8-connected piece 2 px thick standing on its own
  bottom. Their drawings go in one texture (16 x 32 each), their solids in the model layer.
- `camera.lua`: the camera in the battle canvas's own pixels (35 degree vertical field over 160
  rows, target on the canvas centre), so the world meets the battle's sprites through whatever
  mapping puts the canvas on the screen. The stage pose (30 degrees, 7 tiles) and the glide
  (field pose straight down, smootherstep travel with a crane arc, a landing push) are adapted
  from Emerald 3DS.
- `stage.lua`: Emerald 3DS's stage search: 13x13 targets scored on what each side's feet stand
  on, cards in front of a sprite and void on screen. A best score under `Stage.FLOOR` keeps the
  wallpaper.
- `trees.lua`: Emerald 3DS's trees (`voxel_tree.c`), on outdoor maps whose primary tileset is
  General (the engine's pair `general__<secondary>`): `part(sec, mid)` (0-3 a 2x2 tree's,
  SMALL, GRASS), `groundMetatile` (a crown's top over grass lays the grass), `laysGround`,
  `emit` (trunk plates and crown cards from `assets/scene/trees.png`, the crown's missing row).
  Packed by `tools/pack_trees.py` from an emerald-3ds checkout. No relief yet: no steeper
  crowns against rock. Cells a tree or a crown covers stand no card.
- `models/kernel.lua`: Emerald 3DS's building primitives (`voxel_building.py`): a model in pixels
  from its rectangle's top-left (X east, Y up, Z south), its drawing at u = X, v = Z - Y; Proj,
  Tile, Band, Strip (courses laid up a face), Prism, HipRoof, Frustum, Vault, Walls, Cylinder,
  PlainWall, PlanPrism, PlanPyramid, PlanHip, PlatePrism, SectionPrism, Moved, Lifted. Python's
  0-based edge indices stay 0-based (`edges = { [0] = ... }`), `Strip`'s `repeat` is `rep`.
- `models/specs.lua`: the 52 exterior specs built from explicit parts (`voxel_building_specs.py`),
  numbers unchanged: houses, Centers, Marts, gyms, Devon, the Safari Zone, Slateport's market,
  museum and halls; and 22 `parts_art` specs (`parts_art(art) -> parts, texture`) of flat faces
  over the drawing (`K.flat`: the texture is `K.withRing`'s three bands, the hidden faces
  `K.Grown` onto the grown band) or cards: Lilycove's store, museum, hall and harbour, the cable
  car stations, the Mirage Tower, Trainer Hill, Cozmo's antenna, Rydel's bikes and most of the
  Battle Frontier.
- `models/solids.lua` (loaded into the kernel before the specs) and `models/solid_specs.lua`
  (appended to them, with `specs.helpers`): `Volume` (dome, drum, tube, slab, plate, lathe,
  profile, pyramid, prism, hip, box, hollow), `HeightSolid` (the volume cut to the drawing column
  by column; `K.HEIGHTSOLID_LOD` is the spec's `lod` while its `parts_art` runs), `ownBands`,
  `ProjSection`, `ProjHull`, `ProjCanopy`, `clipToArt`, `Mound` (a rock lifted pixel by pixel off
  its drawing), `VoxelLathe` / `BakedLathe` (true cubes carved to the drawing, then a 32-sided
  lathe wearing a texture baked off them; the fill pass grows what the view sees by the new
  cube's own faces only, so it skips the full re-scan per trial); 33 specs: the battle tents,
  Slateport's boats, Route 109's parasols, loungers and mats, Route 108's wreck, the Game Corner,
  Verdanturf's flower box, Lavaridge's sand bath, Pacifidlog's hut, Sootopolis's houses, posts and
  the Cave of Origin's doorway, the League and its bushes, the Battle Dome and Pike, the Space
  Center, Slateport's lantern, Rustboro's fountain (`PlanRing`, `Shade`, `Jet`). Spec fields:
  `lod`, `ground_rgb` (cleared at 5 bits a channel), `clip_art`; `parts_art(art, ctx) -> parts,
  texture[, live]` with `ctx.layoutArt(layout, x, y, w, h, ground)` for another building's
  reference drawing, `ctx.animFrames(cx, cy)` (the rect cell's frames in the engine's tile
  animation banks, `TilesetAnim._pairs[pair].banks`: whole metatiles or their upper layer) and
  `ctx.lowerOf(m)` (a metatile's lower layer alone, off the atlas blobs). `live = { cell, frames,
  texels }`: texels a tile animation redraws (the fountain's jet), kept with the model (and in its
  cache) and repainted by `stepLive` when that metatile's bank turns to another frame. In a
  battle the engine does not step the field's animations, so the jet holds the frame the field was
  on, as the water does.
- `models/fortree.lua` (appended to the specs after solid_specs): Fortree's tree houses (deck,
  hut, `LeafRoof`, the bridge planks in the deck's end cells, all `Lifted` 28 px; the ladder a
  `ProjPoly`), the bridge cells and the palms (a card leaning 50 degrees, the trunk cells laid from
  their lower layer). `voxel_fortree.deck_table` (lifting walkers onto a deck: `specs.decks`,
  served by `Scene.decks`) is kept for an overworld view, unused by the battle scene: their
  battle stage search counts a deck as a building's tall cells too. Every spec ported before the lantern builds the same triangles as the
  Python generator (compare counts and coordinate sums with its `vb.Mesh`, the parts_art ones on
  the same synthetic drawing, their textures' checksums too; all 105 matched); the lantern,
  fountain, Fortree and props are checked in the game only.
- `models/bridge.lua`: `voxel_bridge.py` whole (Route 110's Cycling Road): `Bridge.read(io,
  conf, tick)` reads the road off the layout's drawing (pret's colours: `World.pretArt`, the
  relief's `Art.pair` over the cache's tilesets; roles from `World.roles`; the curb component's
  spec), builds its faces (`quads`: the deck, rails, front, piers, ramps in their slots, the five
  kinds of corner, `merge`, `tileFlanks`, `cutCorners`), and `Bridge.blocks` cuts them into one
  model per cell drawn alike (art: the cell, the flank band, the plain road band, a curb's
  stones; `top` from the faces over the cell in the world; a patch of the drawing laid on the
  ground). Pixels and cells are number keys (`P(u, v)`, `C(x, y)`). Where Python breaks a tie by
  a set's order, the port takes a sorted order: the output still matches. `init.lua` builds it in
  a coroutine (`bridgeStep`: `Scene.BRIDGE_SLICE` a frame from the warm-up, `warmAll` and
  `warm` queue it; inside the relief's own build through `modelCells`, which gives the solver
  the bridge's cells as Emerald 3DS's buildings.bin does; to its end if a battle needs it first),
  keeps it in the model cache (`LAYOUT_ROUTE110.bridge`, text, and `.bridge.rgba`, one atlas of
  18-texel columns, each block framed by a copy of its edge as their gutter) and `placeBridges`
  stands a block on every cell of the layout the window shows, its ground the block's metatile
  with the patch over it. Read: 1.5 s, slices at most ~22 ms; from the cache ~20 ms.
  Checked against Emerald 3DS's own models: `tests/drivers/bridge_dump.lua` writes every
  placement's triangles (pixels, shade, the colour at the centroid) as a dump of their
  buildings.bin does; all 883 placements match (their file has more distinct models, 292 to
  253 then: it also keys on the footprints). The relief rebuilt with the bridge's cells is still
  byte for byte theirs.
- `models/interiors.lua` (+ `models/interior_specs.lua`, the rooms' specs in order): the rooms,
  `gen_voxel_buildings.interior_specs` with its helpers (claims, `auto_leave`, `support_left`,
  `outline_trim`, legs (`leg_split`, `table_plan`, `table_parts`), fills, `side_image` /
  `plain_side` / `slab_side`, `pick_side`, `ball_fit`, `lathe_fit`, `dome_fit`, `post_parts`,
  decals, `floor_under`) and the reuse registry (`register_piece`, `reuse_pieces`,
  `place_reused`; `reuse_everywhere` is done per layout, the first time a battle shows a room
  nobody modelled). `Interiors.room(spec, io, reg, tick)` -> the pieces' specs (`name, layout,
  rect, ground, art` (an image of colour ints), `parts, owned, placed, placed_patches, when`,
  and from later rooms `reused_at` / `bare_at`); `Interiors.build(piece[, bare])` -> `{ tris,
  art, tex }`. Images are `{ w, h, c = { [v * w + u] = colour } }` (nil clear); colours pret's
  (`World.pretArt`, the relief's `Art.pair`), so the specs' hex colours compare exactly. Python's
  ties are reproduced: Counter's order (first met), `_set_order` (`Art.setOrder` over tuple
  hashes) and its compensated float sums (`Art.fsum`). The engine keys a layout by pret's number
  (`data/layouts/layouts.json`'s order, which is also how Emerald 3DS's file numbers them), and a
  layout many maps share is named for none of them, so `interior_specs.ids` gives each room's
  number. A layout no map is drawn with, which a script swaps into one (`setmaplayoutindex`: the
  lab with its table), is read off the engine's baked `native/layouts/<key>.mid`
  (`interior_specs.swaps` names the map's own layout, for its tilesets), and `placeRooms` stands
  it when the live cells match it better than the map's own layout. `init.lua`: `roomJob` reads every
  room in order in a coroutine (`Scene.ROOM_SLICE` a frame from the warm-up; `warm` queues it
  for an indoor map, `warmAll` always; to its end if a battle needs it first), `roomModel`
  builds a piece's model once, and `placeRooms` stands the pieces of the window's indoor layouts
  (own place, `placed`, `reused_at`, `bare_at`; a room's commonest floor and its own paint for
  a room nobody modelled) - pieces share cells, so a cell keeps the first piece's floor and the
  tallest top; a room read once per state of its doors (Petalburg's gym) finds another room's
  piece once per state, and the same model on the same spot stands once. Animated pieces
  (`anim`: Mauville's beams) find their extent in any frame (`anim_box`) through
  `io.animOver(layout, m)`, which reads the engine's baked tile-animation banks off their files
  (`native/<pair>/anim_manifest.lua`, then each frame's metatiles as 256 palette bytes, 0
  clear), whether or not the field has that map bound; their texels are the tiles as the map
  shows them (a battle does not step the field's animations). All 193 of their rooms (the later
  ones in functions of their own, `laterRooms` and `lastRooms`, as a chunk holds 200 locals; the
  Sky Pillar's floors and their `_CLEAN` twins swap either way).
  The job (`roomJob`): every room in order, then `reuse_everywhere` - the known furniture stood in
  every indoor layout nobody modelled, in the layouts' order (`World.layoutIds`) - and it is
  `ready` (`Scene.rooms()` runs it to there if a battle needs it first; ~15 s); then it builds
  every piece's model and writes the cache (Scene Cache: `rooms.index`, every piece's facts and
  places and the reused pixels per layout, as runs; `room_<name>.dat`, its pieces' triangles and
  their textures' sizes; `room_<name>.rgba`, the textures; each compressed, `love.data` zlib,
  "Z"/"R" prefixed). A battle then reads the index (~30 ms) and only the room files its layouts
  stand pieces from. The cache is keyed by `Scene.ROOMS_CACHE` and the specs' signature (each
  room's name and piece count). The reader yields from inside its heavy loops through a counted
  `step` (`stepTick`, the job's tick): no stretch between ticks over ~30 ms
  (`room_dump.lua` with `ROOM_CACHE=1` times the sliced build and the cache read, `ROOM_WATCH`
  lists the long stretches by room and phase).
  Checked against Emerald 3DS's own models: `tests/drivers/room_dump.lua` (`ROOM`: the last room
  read) writes every placement in each room's layout as their buildings.bin's dump does
  (`bld_dump.py <bin> <layout number> out 0 0`); all 188 layouts of the 193 rooms match triangle
  for triangle, colours and all, reuse included (a few texels a centroid reads just past a
  texture's edge are clear in both), and with `ROOM_EVERY=1` the furniture stood in the ten
  indoor layouts nobody modelled matches too (`room_#<number>.txt`).
- For an overworld view, unused by the battle scene: the deck tables (`Scene.decks(layout)`,
  export `sceneDecks`: `{ x, y, top, bottom, gate }` - Route 110's `Bridge.decks`, kept in its
  cache, and Fortree's `specs.decks`) and each model cell's shadow footprint
  (`Buildings.footprints(md)`: `cell_footprints`, 16 rows of 16 bits or false for a box; the
  bridge's blocks bring theirs from the world, `voxel_bridge._world_cover`; interior pieces will
  have none). `bridge_dump.lua` also writes the deck tables and every model's footprints in a few
  layouts (`BRIDGE_FP_LAYOUTS`): the bridge's footprints and tops, both deck tables (484 and 90
  rows) and Rustboro's and Fortree's footprints match Emerald 3DS's file. Slateport's bushes,
  bollards and battle tent do not: their meshes differ from that file's (the tent 878 triangles
  to 528), though they matched the Python of the source we port from - the pak seems built from
  another version of it.
- `props.lua`: `voxel_props.py`'s objects (sea rock, sand boulder, sea stack, Fallarbor's boulder
  and stack) and finder, over a layout's upper layer in subtiles (`World.subtiles`: the raw
  `metatiles.bin` of its tilesets; `World.neighbours`: its maps' connections, for an object a
  seam cuts). `init.lua`'s `placeProps` runs it on each map the window shows (`env.where`: map
  id and origin), then per variant (offset in its cells and what is drawn of it), once a
  session, builds the art from the cells' upper layer quarters (`World.art`), `K.withRing` with
  the spec's `ring`, and its part by `shape`: a `Mound` (`rise`, `step`; the default), a
  `ProjLathe` (the urn, the baskets) or `ProjDome` (the fruit) moved by the variant's half-cell
  offset, or a `Card` (the Battle Frontier's flags), `clip_art` cutting it to the drawing's box.
  Its cells lay their own drawing for ground, the object's quarters of the upper layer left out
  (the lower layer there). The flags' cloth is `live` (every pixel of its `live_tiles`), its
  frames read from the engine's upper-layer bank for it (`animFramesOf(pair, mid, true)`: those
  cells sit over animated water too, whose bank holds whole metatiles); `hd.stats.sceneLive`
  counts the live models in a scene.
- `buildings.lua`: in the game, per spec once per session: its reference template (the
  reference layout read through `Map.ensureMidLayout(Runtime._game, "EM_" .. name)`), its art
  read through `layerSource` (init.lua: the layout's metatiles' two layers off the cache's raw
  tilesets, `World.pretArt`'s `subtiles`, as `voxel_building.LayoutArt` reads them - the lower
  layer whole, also under a COVERED metatile's upper, which the engine's lower atlas has drawn
  over it; the atlases, `pixelSource`, only where the raw tilesets are not at hand), ground
  quarters (and with `ground_px` ground pixels) clear, `keep` applied. Read off the atlas, the
  battle tent's covered cells failed the ground test and left its lawn's dots standing round its
  foot as a fringe, its plan cut in narrow cells (878 triangles against 528). Every model placed
  in the 100 outdoor layouts equals Emerald 3DS's `buildings.bin` triangle for triangle
  (`bridge_dump.lua` with `BRIDGE_FP_LAYOUTS`, against `bld_dump.py`), but WoobleView's own
  `ever_grande_gate`. Only specs one of
  whose template metatiles the window draws are read. `find` places a spec wherever its core
  cells (match rows, drawn cells) repeat, but a spec with `owned` cells only where it is drawn or
  at its `repeat_at` places (the cell's place in its own map, `env.where`; gen_voxel_buildings's
  rule) (a primary-only core: any pair with the same primary;
  else the same pair; WoobleView's own entries: `gym_sootopolis`, the shared `gym` parts over
  Sootopolis's rect, its roof in the town's own tiles; `ever_grande_gate`, the gateway on the path
  up to the League, an `Awning` on its stone legs): the anchor exactly, the others exactly or by a look-alike metatile that
  draws the model's pixels in that cell, all but an eighth (Emerald 3DS's same_building_pixels,
  with that slack for the ground drawn round a corner: Rustboro's Center and Mart on its paving;
  a signpost's cell, or the cell its head tops, is asked its lower layer alone, off the atlas
  blobs, as their same_building_pixels asks it: Lavaridge's gym sign on the gym's corner).
  A placed model's cells (`cell.model`) draw its ground image and stand no card, tree or tile;
  `cell.top` (its height there) feeds the stage search like a card. The ground is
  `Buildings.groundPlan` (gen_voxel_buildings's find_placements, placement_ground, patched_cells,
  placement_patches), over the placement's own map (init.lua `groundCtx`: `env.where`, the
  layout's cells off `World.layout`'s grid, its colours off `World.pretArt`): the ground metatile,
  of the ring's open metatiles (not water, for a spec whose grounds are not) and the spec's own
  grounds the map paints (those that tile, if any), the one drawing most of what shows of the
  ground in the GBA's view (`exposed` less `covered`: the model rasterised in x, z - y), then the
  patches' edges and 16 a ring cell; `ground_fixed` over it where the map paints it. The map's
  paint is laid where the model draws nothing in the cells it paints otherwise than the template,
  but only where nothing of the model stands (`cellHeights`, the triangles clipped to the cell),
  and in all of them with `patch_own`, `patch_cells` or a component's `upper`; `cell_ground` and
  `cell_ground_at` lay a metatile whole. `relief_bare` cells (owned, nothing standing over them:
  Sootopolis's houses, Lilycove's beacon) take no patch; with quarters of the reference's upper
  layer to leave out (`cell.bareQ`) the relief goes on there (`B.bare`: the cell's metatile less
  those quarters, `lessQuarters`; `cell.reliefDrawn` then drops the model's ground quad), and off
  the relief that drawing lies flat (Emerald 3DS's dev branch, de38764). Masks and the patches
  read the model's texture (`texCover`: a `parts_art` texture of its own, as their `model.art`),
  not the drawing. Every one of the 283 placements in the 100 outdoor layouts lays the pak's
  ground metatile and its number of patches (`bridge_dump.lua`'s `P` and `G` lines, the pak's
  patch field six vertices a patch); components are placed in the window only and not in that
  check. Without the World's data, or with `exports._sceneGroundPlan(false)` (the battle
  driver's `SCENE_GROUND_OLD=1`, for before-and-after shots), the old rule: the commonest spec
  ground round it, the map's paint in every cell it paints otherwise.
- `models/components.lua` and `models/fence.lua`: the `components` specs (hedges, fences, curbs,
  railings, Sootopolis's walls, Lavaridge's spring, Slateport's crates), found at runtime as
  connected runs of their metatiles in one pair (`tilesIn`: `primary`/`secondary` names as the
  engine's pairs spell them, lower case without underscores; `also`, `skip`, `fill`), each run
  built whole: a `Relief` (the kernel's, column by column off the run's own drawing, after
  close_gaps, trim_outline, join_corners, fill_behind, pick_side and flank_band) or, with
  `posts`, `Fence.build` (posts found by their drawn caps, rails between them, logs, a ground
  Decal). A fence's reference metatile is read from any pair of its primary that draws it.
  `Buildings.kits` finds Rustboro's blocks by corner, top row, end and foot (`specs.kits`).
  Component cells lay the map's own drawing where the model draws nothing, and under it the
  ground metatile (or, for what is drawn on the upper layer, the cell's own lower layer).
- The atlases are split by draw order, not by metatile layer: `pixelSource` takes `image` as
  the lower layer and `overImage` as the upper, except for a metatile with nothing over whose
  `image` shows more than one colour where `midImage` is clear (a NORMAL one shows only the
  backdrop there): that one is COVERED, its upper layer `midImage`.
- `relief.lua`: terrain read off the drawing (Emerald 3DS's `voxel_relief.c` and the relief
  parts of `voxel_mesh_builder.c` / `voxel_atlas.c`): its `relief.bin` format (`Relief.parse`),
  cut tiles (`cutDiagonals`, `cutClear`, `cutTexture`), the seam step between maps, and a lifted
  cell's geometry (`emitCell`: its drawing on its 5x5 lattice at (u, h, v + h), a cut tile's flat
  layer and the ground run on under it, cliff walls, a back's north face; `treeStep`). In
  `init.lua`, `placeRelief` finds each cell's map (`env.where`) and layout id (the cache's
  `map_tree/maps/G_N/header.json`), places the maps by their bases and seam steps, and sets
  `cell.g` (heights), `cell.dy` (how high what stands on it is, tiles: a point h up also stands
  h south), `cell.lifted`; `emitRelief` draws the lifted cells from one texture of the drawings
  they lay (two passes). Trees, models, signs and flat cells are lifted by `dy`. For now the
  heights come only from a dev driver: `WOOBLE_RELIEF_BIN` names a relief.bin (Emerald 3DS's
  own, read locally to check the renderer, never shipped), which `scene_battle.lua` hands over
  through `exports._sceneRelief`; the solver's port comes next. `Relief.decode` / `encode` are
  `voxel_relief_fixes.py`'s lossless `parse` / `pack` (byte for byte, Python's round-half-even
  included); `Relief.view` is what the renderer reads.
- `relief_solve.lua` and parts (`relief_art`, `relief_input`, `relief_drawn`, `relief_shape`,
  `relief_cuts`, `relief_world`): `gen_voxel_relief.py` through `export()`, byte-identical to
  the Python on all 60 layouts (`world_maps.lua` feeds it the cache's raw tilesets, grids,
  events and the five script-swapped layouts). `relief_terraces.lua`, `_fit`, `_out`:
  `voxel_terraces.py` whole, byte-identical on all 29 groups (`S.T.apply(model)`); they need
  `opt.models(layoutName)`, the cells the building models own (`Scene.modelCells`: every spec
  placed over the whole layout). The whole chain, export → terraces → the last passes → encode,
  equals Emerald 3DS's shipped relief.bin byte for byte.
- The border round the battle map (Emerald 3DS's `VoxelMesh_EmitBorder`, `BorderWaterLevel`,
  `VoxelMesh_BorderLevel`, `EmitBorderSteps`, `EmitBorderNorth`): `init.lua` marks each cell
  past every map, but in a room (`env.walled`: Emerald 3DS's `indoor`, MAP_TYPE_INDOOR or
  SECRET_BASE from `def.mapType`; a cave has its border, and past its edges the stage search
  reads border, not void). `cell.border`: its metatile (the border block's, tiled as the engine
  tiles it, `env.borderMid`, or where the map's hand marks fill that edge the fill's,
  `Relief.edgeFillAt` over the relief's `edges`: phased from the map's corner, the west or east
  edge first past a corner); water or not (`env.waterMid`); `level` and `shift` (tiles, the
  cells' frame; `base` is the battle map's base there, `ring.lift`): water at the map's sea
  nearest it along the edge or a fill's top; land at the map's nearest edge cell's level
  (`steps`), a fill's top less two courses (its shift still the edge cell's), or the base past a
  sea edge; and `drawn`/`courses`, a map's own belt (`L.belt`: Lavaridge 2, Rusturf Tunnel 3)
  laid as its drawing, that many rows south, its top its own drawing and no faces.
  `render.lua` draws it in Emerald 3DS's frame (heights and rows over the base, so a north
  wall's bands and its run-on's rows fall where theirs do) and puts it in ours: water flat,
  land `Render.BORDER_COURSES` (2) courses (its top read from the row they rise over, faces only
  where it meets the map or water), steps down to a lower belt cell, the north wall up from the
  row behind, a band a level, that row's top run on to it and capped down the courses beside the
  map. `EmitSeamSkirt`'s belt cases: a map's edge cell under the belt north, west or east of it
  hangs a wall of its own drawing, point by point of its lattice, up to the belt; south of it a
  belt of trees has its drawing run on to the belt. Trees are trees. The stage search counts the
  belt two tall.
- Where two maps meet at different levels (the rest of `EmitSeamSkirt`, with `SeamEdge`):
  `render.lua` compares both edges point by point of their lattices, theirs over our map's base
  (`mapLift` apart); wherever ours stands over theirs a wall of the edge cell's drawing hangs down
  to theirs (west, east and south a cell with a cut record and a wall stands on its foot; north,
  not under the stretches its cut tile clears, `cell.northStands` from `Relief.cutClear` in
  `placeRelief`), and south, an edge a sliver short of theirs has its drawing run on to it, a row
  of the drawing a row of the gap. `scene_battle.lua` logs the skirts laid, by case, and their
  first cells (`sceneRelief`: "skirts: belt, seam, gap"). Not ported: the ease stretch (`VoxelBuilder_StretchZ`; no layout
  of the relief eases, so it never applies).
- The build's cost, measured in the engine at 3 ms slices: about 75 s for a whole cartridge.
  The solver's per-cell bookkeeping is kept as numbers (each canvas cell's counts packed, its
  commonest region worked out where counted; sub-tiles packed), not as tables: a million small
  tables made every collection pause 100-250 ms. `Art.setOrder` hashes only distinct keys (a
  repeat changes nothing in CPython's set), colour hashes are memoised, flood fills keep their
  stacks by index. `relief_dump.lua` has `RELIEF_FULL` (the terraces too), `RELIEF_GAPS` (every
  gap between yield points over 30 ms, where, and the heap across it), `RELIEF_BIG` (the
  reachable tables by path) and `RELIEF_GC` (the collector's pacing, to compare).
- `relief_post.lua`: the solver's last passes, after the terraces: `seaRamps`, `cutFeet`,
  `seamEases` (`gen_voxel_relief.py`) and `applyFixes` (`voxel_relief_fixes.py`) over a model,
  with `Post.json` (a JSON decoder that keeps object key order: the marks' edge fills are written
  in file order). `assets/scene/relief_fixes.json` is Emerald 3DS's hand marks, minified, contents
  and order unchanged. Each pass gives the same bytes as Emerald 3DS's stage outputs.
- `relief_run.lua` (engine side): the relief built once a game in the background and cached.
  It hooks `core.update`; each frame it runs the scene's model warm-up (`Scene.warmStep`: on
  `map.entered`, `Scene.warm` queues the specs that map's layout draws, readied one a frame, so a
  town's first battle no longer builds them all) and then one slice (3 ms) of the build: the
  solver (`world_maps.lua` over `relief_solve.lua` and its parts), the terraces
  (`relief_terraces.lua`, optional: without it only a cached relief is served), the last passes
  and `Relief.encode`. The bytes go to `mod.cache` under `relief/v<N>/<game>-<fingerprint>.bin`
  (the fingerprint: FNV of the cache's `census.json` and `layout_files.lua`), and to
  `Scene.setReliefBytes`. Drivers' frames skip the engine's update hook, so `exports._reliefStep`
  runs a slice by hand (`RELIEF_BUILD=1` in `scene_battle.lua`) and `exports._sceneWarm(mapId)`
  the warm-up (`SCENE_WARM=1`; `SCENE_WARM=all` the whole-game one). `SCENE_LOOK` takes an
  optional fifth field, a yaw in degrees east of north (the battle itself always looks north).
  `SCENE_PROBE=<spec>` logs a model's art (drawn / cleared, row by row) and its parts' bounds
  (`exports._sceneModelArt`, `_sceneModelBounds`, built afresh), `SCENE_PROBE_PNG=<spec>,...`
  saves each one's art as `art_<spec>.png` (`exports._sceneModelArtRaw`); `SCENE_PIXELS=pair:mid:x:y,...`
  a metatile's two layers at a pixel through the scene's pixel source (`exports._scenePixel`). The dev `WOOBLE_RELIEF_BIN`
  path still overrides it. **Scene Cache** (`scene_cache`, `Scene.cacheModels`): on the first
  `map.entered`, `Scene.warmAll` queues every spec; `ready` reads a model from `mod.cache`
  (`models/v<MODELS_VERSION>/<game key>/<spec>.lua`, a Lua chunk of its triangles, core cells and
  texture size, plus `<spec>.rgba`, the texture's bytes) or builds it and keeps it. A model's
  `ref` and `art` are recomputed (cheap; the art feeds look-alike matching). Bump
  `Scene.MODELS_VERSION` when the kernel or a spec changes what it builds. 104 models: 13 MB,
  built in 1.9 s, read in 0.85 s; `sceneModels` counts both.
- `roles.lua`: `voxel_cells.py` whole (every cell's role: water, ledge, stair, floor, signpost,
  wall, tree, fence, cliff, shelf), over an adapter of a layout; matches the Python cell for cell
  on 21 layouts. Its drawings are exact layers from the atlas blobs (`Roles.blobPixels`: colour
  index 0 left out, pret's colour rounding); `blocked` is the cartridge's collision bits.
- `world.lua` (engine side, battle-free): Emerald's layouts by the cartridge's layout id (from
  `map_tree/maps/G_N/header.json`, `events.json`, `grid.bin`), their maps' warps and sign events
  joined as `voxel_cells.MapEvents` joins them, `roles.lua` adapters over them, the game's sign
  posts and each layout's roles, cached once a game. `signs.lua` asks it in Emerald
  (`opt.signpostAt`). The raw tilesets are in the cache too (`map_tree/tilesets/ts_<ptr>/`:
  `metatiles.bin`, `tiles.4bpp`, `palettes.bin`, `attributes.bin`).
- `render.lua`: static meshes per atlas and layer (ground quads, then cards, then trees, then
  buildings); a shader that
  outputs screen pixel x depth through LOVE's own projection with the view depth as w (so the
  ground is perspective-correct and LOVE's canvas flip still applies), depth-tested, fogged
  into a haze colour (the wallpaper's top colour outdoors, black indoors).

In `src/gen3.lua`, `fitTerrain` records `hd.world(wallpaper, scene)` and two soft shadows as
stage items instead of the wallpaper and pads; `drawEntry` skips the intro bands. The `"world"`
item is drawn by `hd.composite` (and `compositeCard`) through `hd.sceneRenderer` with the
scene's mapping, in the wallpaper's recorded colour and shader (move dims, flashes); the
recorded transform is the background's shake. `flatten` puts the wallpaper back. The intro's
progress is the battlers' slide (`enemyOx` -240 to 0).

The battle scene is adapted from Emerald 3DS (CC BY-NC-SA 4.0), which is why WoobleView is
CC BY-NC-SA 4.0 from this version on (LICENSE names what was adapted and how). Keep any further
material taken from it credited there.

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
| `flip` | `true`: the `texture`/`quad` frame is drawn mirrored about its `pivot` (a stand-in the mod drew mirrored; `lowPivot` is in the stand-in as drawn). Check `features.flip` |
| `shades` | a shader: the stand-in is in the Game Boy's four shades, made by this shader from the frame's colours. The `texture`/`quad` frame is drawn through it and then coloured as the stand-in is: in Gen 1 into a canvas a whole number of times the pass's size, then through the Renderer's blit (its SGB zones); in Gen 2 (a direct pass) 1:1 into a canvas, then drawn under the palette shader in force. Without it a tagged frame under a shader falls back to the stand-in. Check `features.shades` |

Also `untag(image)`, `tagOf(image)` (the spec an image was tagged with, or nil: a mod that
draws a tagged pic outside the battle, field and Pokédex passes can draw the full-resolution
texture itself), `isActive()`, `enabled(pass)`, `setEnabled(pass, on)`, `cap(pass)`,
`setCap(pass, n)`, `features` (`{ quadPivots = true, dex = true, battleFit = true, tagOf = true, flip = true, shades = true }`),
`fitEnabled()`, `setFit(on)` (the old `"off"` / `"fit"` / `"tall"` still work), `fillEnabled()`, `setFill(on)`,
`sceneEnabled()` / `setScene(on)` (Battle Scene: OVERWORLD), `sceneZoom()` (the battle scene's zoom this
frame; 1 = none), `sceneDecks(layout)` (a layout's deck table, for an overworld view: see Battle
Scene) and `stats()` (`splits`, `composites`, `flattened`, `overCap`, `zoom`,
`zoomTarget`, `lift`, `extraLift`, `hiddenEnemyUI`, `hiddenOwnUI`, `backTop`, `shiftEnemy`, `shiftPlayer`, `dropPlayer`, `raisePlayer`, `fill` (the scene's scale over the Renderer's, 1 = none), `uiScale`, `uiTopDy`, `card`, `grow`, `inward`, `topY`, `uiK`,
`failed`). The export `version` is 2. Tags are weak: an image that is freed drops its tag. Keep the tagged
image itself a real low-res picture: it is what shows whenever a frame falls back.

## Tests

`luajit tests/hd_test.lua` (a fake `love.graphics`; no game needed). Every test file is listed by
exact path in `.modkitignore`. The drivers in `tests/drivers/` run in the game
(`POKEPORT_DRIVER`, each file's header says how) and screenshot what they check; for the Game
Boy games: `gen1_battle.lua` (with `GEN1_INTRO_SHOT` and `GEN1_COLORS`), `gen2_battle.lua`,
`field_gb.lua` (Field HD with Vivid Worlds: OG), `screens_gb.lua` (Red's whole screens) and
`dex_gb.lua` (the Pokédex and summary in each colour mode, HD on and off). Battle Scene:
`luajit tests/scene_test.lua` (camera, cells, stage search, vertices, trees, the building kernel,
specs and placement, look-alike cells, solids, component runs, fences, kits, signs, relief and its
last passes), `luajit tests/roles_test.lua` (the cell roles) and the drivers
`scene_battle.lua` (`SCENE_SPOTS`, `SCENE_LOOK` for shots aimed elsewhere, each also saved as the
scene alone through the test hooks `exports._sceneLook` / `_sceneShot`; it logs every placed
model with its cell, every component run with its triangles, every sign (cell, metatile, head),
the relief's lifted cells and layouts (`sceneRelief`) and the build time phase by phase
(`scenePhases`);
`SCENE_DUMP` for collision codes, `SCENE_SELFTEST` for the
renderer on a synthetic field), `bridge_dump.lua` (the Cycling Road's triangles, its sliced build
and its cache read; see `models/bridge.lua` above), `room_dump.lua` (the rooms' pieces; see
`models/interiors.lua` above) and `roles_dump.lua` (`ROLES_LAYOUTS`: each layout's roles as
`voxel_cells.py` prints them, to diff). The relief is checked against Emerald 3DS's own scripts
run locally: pret's pokeemerald at their pinned commit with its graphics built, their
`3ds_port` overlaid, `romfs/voxel/buildings.bin` in place, Python 3.13 (their pinned version;
3.14 changes the output); the stages after export are then compared byte for byte.

Keep [README.md](README.md) describing the mod as it is now (players read it).
