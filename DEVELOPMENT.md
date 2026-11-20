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

Every clip to the game screen's box goes through `hd.scissorOver(x, y, w, h)`, never a bare
`setScissor`. LÖVE drops a scissor's fractions in units and again in pixels after the DPI scale,
so on Android's 2.625 DPI a box lost up to four pixels at its right and bottom and whatever was
under the screen showed there (a white line beside Gen 2's panel with Battle Fit off).
`scissorOver` goes out to whole units, and one more on a fractional DPI. A sprite's own clip
(Gen 1's UI sprites) stays a plain scissor.

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
  is ours too. Gold paints it round the panel after `drawWidescreen` (`Game2:paintBattleSurround`;
  for world, over the overworld it drew first, with `Chrome.worldSurround` set so
  `Chrome.letterbox` paints nothing). `present` lays the battle's white paper itself: the whole
  window when Fill Screen is on, else only the panel's box, so the world shows round it. A frame
  the battle filled the window in (`filledFrame`, Game2:draw's count) skips the surround, which
  would paint its bars over the battle (`stats.surroundSkipped`). Without that seam or the frame
  count, only a white background's battle is taken (`paperOk`).
  **No Fill Screen in Gold, Silver and Crystal** (`fit.fillAllowed` false, set in main.lua; the
  option row is dropped from their schema and `exports.setFill` cannot turn it on). Facets paints
  its battle scenes (BATTLE BG) into the panel and into the window round it
  (`render.letterbox`); a filled battle is the panel grown about its line, so the two met in a
  seam at two sizes, and other mods' Gen 2 art is drawn for the game's own screen. The adapter's
  fill paths (`view`, the stacked layout, `drawSliding`, the surround skip) stay but never run.
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

The own-size rule below, the side shift and the player's drop apply to the classic backgrounds.
In the 3D world (Battle Scene: OVERWORLD) the battlers stand at the world's scale instead: see
**World scale** under Battle Scene.

**Own size** (`ownSize` in `src/hd.lua`, Battle Fit on, singles and doubles): a battle Pokémon
(a side's tag, not a trainer's, with a full-resolution `texture`) is drawn at its tag's own
`scale`, the sprite mod's, unless that is too big for its room (`fillScale`): then just small
enough to fit it. No sizing by species height, no pairing of the two sides, no lift for a small
back. (Until 2026-11 Battle Fit sized both sides to one scale by their species' heights, with
`sizeCurve`, `nearScale`, `sizeFloor`, `minShare` and a raise for small backs; the 3D world's
real sizes replaced it, and the classic battles went back to the sprite mod's own sizes.)

- **The room** (`fillScale`): the stand-in's box (the picture box the game draws) grown by the
  layout's `fitRoom[side]` (`up` rows above, `left` / `right` columns beside), the art kept
  inside it above and beside its feet (`lowPivot`, which stays put). The art is the tag's `art`
  box (its union over the animation), else the frame from its `top` down. The player's room
  reaches up to the enemy's HP box's bottom wherever the UI puts it over the scene (`uiTopDy`,
  `uiK`, `sceneUp`).
  - **Gen 3:** the enemy's up to the screen's top (8 rows), the player's up to the enemy's HP box
    (it stands on its pad, the UI over its lower rows as in the cart), each 16 columns wider.
  - **Gen 1 / 2:** the enemy's out to its HUD and the screen's edge (its box already starts at
    the top); the player's up to the enemy's HUD (row 32) and out to the screen's edge and its
    own HUD.
- **The camera** (`fitSolve`): only for what would leave the screen: the enemy's art under the
  screen's top, each back's whole animation (`r.top`, a head flung up) on it. The HP boxes and
  the text box may cover a Pokémon, as on the cart (`hiddenEnemyUI` / `hiddenOwnUI` in the stats
  say how much). `hd.pair` (each side's latest tag) is still kept for `topLimit`: with a pair
  the camera's top `margin` is 0.

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
  - **Headroom:** the resting body's top is no higher than `fit.backTopMin` = 44, the enemy's
    HP box's bottom (y 16–44; the tallest cart back sprites, Tyranitar, Steelix and Meganium,
    start 8 px lower, at row 0 of the 64×64 back box centred at y = 80 + 4), so the head never
    sits behind it; with the box raised (`topGap`, Fill Screen) the headroom
    rises with it. On Gen 1 / 2 it is the enemy's HUD's bottom (row 32).
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
  - **Aimed at the body (the 3D world's singles):** a move aims at `AnimCoords.SINGLES`, the
    middle of the cart's 64 px pic box (the foe's row 40, its feet at 72). A Pokemon drawn at
    its true size stands at its feet, so a small one's body lies well under that, and an
    effect landed over its head (more so zoomed in on it). `fitStep` notes each side's art
    middle where it rests (`(artTop + feet) / 2`, canvas px, unzoomed; trainers left out) as
    `fit.aimEnemy` / `fit.aimPlayer`, and `Engine.shiftCoords` puts `SINGLES[1].y` /
    `SINGLES[0].y` there (else their own rows, the player's with its shift). Not the intro's
    `ENEMY_MON` / `PLAYER_MON` (ball targets).
  - **Effects grown with a giant** (the 3D world's singles, `fit.fxGrow`): `fitStep` works out
    each side's growth, its world scale over the sprite mod's own (`e.k / spec.scale`), at
    least 1, at most `fit.fxMax` (4): `fit.fxEnemy` / `fit.fxPlayer` (a Wailord before a
    Pikachu 1.69, the Pikachu 1). `Engine.shiftCoords` hands over the line the moves run
    along, `fit.fxLine` (player's aim to the foe's), while either grows. The wrapped draw grows
    each piece of a move's animation (`hd.inAnim`; not a tagged picture, a canvas, or one
    `fit.fxBig` (0.6) of the canvas across: a background) about its own middle by the factor
    where that middle lies on the line, the player's at 0 and the foe's at 1 (`fxFactor`): the
    current transform scaled about that canvas point for the one draw. A beam's pieces widen as
    they near a giant, a cone; positions stay where the move puts them. `stats.fxGrown`.
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
  - **Planes** (`planeTile`; with or without fill): WoobleDex's Gen 9 animations (its `NdxEss`
    task) draw an Essentials plane, a background or foreground repeated across the screen, as
    copies of one atlas rect on a grid from the canvas's top left, scrolled (`drawPlane`:
    Surf's foe-side wave, 286 x 480, rising; Steam Eruption's mist sliding sideways). Together
    they always cover the canvas, alone they don't once it scrolls, so each copy was zoomed with
    the scene and cut off at the canvas's edges. An upright, unscaled quad at least 48 px a side
    reaching over the canvas's top left corner starts a run (`cur.plane`); the same picture next
    on its grid continues it; the run is one `screen` layer, as a single whole background is.
    `stats().plane` counts runs.
  - **Rows** (`rowTile`, `drawRow`; with fill): pieces of one width side by side across the
    canvas, sharing their top or bottom row (WoobleDex's Surf from the player's side: its wall
    of water, the crest and the water pieces by turns, placed on Essentials' screen). Upright,
    unmirrored quads at least 64 px wide; once a pass's pieces reach both sides, each the last's
    width along, a `row` item is recorded (it opens no layer). The composite carries the row on:
    an end piece that carries it (`carryLo` / `carryHi`, below) repeated out to the view's
    sides, and a piece reaching the text box's line (the cart's text box hid the rows below it)
    run on down from its foot (its last texel row) to the view's bottom, inside the canvas's box
    too. The row's own pieces are drawn in their layer, or uncut past the canvas's edges
    (`freeDraw`, below). `stats().row`.
  - **Mosaics** (`mosaicPiece`): big upright quads (48 px a side or more, none covering the
    scene alone) drawn one after another that together cover the canvas down to the text
    box's line (Seismic Toss's starry sky: six different tiles in two rows, so no row repeats).
    Seen covering it in a battle pass (`self.mosaicNext`, keyed by picture and viewport), its
    pieces are `screen` draws in the next (`self.mosaicNow`): one whole-scene layer, a frame
    late.
  - **Effects past the canvas** (`freeDraw`, `drawFree`; with or without fill): a layer is the
    canvas's size, so a move's effect drawn partly past its edges was cut off there, though
    zoomed out the view shows past it (a slash on a giant near a side, a burst low on the
    player's side). An image draw in the scene that crosses an edge (its corners through the
    draw's own rotation, scale and origin, and the transform: partly on the canvas, partly off;
    one wholly off may be parked there to hide it, unless a move's animation draws it,
    `hd.inAnim`, within a canvas's size of the canvas: a giant of the player's stepped out past
    the left side has its moves aimed at its middle there, x -49 for a Wailord) is recorded as
    a `free` item, its quad's
    viewport as drawn, and replayed in the composite at the scene's mapping, clipped only by the
    view. Up to 48 a pass (`freeMax`), the rest in their layer as before. A row's pieces
    crossing the edges are drawn this way; the row adds only what lies past them.
  - **Which end carries a row on:** the row's lowest piece (its body: a wave's water, the
    crest standing taller above it), and a piece seen repeated in a row before (`rowSeen`,
    weak by picture), even when it shows only once in this one (Muddy Water's last frames); the row's run-on is also drawn inside the canvas below its pieces' feet. A row
    no longer opens a new layer after it.
  - Checked in game with `tests/drivers/ess_scene.lua` (WoobleDex in mods/: its animations in a
    3D battle, both sides, shots and frame times; `MOVES=`, `HD_PLAYER` / `HD_ENEMY`, `HD_SIZE`):
    Spacial Rend, Springtide Storm, Seed Flare, Shadow Force, Surf, Spectral Thief and Steam
    Eruption cover the view at zoom 1, 0.49 (a Wailord) and 1.8 (two small ones), wide and
    upright. `move_edges.lua` logs `plane` and `row` per move. `COVER=1` measures every 6
    frames how much the view's outer 8% a side and its middle 30% changed from the battle before
    the move: "boxed" when the middle changed (over 30 of 255) and the sides did not (under 6),
    a background stopped at the canvas's box; all 168 WoobleDex animations with a background or
    big screen pieces are swept that way at Wailord's zoom (0.49).
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
- **No lift for a small back:** a back stands on its pad where the game puts it, however
  little of it shows over the text box (`shift.playerRaise` stays 0; the engine's coordinates
  still read it). Until 2026-11 a small back was raised until enough of it showed.
- **Battlers as they rest:** before the UI seam, `src/engine.lua` (`Engine.prefit`, inside the
  battle's draw) asks `Pokemon.frontPic` / `backPic` for both leads, so a sprite mod hands over
  its battle pics. It hands each to `hd.prefit(side, image, x, y)` at the spot
  `Ui.battlerSpriteCenter` gives (origin 32, 32). The fit uses these resting placements for
  their sides instead of the drawn pics. So in a trainer battle the camera is framed for the
  Pokémon before they are sent out, and a send-out jump or an attack's lunge never moves it.
  In a double battle each battler still in (not `st.absent`, HP above 0) is reported on its own
  unshifted spot (`home.doubles[id]`, `Ui.battlerSpriteCenter(id, ...)`), keyed by its id
  (`hd.prefit(side, image, x, y, id)`); a side with any report is fitted by its reports alone.
  Without this, the target cursor (which hides the picked foe every other beat:
  `Ui.targetHidden`) moved the camera with each blink. Portrait was worst: Fill Screen's
  growth jumped every few frames. Drawn pics are used where nothing was reported (Red to Crystal).
- **The 3D world's single battles frame what is out** (`live` in `fitStep`: `tuned()`, not a
  double battle). `Engine.prefit` passes each lead's `present` (`hd.prefit(side, image, x, y,
  nil, present)`): false while its sprite is not up (`Anim._present[0 / 1].visible`, false
  before its send-out and after its faint, withdrawal or Fly). Such a record (`rec.out ==
  false`) is still sized but not framed, nor is its side's drawn art (a send-out grows it). The
  adapter also reports the opposing trainer (`hd.fieldTrainer(Anim._stage.trainer.enemy.visible)`,
  `cur.trainerOut`). The camera starts each battle at zoom 1 with no rise (not at its target),
  pulls out for the foe once it is out, and is framed again when the player's is; the zoom-in
  for small ones waits for both. A side that was out (`fit.wasOut`) and is not holds the target
  (`fit.target` / `extraTarget`) and the HP box (no re-placement) until a Pokémon is out again,
  the next one reported before its send-out included. The trainer shown with no foe out (its
  intro, its last words) sets the target to zoom 1, settled at once, so the trainer is drawn at
  its size. Not held back by `fit.turn` (below): framed at rest and only as the Pokémon come
  and go, it follows a send-out mid-turn. Until 2026-11 both leads were framed from the
  battle's first frame, before either was out, and a faint let the camera come back in.
- The zoom snaps to the target at a battle's first frame (the 3D world's singles: at 1) and
  eases out about 20% per frame. The extra rise eases the same way.
- It eases back in about 5% per frame, but only after the target has stayed larger for 45
  frames.
- **Not back in while a turn plays.** Before each battle pass the adapter calls
  `hd.setTurn(on)`: Gen 3 when `Battle._phase` is anything but `command`, Gen 1 any
  `BattleState.phase` but `menu` / `moveSelect` / `mimicSelect`, Gen 2 any but `menu` /
  `submenu` / `moves`. While `fit.turn` holds, the zoom and the extra rise may still pull out at
  once, but the hold never counts, so they never come back in. Fill Screen's growth (`fit.grow`)
  does not grow back meanwhile either. Back at the menu the 45-frame hold applies and it eases
  in. Without this, a move that swells, lifts or lunges a Pokémon for a moment (Bulk Up,
  Growth, a jump) pulled the camera out and let it back in, move after move. That happened
  wherever no resting pose is reported: Red to Crystal (and Gen 3's double battles, before
  they reported theirs).
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
- **The enemy's HP box raised** (Gen 3, `fit.topGap` = 2 UI px; a double battle's foes' two
  boxes moved up as one, since 2026-11): on a wide screen the
  battle fills, the top band (the rows above `fit.split`) is blitted so the enemy's HP box's top
  (`fit.ui.enemy[2]`) is `topGap` under the screen's top, the player's HP box's gap over the text
  box, as the stacked arrangement moves it (`dyTop`, `banded`; `noteUi` records it for `uiMap`).
  The fit sees it there (`fit.uiTopDy`), so the player's Pokémon has the rows it left. Not on a
  frame whose UI crosses the split (the straddle guard), not with Fill Screen off
  (the game's own frame).
- **Gen 2's intro slide** (`drawSliding` in `src/gen2.lua`): the game slides its halves in the
  way the cart's scroll does (`BattleAnimView:presentSlide`: bands blitted row by row, shifted,
  the back pic over them from the right), inside its 160-px panel. With Fill Screen the panel is
  drawn unshifted, the enemy's pic moved by the top band's offset (`slideOffsets`) and the back
  pic by its own (`slideBackpicOffset`), every pic at window resolution (an untagged one, a
  trainer's, tagged for the frame as `{ side, trainer = true }`), the intro's `BLACKOUT` palette
  a dark tint (a shader would send a full-colour frame back to its stand-in). So both are on the
  screen from the first frame. The bands' scroll of the paper is not kept.
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
    - The enemy's HP box (a double battle's two foes' boxes too) has its top `fit.stackGap` (2) UI
      px under the scene's top in every game:
      its canvas row 0 at the scene's scale, or the screen's top when the scene reaches it (as
      `topGap` on a wide screen). Gen 1 / 2 have it on the cart's top row. It never moves with
      the art; the fit sees it there, the upper limit for the player's Pokemon. The spot
      (`fit.anchor`, UI px) is held while a turn plays (Gen 2 fits drawn pics, so a lunge may
      pull the scene out a little) and eased (`inRate`) to the scene's top between turns; set
      afresh each battle. (It used to hug the highest art, `fit.artTop`, and bounced on a
      phone with every move that drew a Pokemon lower, Gen 2's Body Slam, and with sprites
      animating at the menu.)
    - **The straddle guard:** a visible UI draw that crosses the split but does not cover the
      whole canvas (the level-up window, the intro's closing wipe) sets `cur.uiStraddle`. That
      frame's UI is drawn in one piece.
    - **The enemy's HUD as its own layer:** a game that draws the enemy's HUD through a call of
      its own puts `hd.seam("uiTop")` / `hd.seam("uiTopEnd")` round it (Gen 2's
      `drawEnemyHud`, WIDE's `drawTopHud`). That layer is then the top band, moved whole, and
      the rest of the UI stays put, so the straddle guard is not needed: what mods draw inside
      the call goes with the box (Facets' BATTLE UI boxes, National Dex's chips under it), and
      what they draw by the player's box stays there. National Dex's Stat Hints stack the
      player's chips up from its box past the split row; on the rows' banding that was a
      straddle every frame, and the enemy's box dropped to its cart spot over the player's
      Pokemon. Gen 1 and Gen 3 keep the rows.
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

**Safety.** Every engine hook calls into this mod under `pcall`. An error goes to
`hd.fail(err)`: it is logged with its count ("failure n of 3"), any pass in flight is flattened
back into its canvas, and nothing is captured for `hd.retryAfter` (2 s); then `hd.recover`
(each `endFrame`, `beginPass`, `beginDirect` and `hd.down()`) captures again. The
`hd.maxFailures`-th (3) turns it off until a restart (`stats().failed`, `stats().failures`).
While it is down the exports report it off (`isActive`, `enabled`, `fitEnabled`: `hd.down()`),
so a sprite mod draws its own plain sprites, not the stand-ins it leaves for this mod (a big
back's close-up in the 64-px box, drawn by the game it looked several times too large), and
Gold's draw wrappers (`hd.down()`) leave the battle to the game. Before, the first error was
for the whole session and the exports kept saying on. `hd.canCapture()` is false when the
engine presents without the Renderer (`Display.planesBroken`, its Android fallback), since a
captured pass would never be composited there.

If `BattleChrome.drawTerrain`, `BattleChrome.terrain` or `BallOpen.draw` is missing,
`fit.available` is false and the option does nothing. The HD sprites are unaffected.

## Battle text box (Gen 3: `src/bar.lua`)

Ruby, Sapphire and Emerald, option `battle_textbox` (`hd.barEnabled`, default on), with a
battle pass (Battle HD on). FireRed / LeafGreen keep the cart's boxes (`Bar.LAYOUT` has no
`frlg`).

- **The bar:** canvas rows 124 to 160 (`Bar.TOP`, `Bar.BOTTOM`: 36 rows, three quarters of
  the cart's 48 from row 112), across the view's whole width. Panels by panel mode: `none`
  one message panel; `menu` the message panel to the action menu's; `moves` two menu panels.
  The menus' panel starts at the cart's frame column (`Bar.LAYOUT[...].split`: Emerald 120 /
  160, Ruby and Sapphire 136 / 176) moved right with the UI's right margin, so it keeps its
  width and ends on the screen's right edge (`Bar.splitX`).
- **The look:** `Bar.pixel` (signed distances, straight alpha): a frame (gradient, a light
  rim at its top), a line inside it, the panel (gradient, an inner shadow under its top), a
  soft shadow cast up onto the scene. Message: red frame, grey line, teal panel; menus:
  purple-grey frame, light line, white panel (the cart's colours, Emerald 3DS's HD text box's
  layering). Ends on the screen's edge are rounded, ends where two panels join square and
  thinner. Each panel is drawn from three cached pieces per scale: its left end, one middle
  column stretched, its right end (the left one mirrored); `Bar.reset` drops them.
- **`hd.paint(fn, a, hide)`:** an item the composite runs at the screen's resolution in the
  pass's order (over the UI drawn before it, under what comes after), told where the UI is
  (`x, y, sx, sy`), the view's sides (`l, r`) and the UI's margins (`extraL, extraR`). `hide`
  (row 112): the UI's layers before it are cut off there, as the cart's text box hid them (the
  bottom of the player's HP box art). A flattened pass calls it at 1x.
- **`hd.bar(spec)`:** what the pass draws until `hd.bar(nil)` goes into layers marked with
  `spec` (`top, bottom, dy, split`). The composite blits such a layer `dy` rows down (Emerald
  4, Ruby and Sapphire 6: the two lines centred in the bar), clipped to the bar's rows; left
  of `split` moved left with the UI's left margin, the rest right with its right one. So the
  game's own text and cursors land in the bar whichever font or printer drew them.
- **The seams (`Gen3.wrapBar`):** `BattleChrome.drawPanel` paints the bar instead and opens
  the text window; `BattleChrome.drawMenuFrames` is skipped under it; `Ui.voiceoverDim` (called
  right after the menus in `Ui.draw`) closes the window; `Message.draw` (the battle's message,
  drawn after the battle) gets a window of its own; Ruby / Sapphire's red cursor
  (`rs.menu_cursor.draw`) is widened `Bar.CURSOR_PAD` px left, off its text. Each battle frame
  (`Gen3.barFrame`) the trainer's back is pinned to the bar's top and the fit's text-box rect
  (`fit.ui.text`) starts there, else at 112.
- **Standing down:** nothing is painted while `Ui.bottomUIVisible()` is false (Kanto Gear's
  GEAR / FULL GEAR take the battle's menus to their own screen; its hook hides them), and the
  battle's message is then not drawn either (every Gen 3 game, Oak's voiceover excepted), so
  no text is left floating over the scene. Without a battle pass the game's own boxes draw.
- **Driver:** `tests/drivers/portrait_battle.lua` with `HD_BAR=1` shoots the first message, the
  menu and the move menu; `HD_PLAYER` / `HD_ENEMY=SPECIES_X:level` the battlers; `HD_FILLOFF=1`
  Fill Screen off; `HD_HIDEBOTTOM=1` the bottom UI hidden as Kanto Gear hides it.

## Battle Scene (Gen 3)

**Battle Scene: OVERWORLD** (`battle_scene`, `Engine.Scene`, `hd.scene`) replaces the battle's
wallpaper and pads with the map around the player, in 2.5D. It needs Battle Fit (it rides the
battle pass) and is Gen 3 only.

**HP box hooks** (`hd.boxBegin(id, ox, oy)` / `hd.boxEnd()` in `src/hd.lua`; Gen 3's adapter
wraps `Healthbox.draw` with them, outermost, re-wrapping whenever another mod wraps it later, so
Wooble Dex's badges or Facets' box pictures drawn with a box fall inside). `id` is the battler
(singles: 1 the foe's, 0 the player's), `ox, oy` the game's slide-in and bounce. They do nothing
unless `hd.boxLayers` is set; nothing sets it yet. Set, each box draws in a layer of its own
(`item.box`) with its drawn bounds kept in `cur.boxes[id]`, so a composite could move a box
whole. (A first 3D placement built on them, fixed corners with the Pokémon packed around the
boxes, was dropped in 2026-11; it is kept in a git stash, "hp-boxes: 3D custom positioning".)

**World scale** (`worldSize` in `src/hd.lua`): when a pass draws the world (`hd.world` sets
`cur.world`; the composite and `endPass` copy it to `hd.worldScene`), each species tag with a
`height` stands in it at the world's scale in place of its own size (`ownSize`). All of it, and
everything below that fits the battle round those sizes (the soft ceilings, the zoom in, the
step outward, the foe's HP box over the heads, the doubles' rules, the scaled shadows), is
behind `tuned()` (`hd.worldTuned`): the world drawn and `fit.worldSizes` on, the **3D Sizing**
option (`scene_sizes`, main.lua: Off / Minimal / Medium / Accurate, `fit.sizeMode` the last three;
a saved true / false of the old toggle reads as Medium / Off and is rewritten so by
src/prompt.lua's tick once a game runs). Off, the world's battlers are drawn and framed as outside it
(`ownSize`, `fitSolve`, the camera's fit across the scene's edges); the sides still stand on
their ground (no side shift or drop: those are for the classic platforms):

- `k = height / Scene.METRES_PER_TILE (1) * pxPerTile / artPx`. `height` is the real height of
  the tag's art box (feet row to the top of the art over its animation; WoobleSpritePack measures
  it per sprite, a back's corrected for its own animation), eased under a soft ceiling:
  true to size up to `fit.heightKnee` (3 m), a taller one at `knee + (max - knee) * (1 -
  e^-((h - knee) / (max - knee)))` toward `fit.heightMax` (5 m; a foe's `fit.heightMaxFoe`,
  4.5 m), so the taller stays the taller (Groudon 3.5 m drawn 3.4, Steelix 9.2 m and Wailord
  14.5 m just under 5). Tuned at half a metre a tile as 1.5, 2.5, 2.25 and 3 m (width); back at
  a metre a tile they were doubled, or the giants came out half as tall. Hard caps came first
  (Raging Bolt's 5.2 m, 3 m, then 2.5 m, at half a metre a tile):
  a player's Wailord filled the screen, and a hard cap drew every giant the same height; then
  at `fit.widthMax` (6 m) across:
  the art box's width in metres at that height (`height * artW / artH`), a wider one's height
  scaled down to fit it, so a wide giant (Wailord) shrinks and a tall, thin one (Steelix) keeps
  its height. Both before the indoor ceiling. A metre a tile: half a metre was tried in
  2026-11 (Pokemon looked small against the houses and trees at a metre), but a 2 m Pokemon
  then stood as tall as a house, the player's, nearer the camera, taller. `artPx = hpy - art[2]`.
  `pxPerTile = Scene.groundScale(scene, X, Y)`: `Camera.F` over the depth of the ground under the
  feet's canvas point on the settled pose `s.to` (33.8 at the foe's feet, 44.7 at the player's).
  Perspective comes from the depth, not `nearScale`; `sizeCurve`, `sizeFloor`, `minShare` are not
  used.
- **3D Sizing's choices** (`fit.sizeMode`; singles only, a double's four as Medium):
  - *Medium* (`"medium"`, the default): everything here.
  - *Minimal* (`"minimal"`): Medium's final scale, its floors' raise included, as metres where it
    stands (`k / perM`, `perM = ppt / (METRES_PER_TILE * artPx)`), drawn toward
    `fit.minimalMid` (1 m) by `mid * (h / mid) ^ fit.minimalPow` (0.75). Applied after the
    floors: before them, Medium's floors lifted a small one past its curve, so a Capsakid stayed
    as it was while the Dewott beside it grew. `e.lift` (the raise the zoom-in leaves out) is
    Medium's, curved alike. Pikachu by Wailord drawn as 0.70 m and 3.0 m (Medium 0.62 / 4.34),
    Capsakid by Dewott 0.58 / 0.87, Zigzagoon by Blaziken 0.62 / 1.62.
  - *Accurate* (`"accurate"`): the tag's height as it is (WoobleSpritePack's measured art height,
    the same dataset as WoobleDex's `artHeightOf(...).art`: Wailord 6.36 m): no soft ceiling, no
    width cap, no share of the tallest or wide raise, only `fit.worldMinAccurate` (4%) of the
    battle's height; the camera's furthest view (`e.most`) and a room's ceiling still hold it.
    Pikachu by Wailord: the camera at `zMin` (0.4), Wailord 6.35 m, Pikachu its 0.4.
- The smallest: its art's longest side (height or width of the art box: a flat Wishiwashi
  counts its width) at least `fit.worldMin` (0.1) of the battle's 160 rows, and at least
  `fit.worldShare` (0.2) of the art height of the tallest on the field (`e.px`, canvas px
  before the zoom, after the caps, of the entries for `hd.pair`'s two), both before the zoom
  (`k >= max(worldMin * 160, worldShare * tallest) / side`; `e.raised`). Above it, true to
  scale; the largest limit wins over it. Until 2026-11 `worldMin` was taken after the zoom
  (`/ fit.z`), so it grew as the camera pulled out for a giant: a wide screen pulls out for a
  foe's Wailord (0.49) and an upright one, with room above, does not (1.0), so a Pikachu beside
  it was drawn smaller on the upright screen (0.39 against 0.48). `worldShare` matches what the
  wide screen drew (the small one's art 14-16% of the giant's for Wailord, Groudon and Steelix
  pairs) on any screen. At 12% after the zoom a Pikachu beside a Wailord stood half a tree tall
  and Wishiwashi as big as one. Raised from 0.07 / 0.155 (2026-11-20): on an AYN Thor (a 6"
  1920x1080 screen) a Capsakid before a Dewott stood 75 px of 1080; with these and the small
  foe's zoom-in below, about 1.8 times that.
- A wide one (its art box wider than tall): both floors times its width over its height, at
  most `fit.wideFloor` (1.4; `e.widen`). By its length alone a long, low Zigzagoon (1.38 to 1)
  stood a quarter of a Blaziken's height on an upright phone and read as lost; with it, 27-38%
  bigger beside a Pupitar, Manectric or Blaziken. A tall or round one is unchanged.
- Wide ones step outward (singles; `fit.wideLine`, 0.4): after the camera has eased, a side
  whose art (its own, not the platforms) reaches past the line is shifted toward its own edge,
  partly off the screen: the player's art's right edge no further right than 40% of the screen's
  width (`viewL`/`viewR`) from its left, the foe's left edge no further left than 40% from its
  right. It is the side shift (`fit.shift.player` / `enemy`, canvas px before the zoom), so the
  shadow and the engine's battler coordinates follow it. The camera is fitted to where the
  battlers rest, unshifted, so it never pulls back for the step. Never so far that less than
  `fit.wideKeep` (0.5) of the art's width stays on the screen: the player's art's point half its
  width in from its right edge stays on the screen's left edge, the foe's likewise on the right,
  so a giant still shows half of itself and may then reach past the line. Since 2026-11 the line
  is 0.45 and the share kept 0.6 (`wideKeep`): the point 60% of the art in from its inner edge
  stays on the screen. Not in double battles.
- Outside the 3D world (and in its doubles' own sizes, before `doublesOwnSize` returned the
  size as it is) `ownSize` measures a battler's room as it rests (`fillScale` with the draw's
  scale 1): coming out of its ball the game draws it small, its room in those pixels larger,
  and it grew to its full size, then shrank.
- In singles the camera's fit across (`across` in `fitStep`) leaves each side's outer edge
  (the player's left, the foe's right) to the step outward, which keeps most of it on the
  screen: fitting a wide one's whole width pulled the camera back only for the step to put it
  half off the screen again (a player's Wailord at zoom 0.40).
- **Small ones zoomed in** (`fitStep`, the 3D world): when the world zoom target is 1 (no
  battler needs the camera back), it comes in toward the tallest art (each `heads` entry's
  feet row less its top, at zoom 1) standing `fit.smallFill` (0.3) of the battle's height (the
  screen's top, `topLimit`, to the text box's line), up to `fit.zMax` (2.5): the largest zoom,
  in steps of 0.01, at which every art top stays on the screen and under the foe's HP box
  where it is under its columns, every art lies wholly inside the screen's sides (the step
  outward only ever moves one out, so coming in it may not lean on it: a foe went off the
  screen's right), and `fit.zoomInShow` (0.75) of each player's art shows above the text box's
  line (the zoom is about the focus row, which a filled screen's text box is not on: zoomed in,
  a back sank under it). The camera rises as it comes in (`et`, the rise past `fitLift`, by
  the lowest player's feet row past the focus row times `z - 1`), so the player's feet stay
  on the row they stand on at zoom 1 and a back grows upward: a back's feet stand below the
  focus row, and zoomed about it they sank under the text box (Pikachu half hidden at 1.85). Eased in as any zoom
  in (after `holdFrames`). `stats.zoomIn` is the target when past 1. A small foe before a
  bigger Pokemon of the player's brings it in too, gently: toward the foe's art (the `enemy`
  heads) standing `fit.smallFoe` (0.17) of that height, up to `fit.zFoeMax` (1.4), the larger
  of the two targets, within the same bounds (a Capsakid before a Dewott: 1.35 wide, 1.39
  upright). Both targets measure each Pokemon's art at its size before the floors raised it
  (`e.lift`, its raised scale over its own): measured after, a floor raised 15% had the camera
  come in 11% less, a Capsakid foe the same on a wide screen (0.458 to 0.468 of its scale at
  zoom 1) and only the Dewott behind it smaller.
- A giant pulls the camera back a little further: a world zoom target under 1 is multiplied by
  `fit.bigPull` (0.9), as far as `zMin`.
- **Double battles at the sprite mod's own sizes** (`fit.doublesOwnSize`, on): in the 3D
  world a double battle's four are drawn at their tag's own `scale`, never shrunk (`ownSize`
  returns it as it is; they may overlap a little), with no world scale (`worldSize` is not
  asked), no spread (`spreadTarget` 1), and the HP boxes where the game puts them (`headBox`
  off). The camera stands at zoom 1 with no rise, pulled back (`fitStep`, by `zStep`, as far as
  `zMin`) only as far as shows every reported battler's art whole: its top under the screen's
  top (`topLimit`), its sides inside the screen's; never in. Until 2026-11 it never moved, and
  a wide screen cut the top foe's head (Steelix, Rayquaza).
  The world's sizes squeezed a double's giants hardest (a wide Wailord to its spot's width), so
  Wailord and Steelix stood barely bigger than Seedot and Lotad; the sprite mod's sizes show the
  differences. The rules below apply with it off.
- **Double battles (world sizes, `doublesOwnSize` off):** the soft ceiling from `fit.heightKneeDouble` (2 m) toward
  `fit.heightMaxDouble` (5 m; the metre width cap `widthMax` is not used; a hard 1.5 m cap,
  tried first, drew everything from Blaziken to Wailord the same height), and each no wider
  than its spot: `fit.doubleSpots` (Gen 3's battler columns 32, 90, 152, 200, canvas px),
  spread apart about the focus column by `fit.spread` (below), split halfway between
  neighbours less `fit.spotGap` (2),
  its art's left and right of its feet each held inside (`k <= room / part`), the outer sides
  left to the screen (`e.most`). The spot is the one nearest the column it rests on, from the
  engine's report (`hd.prefit`, its record's `rest`: `e.restX`), else where it is drawn. The
  cap wins over the smallest's minimum.
- **The doubles spread** (`fit.spread`): each column moved to `fx + (x - fx) * spread`, the
  battler drawn there (`hd.spreadDx(x, spec)` added to its side shift), and the engine's
  coordinates for it with it (`Engine.shiftCoords` moves `AnimCoords.DOUBLES[id]` by
  `hd.spreadDx(home x)`, so a move lands on it). The recorded draw is put back on its unspread
  column (`cur.spread`, the spread the coordinates were moved by this frame, taken off the
  column drawn nearest), as the side shift is. Its target (`fit.spreadTarget`) is set when the
  HP boxes are placed (a battle starts, a new Pokémon comes out): as far as keeps the outer
  two's feet `fit.spreadEdge` (20) canvas px inside the screen (`viewL`/`viewR`) at zoom 1,
  between 1 and `fit.spreadMax` (1.6) (taken at the camera's target zoom, the bigger sizes it
  allowed pulled the camera back, which allowed a wider spread: an upright screen's doubles
  ended at the furthest zoom); eased `fit.spreadEase` (0.1) of the
  way a frame, so the sizes it allows grow smoothly. Held otherwise: the zoom it allows never
  feeds back into it. The scene's shadow under each side is not moved (one per side).
- **The foe's HP box over the heads** (`fit.headBox`: Fill Screen, the 3D world; both foes'
  boxes in a double battle, `fit.ui.enemy` being their group): the
  top band (`dyTop`, UI px) moves so the box's bottom (`fit.boxBottom`, UI px) sits
  `fit.headGap` (2) above the highest art top, the foe's or the player's, at the camera's
  target (`fit.target`), no lower than `headGap` above the player's HP box and no higher than
  its own height plus `headMargin` (2) under the screen's top (`fit.screenTopUI`). The camera
  makes room for it only for the heads under its columns (`heads`, each battler's art across
  where its side shift puts it, at each zoom tried): `fitStep` steps the world zoom target back
  by `zStep` until every such art top is under the box's line plus `headGap` (`uiY`), or under
  the room it needs (the box's height plus `headMargin`) before it is placed. A head beside the
  box (a foe's, on the right) needs no room, and the box may sit beside it: with every head
  counted, a double battle's two stacked boxes over its high-standing foes pulled the camera
  all the way back (zoom 0.40 for Pikachu and Zigzagoon against Seedot and Lotad). Placed in `fitStep` when a battle starts, when a new Pokémon comes out (a
  battler the engine reports, `cur.prefit`, with a Pokémon other than the one remembered for it
  in `fit.boxKey.mons`, which a faint leaves as it is; in singles also `hd.pair`: `sameMon`), or
  when the screen changes (`fit.boxKey.screen`); otherwise held,
  so a faint or the end of the battle moves nothing, and the camera never comes in under it.
  Eased `boxEase` (0.25) of the way a frame (`fit.boxDy`). The band is drawn moved down as well
  as up (`banded` allows `dyTop > 0` here).
- Indoors (the scene's `indoor`: a room or a cave) a ceiling: an art height over
  `fit.indoorKnee` (2 m) eases toward `fit.indoorCeiling` (3 m),
  `knee + (ceiling - knee) * (1 - exp(-(h - knee) / (ceiling - knee)))` (Gyarados 3.2 m stands
  2.7, Wailord 6.4 stands 3.0), so the camera need not pull back past a gym's or a cabin's walls
  for a giant. Under the knee, true to scale. `e.height` is the height it was sized by.
- Measured where it rests: per battler (`worldMons`, keyed by side and `sameMon`, cleared when a
  battle starts), again at each draw until one at the game's own scale 1 (the send-out grow,
  `rec.sx` 0.16, is measured again), then kept (a lunge or jump never changes it). Two of one
  species on one side of a double battle share one.
- The largest: `k` at most what puts its art inside the view at `zMin` about the focus, from
  where its feet stand (the screen's top, `fit.topY`; the scene's edges `fit.viewL` / `viewR`,
  set by the composite from `sceneBox`). `e.limited` marks one held to it.
- The camera alone makes room: `fitStep` makes no side shift, no slide inward and no player drop,
  and `playerDrop` / `backRaise` return 0, so each side stays on its ground and `Engine.shiftCoords`
  hands the game unshifted coordinates (move effects land on the sprites). `fitSolve` keeps only
  its on-screen test (a back may stand under the HP boxes, as the cart's do), and the zoom also
  fits each side's art between the scene's edges (`across`). Never zoomed in past 1.
- The scene's shadows (`Scene.SHADOW`, radii) are scaled about their middle to the side's body
  width at its size (`hd.worldShadow[side]`, the stage item's draw).
- Indoors the void past a room's or a cave's edges (the camera pulled back for a giant) is a
  soft dark gradient in the room's colour, not black: `roomFill` averages the scene's first
  rendered frame (a 32x18 copy, its near-black pixels left out) into `s.fill` (`Scene.FILL`
  0.42 of it at the canvas's foot, `FILL_TOP` 0.16 at its top), the sky `Render.draw` clears to
  and draws its gradient (`drawGradient`, one mesh) behind the world. A room's black filler past
  its walls (an unmodelled blocked cell whose metatile is blank: `tiles(pair).blank`, every texel
  of its lower layer near black and its upper layer black or clear, read from the tileset's
  `imageData`) is marked `cell.blank` before the stage and left out of the floor, so the fill
  shows there too. The stage still takes it as blocked ground (Mossdeep's gym is black between
  its paths: as void it left no stage at all). `stats().sceneBlank` counts them.
- Tests: `tests/hd_test.lua` "World scale" (a fake `hd.scene` with `groundScale`),
  `tests/scene_test.lua` (`groundScale` at the feet).

**The sky** (`hazeFor`): indoors the room's fill (below); outdoors a gradient, the battle's sky
colour (`s.haze`, the wallpaper's top) at the canvas's foot deepening toward `Scene.SKY_DEEP` by
`SKY_DEPTH` (0.55) at its top (the `top` of the sky table `Render.draw` clears to and draws as a
gradient behind the world). Both ends take the time of day (`Light.sky`), the top darker by
`SKY_NIGHT` (0.45) of the moonlight, and flatter by `SKY_DULL` (0.75) under rain, sand, ash or
fog. A sunset warms the horizon toward `Scene.SUNSET` by `SUNSET_GLOW` (0.65) and the sky over it
toward `Scene.DUSK` by `DUSK_GLOW` (0.35), as far as `Scene.sunset(minute)` says (full 17:00-18:00,
easing in from 15:00 and out by 20:00; a dawn `DAWN` 0.35 as much, about 5:00-7:00). Outdoors
the gradient meets the horizon where the camera sees it (`sky.horizon`: screen row
`proj[4] - proj[3] * tan(pitch)`), the horizon's colour from there down and the top's reached
`Render.SKY_SPAN` (0.55) of the screen above it; a room's fill runs the whole canvas. `Scene.timeOverride` (dev; the Workshop's `setMinute`, `SCENE_MINUTE` in
`tests/drivers/scene_battle.lua`) pins the minute of the day.

**Stand-in maps** (`Scene.STAND_IN`, `standIn`, `engineEnv(alt)`): a map whose battles are shown
on another, by name with the game's prefix left off. The Abandoned Ship's cabins, corridors and
captain's office are battled on its deck, at (11, 12) facing up, and the deck's own battles where
the player stands. `engineEnv(alt)` reads the window off that map alone (`Map.ensureMidLayout`,
no neighbours, its border past its edges); `outdoor` makes it outdoors though its map type is a
cave's (4): no fill, no ceiling, no cave fog, the outdoor sky (`Scene.HAZE.outdoor`, not the
indoor wallpaper's top colour), the time of day.

Modules in `src/scene/`, loaded by `main.lua` and handed to `init.lua`:

- `cells.lua`: once per battle (a new `Battle._st`), a 61x65 window of cells around the player
  (`Map.worldMidAt` for art; collision and behaviour through the cell's own map: the primary
  layout, a connection found as `fromDir` finds it, `Map.world`). Kinds: floor, grass, sand,
  water, blocked (`CollPermissions.isWall`), void (off every map indoors); each keeps its
  `coll` and `beh`; the kinds are their `KindOf`: grass is the game's tall or long grass
  (Kanto's tall grass also the Cycling Road's 0xD1, pokefirered's own test; in Hoenn 0xD1 is the
  bumpy slope), sand is sand or deep sand, shallow water plain. Nothing without a model stands up
  (Emerald 3DS's rule). In Kanto's games
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
  on, cards in front of a sprite and void on screen. Ours on top: a strict check
  (`Stage.tier`) ranks the targets before the score does:
  - **3, fair:** both feet on a cell they could stand on (in the map, not blocked, nothing
    standing, no slope, the battle's kind: water for a water battle, dry ground else, within
    `Stage.LEVEL` of the target's height, so no sprite floats or sinks). The camera also sees
    both sprites: rays through each sprite's middle, lower quarter and feet (`Scene.FEET`) cross
    no card, so no tree crown or wall in front reaches up to a side's feet (it would seem to stand
    on top of it: Route 111 by the Winstrates' door). A card is
    what the occlusion score stands (`cardOf`): a model, sign or border as tall as it stands, an
    upright run's card, a tree, or ground a level up at its front, lifted with its cell. Hoenn's
    trees are their crown cards as `render.lua` stands them (`c.treeCards`, from `Trees.emit`):
    leant back 50 degrees, so a small tree's crown leans over the row north of its trunk and the
    ray meets the slant. Kanto's stand at their foot row (`c.treeFoot`: built off its drawing, a
    tree stands on its trunk row's southern edge, so its crown row stands nothing). Nothing
    standing, and no rise, on the line between the two feet either.
  - **2:** seen, something between them. **1:** feet fair, the view blocked. **0:** the feet
    are not fair.

  The best score of the highest tier wins. With nothing fair within `REACH`, rings out to
  `Stage.FAR` (12) take the nearest ring with a fair target whose view, to `Stage.VIEW` tiles,
  stays inside the window of cells (`inWindow`, with a margin for Fill Screen). A best score
  under `Stage.FLOOR` keeps the wallpaper, unless the stage is fair. `stats().sceneStage` gives
  the tier, why and how far it moved. The search takes about a millisecond.
  Indoors (a room or a cave: `opts.void`), where the camera pulled back for a big Pokémon would
  show the void past the edges, the void is also counted as a camera at `Stage.WIDE.z` (0.6,
  about the focus) would show it, each cell at `WIDE.weight` (0.5), and the share of the screen's
  lower half that walls, furniture and models between the camera and the battle cover
  (`Stage.foreground`, `W.fore` -40). Both rank the targets (`best.rank`) but stay out of
  `best.score`, so a small room still clears `Stage.FLOOR`. `Stage.REACH_INDOOR` is 6, as
  outdoors: at 9 the search moved battles to the rooms' entrances (Sidney's room, the Champion's),
  their walls framing the view, and the wall penalty did not hold them back. What void is left
  shows the room's fill (below).
- **The stage census (`tests/drivers/stage_census.lua`):** builds the scene at anchors across
  each map in `CENSUS_MAPS` (`CENSUS_STEP` apart) and runs the search for every cell a battle
  could start on, by score alone and with the strict check. It logs how often each is fair,
  why not, how far it moved, spots that show the window's edge, and sample spots for
  `SCENE_SPOTS`. `CENSUS_FAR` sets the rings, `CENSUS_RELIEF=1` builds the relief first, and
  `CENSUS_DUMP=MAP:x:y` maps the cells round a spot with both choices instead (`CENSUS_RAYS=1`
  adds each sprite box's rays, blocked or clear, and what blocks them).
  - Emerald, 34 land maps with the relief (30,444 spots, trees' leant crowns): 84.8% fair by
    score alone, 99.4% with the check, 3.2 tiles moved on average.
  - Emerald's sea routes, surfing included: 95.4% to 98.6%.
  - FireRed, 22 maps: 91.0% to 99.6%.

  In `scene_battle.lua`:
  - `SCENE_STAGE_OLD=1` chooses by score alone, for before-and-after shots.
  - `SCENE_STAGE_FAR` sets the rings.
  - `SCENE_SHOT_XY=1` names the shots by spot.
  - `SCENE_BARE=1` saves the settled scene without sprites or boxes.

  `exports._workshop()` hands drivers `forBattle`, `Stage`, `FEET` and `SPRITES`.
- `trees.lua`: Emerald 3DS's trees (`voxel_tree.c`), on outdoor maps whose primary tileset is
  General (the engine's pair `general__<secondary>`): `part(sec, mid)` (0-3 a 2x2 tree's,
  SMALL, GRASS), `groundMetatile` (a crown's top over grass lays the grass), `laysGround`,
  `emit` (trunk plates and crown cards from `assets/scene/trees.png`, the crown's missing row).
  Packed by `tools/pack_trees.py` from an emerald-3ds checkout. Cells a tree or a crown covers
  stand no card. `init.lua`'s trees pass (before the stage search, after the relief is placed)
  marks each tree cell: `c.top` for the stage search (their `ReadCell`: a small trunk 1.8, a 2x2
  tree's cells and a crown-top cell 2.4, long grass none); `c.treeFoot` on a tree's foot row
  and, in Hoenn, `c.treeCards` (its crown cards, `emit`'s, for the stage's view check);
  `c.treeRock` (their `AgainstRock`: a
  cliff or shelf role two rows north, one for a 2x2 tree, or the same map's cell north a quarter
  tile higher by `Relief.centre`, two rows for a 2x2 tree; a 2x2 tree's columns alike), passed
  to `emit` as `o.rock` (small crown and tuft run 0.8, a tileset's own large crown 0.4);
  `c.treeGround` (`Relief.treeGround`, their `EmitGround`/`TreeOnRock`/`OneLevelSlope`: "rock"
  on a band's rock, "slope" on a one-level slope, where `Relief.treeStep` lays the trunk's ground
  on the relief from a relief-atlas slot of the raw art, `B.treeUV`), passed as `o.noGround`.
  Stats: `sceneTrees`. The same pass gives ReadCell's other heights - a signpost 1 tile, a counter
  or machine (COUNTER, PC, SECRET_BASE_PC, PLAYER_ROOM_PC_ON, SECRET_BASE_REGISTER_PC, TELEVISION,
  CABLE_BOX_RESULTS_1, by `MB.id`) 0.8, whatever model stands there - and marks `c.furniture`
  ("counter", "machine"). `render.lua`'s `standFurniture` stands a cell no model covers as their
  EmitTile does: a counter a 0.70 block (its drawing on top and on each side facing a cell of
  another shape, not the void), a machine their television (grey stand 0-0.3, black body 0.3-1.0
  over z 0.3-0.8, the drawing as a screen at z 0.79 - inside the body's front face at 0.80, as
  theirs), shades `SHADE_*` / `SOLID_*`, colours from `solidColours()`. Across every layout
  (`BRIDGE_FURNITURE=1 BRIDGE_SIGNS=all`) 131 such cells stand under no model: 107 counters (the
  museums, the Space Center, the Battle Frontier, the hideouts) and 24 secret-base PCs.
- Tile animation in battle: the engine's runtime runs `Battle.update` instead of `Field.update`,
  which steps `TilesetAnim`, so the world keeps the frame the field left, as theirs drops its tile
  animation in battle (`DropTileAnimation`). `SCENE_TILEANIM=1` in `scene_battle.lua` checks it.
- Move fades: theirs fits the battle backdrop's three palettes (`VoxelWorld_ScreenFade`'s
  `FadeFit`); ours draws the world in the wallpaper's recorded colour and shader. For a BG palette
  blend (SUN_CONTINUES: 6/16 to white) the world moves 0.35 of the way, as theirs would.
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
  It stands whatever else stands on its cells (Slateport's goods on the stalls); the cells of its
  own map no placement before it holds are its (CellGridOf: the first placement answers; across a
  seam the next map's), laying their own drawing for ground, the object's quarters of the upper
  layer left out (the lower layer there). The flags' cloth is `live` (every pixel of its `live_tiles`), its
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
  `ever_grande_gate`. Only specs that may stand in the window are read: one of whose template
  metatiles the maps in the window draw, or that a copy drawn in other tiles may stand for (no
  `owned` cells, the window's primary tileset, and its pair too unless `anywhere` or its core is
  in the primary's tiles alone). `find` is gen_voxel_buildings's find_placements: a spec stands
  wherever its core cells (match rows, drawn cells) repeat, model by model, each top to bottom and
  left to right, every match standing whether or not it overlaps another (a cut sailboat on the
  whole one) - the caller gives a cell two placements hold to the first (CellGridOf). Its primary
  tileset always, its pair too but for a primary-only core or `anywhere` (the battle tent in
  Fallarbor's tiles, the Frontier's houses). Each core cell, the anchor too, is the template's
  metatile or a look-alike drawing every pixel the model's texture owns in that cell exactly
  (same_building_pixels: `alikeOf`, the cell as pret composes it through `layerSource`, the
  texture `Buildings.texPixels`; of a metatile its layout draws a signpost with,
  `World.signMetatiles` - `Signs.signMetatiles`, _sign_metatiles over sign_record - the lower
  layer alone: Lavaridge's gym sign on the gym's corner, Pacifidlog's Center). Not a look-alike
  anchor: a spec with `owned` cells (it stands only where it is drawn or at its `repeat_at`
  places, the cell's place in its own map, `env.where`: Fortree's houses, Ever Grande's bushes),
  a layout with no secondary tileset, the top-left of another spec's own copy (`layout`, `rect`:
  _canonical_at, Rustboro's gym). WoobleView's own entries: `gym_sootopolis`, the shared `gym`
  parts over Sootopolis's rect, its roof in the town's own tiles; `ever_grande_gate`, the gateway
  on the path up to the League, an `Awning` on its stone legs.
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
  not the drawing. Everything the battle's window places over the 100 layouts the pak has
  placements in (`bridge_dump.lua` with `BRIDGE_RUNS=all`: `placeBuildings` over a whole layout -
  buildings, kits, props, the Cycling Road's blocks, the components' blocks) is checked against the
  pak: 4623 of its 4634 placements stand at the same place and equal its triangles - the
  layouts a script swaps in too (World's alternates, read by name) - and the 987 with a ground
  plan lay its ground metatile and number of patches (`P` and `G` lines; the pak's patch field
  six vertices a patch). The rest: sea rocks and stacks across a map's seam (they stand in the
  window, the next map in it; a lone layout has no next map). The signs (`BRIDGE_SIGNS=outdoor`,
  `signs_<LAYOUT>.txt`: each sign's cell, silhouette and head rows, head ground and ground)
  against the pak's 292 signposts: all 292 found at the same cell, 281 equal in every field; one
  of ours the pak has not (Verdanturf 0,16). The sign step reads Emerald's layers off the atlas
  blobs (`signLayers`: `World.art`, colour index 0 left out as pret leaves it; Kanto's through
  `pixelSource`). The rest need what the engine's native pack drops (gen1recomp
  `native_pack.lua`): a metatile's layer type, and a COVERED one's lower layer under its upper.
  Its blobs cannot tell a COVERED metatile whose upper hides all its lower from a NORMAL one with
  nothing on top (`Roles.blobPixels` reads it as the latter): Dewford's sand 0x124 (so 0x23A's
  silhouette and four grounds), Verdanturf's 0x2BC (its upper fills the cell: a cover to theirs),
  Pacifidlog 7,16; and the seam scores of a COVERED neighbour's lower layer: Route 117 49,5,
  the Battle Frontier's 7,29. A room spec's pieces stand in its own layout whatever its map's type (the
  Abandoned Ship's flooded rooms are MAP_TYPE_UNDERWATER, outdoors to voxel_cells); a room
  nobody modelled is an indoor one (gen_voxel_buildings's reuse_everywhere). `BRIDGE_WHY="LAYOUT,spec,x,y;..."` writes why a spec stands there or
  not (`_findWhy`: each core cell's metatile, sign, and the pixels it draws otherwise). Without the World's data, or with `exports._sceneGroundPlan(false)` (the battle
  driver's `SCENE_GROUND_OLD=1`, for before-and-after shots), the old rule: the commonest spec
  ground round it, the map's paint in every cell it paints otherwise.
- `models/components.lua` and `models/fence.lua`: the `components` specs (hedges, fences, curbs,
  railings, Sootopolis's walls, Lavaridge's spring, Slateport's crates), found at runtime as
  connected runs of their metatiles in one pair (`tilesIn`: `primary`/`secondary` names as the
  engine's pairs spell them, lower case without underscores; `also`, `skip`, `fill`), whatever
  stands on their cells (a building's cell stays the building's, the first placement keeping
  it). A spec with `block` is cut into blocks of that many cells aligned on its map
  (component_specs; `env.where` gives the map cells), each told where the run goes on (`south`,
  `north` cells, `east`, `west` rows: piece_spec); identical blocks (the same cells round them,
  the same seams) share one model. Each is built: a `Relief` (the kernel's, column by column off
  the block's own drawing, after close_gaps, trim_outline, join_corners, fill_behind, pick_side,
  seam_art - `height` rows of the next block's drawing south, the columns open at a seam - and
  flank_band) or, with `posts`, `Fence.build` (posts found by their drawn caps, the run's cells
  north and south of the block drawn too, rails between them, logs, a ground Decal; what the
  map's own buildings keep of its cells cleared, `keptPixels`: kept_by_others, the Game Corner's
  wall in Mauville's stakes). Its art reads the map's two layers through `layerSource`, its
  fence reference post too (the post pattern matched in the same colours). A run reaching past
  the battle's window ends at its edge. A post's or rail's side reading one colour throughout is
  one polygon (`PlanPrism`'s `art`, `_plain_texel`). `Buildings.kits` finds Rustboro's blocks by
  corner, top row, end and foot (`specs.kits`). Their ground is `Buildings.groundPlan`'s.
- The atlases are split by draw order, not by metatile layer: `pixelSource` takes `image` as
  the lower layer and `overImage` as the upper, except for a metatile with nothing over whose
  `image` shows more than one colour where `midImage` is clear (a NORMAL one shows only the
  backdrop there): that one is COVERED, its upper layer `midImage`.
- `relief.lua`: terrain read off the drawing (Emerald 3DS's `voxel_relief.c` and the relief
  parts of `voxel_mesh_builder.c` / `voxel_atlas.c`): its `relief.bin` format (`Relief.parse`),
  cut tiles (`cutDiagonals`, `cutClear`, `cutTexture`), the seam step between maps, and a lifted
  cell's geometry (`emitCell`: its drawing on its 5x5 lattice at (u, h, v + h), a cut tile's flat
  layer and the ground run on under it, cliff walls, a back's north face; `treeStep`).
  **Faces lean** (`Relief.lean`, `Relief.LEAN` tiles a level, 1; WoobleView's own: Emerald 3DS
  stands every face upright, a point as far south as it stands high, so a face drawn a tile tall
  is a wall a level tall and the 45-degree view is the drawing). Leaning, a point on a southward
  descent (a face, a stair, a stack of faces, a face's end) stands as far south as the top it
  falls from (up its lattice column, and on through the cells north while their edges meet and
  the ground keeps rising): the face lies as its lattice draws it, a 45-degree slope a tile a
  level leaning out over the ground in front, a stair of two rows over two tiles; a face's end
  rounds off where its side lowers it. Flats, sides and tops keep their place. It is computed
  where the mesh is laid (`B.depth` in `init.lua`, once a cell; a relief's own depths win), so
  the relief's bytes are unchanged (Emerald's still Emerald 3DS's). The user's call, both games,
  after side shots of Route 112 and Mt Ember; half a tile a level was tried too. A descent leans
  out at most `Relief.LEAN_MAX` (16 px, a tile) in all: a taller one stands steeper, its whole fall
  from top to foot leaning that tile (a five-level stair at 45 degrees buried Mt Ember's plateau,
  its battle spot and boulders under five tiles of rock).
  **No cards in Kanto:** with Kanto's trees models (`Trees.kanto`), nothing stands as a picture
  card (`cells.lua` stood a column's whole run of blocked cells when one was leafy: rock, water,
  fences and wall corners beside trees stood up with them - Vermilion's sea, Viridian's cliffs).
  A leafy blocked cell no tree model is of (a tree's tip or crown drawn over a fence or a wall's
  edge: `cell.leafy`) lies as its lower layer, the tree beside it standing its leaves. In
  `init.lua`, `placeRelief` finds each cell's map (`env.where`) and layout id (the cache's
  `map_tree/maps/G_N/header.json`; the engine pads a layout of odd size to even with a copy of
  its last row or column, `width`/`height`, and places its neighbours by that, as `env.where`
  does, but the map is `trueWidth` x `trueHeight`, its relief that size, and a padding cell is
  in no map - Route 109, Mt Chimney, Mt Pyre, Sky Pillar's foot and the rest of odd size), places
  the maps by their bases and seam steps, and sets
  `cell.g` (heights), `cell.dy` (how high what stands on it is, tiles: a point h up also stands
  h south), `cell.lifted`; `emitRelief` draws the lifted cells from one texture of the drawings
  they lay (two passes). A model's cell is the model's (laid flat at its middle) unless the model
  stands lower than a level there on a face a level tall (`B.modelTop`: `Buildings.cellTop`, its
  clipped height rounded to the pixel as buildings.bin keeps it; Lavaridge's spring rim and
  benches) or it is a `relief_bare` cell; the relief then draws it (`cell.reliefDrawn`, no ground
  of the model's). Trees, models, signs and flat cells are lifted by `dy`. For now the
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
  (the fingerprint: FNV of the cache's `census.json` and `layout_files.lua`, about 126 KB, worked
  out once a game and kept, since every model file's path asks for it through `Run.gameKey()`), and to
  `Scene.setReliefBytes`. Drivers' frames skip the engine's update hook, so `exports._reliefStep`
  runs a slice by hand (`RELIEF_BUILD=1` in `scene_battle.lua`) and `exports._sceneWarm(mapId)`
  the warm-up (`SCENE_WARM=1`; `SCENE_WARM=all` the whole-game one). `SCENE_LOOK` takes an
  optional fifth field, a yaw in degrees east of north (the battle itself always looks north).
  `SCENE_PROBE=<spec>` logs a model's art (drawn / cleared, row by row) and its parts' bounds
  (`exports._sceneModelArt`, `_sceneModelBounds`, built afresh), `SCENE_PROBE_PNG=<spec>,...`
  saves each one's art as `art_<spec>.png` (`exports._sceneModelArtRaw`); `SCENE_PIXELS=pair:mid:x:y,...`
  a metatile's two layers at a pixel through the scene's pixel source (`exports._scenePixel`). The dev `WOOBLE_RELIEF_BIN`
  path still overrides it. **Scene Cache** (`scene_cache`, `Scene.cacheModels`): `ready` reads a
  model from `mod.cache` (`models/v<MODELS_VERSION>/<game key>/<spec>.lua`, a Lua chunk of its
  triangles, core cells and texture size, plus `<spec>.rgba`, the texture's bytes) or builds it and
  keeps it. Bump `Scene.MODELS_VERSION` when the kernel or a spec changes what it builds. 104
  models: 13 MB, built in 1.9 s, read in 0.85 s; `sceneModels` counts both.
  - **What loads as a save opens:** `map.entered` runs `Scene.warm(mapId)` first (that map's
    specs, read one a frame), then `Scene.warmAll`. warmAll's items are wrapped `{ all = item }`,
    and `warmStep` passes over any the cache already holds (`Scene.modelCache.exists`, up to
    `Scene.WARM_SKIPS` a frame). A skipped spec leaves `warmed`, so the map that shows it queues
    it again. warmAll is there to fill the cache (Build as I play, `Scene.cacheJob`), not to read
    every town back: that took a phone's first 5-10 seconds.
  - **A cached model's `art`** (its drawing off the tilesets, the ground a placement lays under
    it) is read the first time something asks `md.art` (a metatable on the model, dropped once
    read). Look-alike matching uses the texture's data (`Buildings.texPixels` / `texCover`) and
    must not touch `md.art` where `md._data` is there. Reading every model's art at warm-up was
    about 70% of the cost.
  - **The relief** is decoded once: `Run.start` hands its decode to `onReady`, and
    `Scene.setReliefBytes(bytes, M)` views it.
  - **`tests/drivers/load_hitch.lua`** times this. It opens a new game with Battle Scene on
    Overworld and steps the frame hook's work by hand, frame by frame. It logs the slowest frames
    by item, plus each model's parts. `HITCH_NOJIT=1` turns LuaJIT's compiler off, as LOVE runs
    on Android. Emerald, cache built, JIT off: 126 frames and 4.1 s of work before, 38 frames and
    0.35 s after. Still left: the first `Scene.warm` loads the World (about 0.2 s), and the relief
    is read (about 0.14 s).
- **When a game's cache moves on (`relief_run.lua`, `src/prompt.lua`):** a version bump
  (`Run.VERSION`, `Run.RULES`, `Scene.MODELS_VERSION`) or new map data gives a game a new key, and
  the old cache is never read again.
  - **Record:** `Run.start` keeps each game's last relief file and models folder in
    `state/cache_<game>`. The mod's cache cannot list a folder, so this is how the old files are
    found.
  - **Pruning:** when the record changes, the old relief (`.bin`, `.ticks`) and every file its
    models folder can hold (`Scene.modelFiles`: every game's specs and bridges by name, the rooms its
    `rooms.index` names) are queued and deleted 8 a frame by the frame hook (`Run.pruneStep`;
    Ruby's old models, 677 files, in 85 frames). A record can only name `relief/v<N>/<file>` or
    `models/v<N>/<key>/` paths; anything else is ignored. Empty folders stay (the cache cannot
    delete one).
  - **The question:** the same change writes `state/rebuild_<game>`. A player asked before, with
    Battle Scene on Overworld, is asked once "Rebuild <Game>'s 3D world?" (Build now / Later); any
    answer deletes the flag.
  - **The guard:** `tests/scene_test.lua` hashes every file the caches are built from (`src/scene`,
    its `models` and `games`, `assets/scene` data; comments, blank lines and the render-only files
    left out) and checks it, with the versions, against `tests/cache_guard.txt`. Change one and it
    fails until you bump a version (the change alters what is built) or record it as it is:
    `CACHE_GUARD_WRITE=1 luajit tests/scene_test.lua`. `exports._reliefPrune(n)` steps the pruning
    in drivers (`first_run.lua` runs it after the prompt closes).
- `roles.lua`: `voxel_cells.py` whole (every cell's role: water, ledge, stair, floor, signpost,
  wall, tree, fence, cliff, shelf), over an adapter of a layout; matches the Python cell for cell
  on 21 layouts. Its drawings are exact layers from the atlas blobs (`Roles.blobPixels`: colour
  index 0 left out, pret's colour rounding); `blocked` is the cartridge's collision bits.
- `world.lua` (engine side, battle-free): Emerald's layouts by the cartridge's layout id (from
  `map_tree/maps/G_N/header.json`, `events.json`, `grid.bin`), their maps' warps and sign events
  joined as `voxel_cells.MapEvents` joins them, `roles.lua` adapters over them, the game's sign
  posts and each layout's roles, cached once a game. `signs.lua` asks it in Emerald
  (`opt.signpostAt`). The raw tilesets are in the cache too (`map_tree/tilesets/ts_<ptr>/`:
  `metatiles.bin`, `tiles.4bpp`, `palettes.bin`, `attributes.bin`). The layouts a script swaps
  in (`setmaplayoutindex`; no map is drawn with them): the engine bakes them as
  `native/layouts/alt_<id>.mid` and writes their cells over the live map (`ops_a.lua`
  `set_map_layout`), keeping no layout id. World reads them as the relief does
  (`relief_input`'s `Input.ALTERNATES`, `Input.baked`, `Input.alternateBlocks`; the rooms' in
  `World.ROOM_ALTERNATES`), with their base's tilesets and events, no connections, and the
  engine's collision codes (`codes`). `World.settle(mapId, liveMid)`, once a scene (the window's
  environment, init.lua), picks the layout each map is drawn with, as voxel_world.c's
  FillInstance and NeighbourLayoutId do: the current map, the alternate (or `MAP_SWAPS`'
  other map's layout: Shoal Cave at high tide) every cell of which that differs from the base
  the live map draws so (`World.swappedIn`); a neighbour, `NEIGHBOUR_SWAPS` (sLayoutSwaps: Route
  111 without the Mirage Tower when FLAG_MIRAGE_TOWER_VISIBLE is clear, Route 130's Mirage
  Island when the game's IsMirageIslandPresent says so, Route 131's Sky Pillar always).
  `World.layout(mapId)` then answers with it, and so do the relief's lookup (init.lua
  `layoutIdOf`) and the window's cells of a neighbour (`env.mid`, `env.cell`: its metatile,
  collision code and behaviour). `hd.stats.sceneSwaps` lists them.
- `render.lua`: static meshes per atlas and layer (ground quads, then cards, then trees, then
  buildings); a shader that
  outputs screen pixel x depth through LOVE's own projection with the view depth as w (so the
  ground is perspective-correct and LOVE's canvas flip still applies), depth-tested, hazed
  with distance, over the sky (the wallpaper's top colour outdoors, black indoors: Emerald 3DS
  clears to the battle's backdrop colour). WoobleView's own, not Emerald 3DS's: land past every
  map fades into the sky from the maps' edge to `Render.BORDER_FADE[2]` (3) tiles past it (the
  distance from each border cell's centre to the nearest map cell's, read between the centres at
  each vertex with its height taken off its row; `VertexFade`), so a mountain's rim carried on as
  the border (Mt Chimney's) does not stand as ridges out to the horizon. Water belts and a belt
  cell with a tree stay whole.
- `light.lua`: Emerald 3DS's light by the weather (ctr_voxel.c's VoxelLight, BaseLightFor,
  LightMix, FogLight, SetGrade; voxel_world.c's weather class, amount, fog density and lightning),
  read each frame from the game's weather (`R.state` of the engine's field_weather_rse,
  pokeemerald's gWeatherPtr). It gives the grade's sun and shade tints (the shader: a vertex's
  shade picks t = clamp((shade - 0.62) / 0.38), its colour shade x lerp(shade tint, sun tint, t)),
  the distance haze (from 1.05 eye distances off - the pose's `dist`, along the line of sight:
  their `distance / cos(pitch)` - to 0.6 further, 0.14 at most, to a pale sky colour; sun 0.12,
  rain 0.30 and 0.18 of its drops, ash and sandstorm mixed in by their blend - Mt Chimney's ash
  0.5 warm grey from 0.75 - fog a pale veil, a blue-black underground, snow 0.36, shade 0.25), and
  the dapples', rays', bloom's and motes' strengths. Their `indoor` (MAP_TYPE_INDOOR, SECRET_BASE):
  the grade is the identity and nothing else. The texture grade (voxel_grade.c): every texel's
  5-bit colour (the engine's c5 x 255 / 31) pushed 1.3x from its luma, in the shader; the tree art
  graded as it loads instead, its crowns then brightened 1.12x (`gradeTrees`, BrightenCrowns), its
  meshes left ungraded by the shader. The sun dapples (MakeDapple, DappleFrame, DappleUniforms): a
  128x128 pattern of three octaves of tileable value noise (their 32-bit hash, exactly), laid from
  above along the sun (a point slid along it by its height), 24 tiles a period, drifting 0.25 tiles
  a second, scaling the lit texel from `dappleLow` to `dappleHigh`.
  - **Time of day** (option `scene_daytime`, `Scene.timeOfDay` -> the minute of the day, or nil):
    their day-night cycle (3ds_daynight.c `CtrDayNight_At` / `_Moonlight`, ctr_voxel.c
    `LightFor`). `Light.cycle(minute)`: keys at 0/120 night (0.66, 0.74, 0.92), 240/480 morning
    (0.96, 0.94, 0.88, daylight 0.75), 600/900 day (white), 1020/1080 evening (1.00, 0.80, 0.65,
    daylight 0.35, glow 0.25), 1200/1440 night (daylight 0, glow 1), smoothstepped between.
    `Light.dayNight(light, cycle)`: sun and shade x the tint x (1 - moon), the haze tinted and
    turned towards the moon's colour (70, 92, 136) by moon = 0.06 x glow^2, rays, motes and
    the dapples' spread x daylight; `light.moon` (that colour x moon) is added to every lit texel
    in the shader (`uMoon`: their multiply-add). `Light.sky` tints the backdrop's colour the
    haze's way. Outdoors only: never `s.walled` or `s.cave` (WoobleDex never tints caves
    either). Not ported: the windows' and lamps' glow at night, the sun's path through the day.
    The battlers, trainers and UI are not tinted. `hd.stats.sceneTime` shows the time used.
  - **The clock** (`src/clock.lua`, `Clock.minute`, read at most once a second): WoobleDex's
    (`national_dex_gen3`) when it is installed: its Clock Source (`exports.clockSource()`, else
    its stored `clock_source`), and nil while its `day_night` is off, so a battle matches the
    overworld its Day & Night look tints. Else the game's: `Rtc.calcLocalTime` where `Rtc.enabled`
    (Ruby, Sapphire, Emerald), the device's (`Rtc.hostInfo`) on FireRed and LeafGreen. Both
    honour `POKEPORT_RTC` (the drivers fix the hour with it).
  `hd.stats.sceneHaze` (the driver logs it). Without light.lua, the old haze: 14 to 48 tiles, 0.9
  at most, the sky's colour, and no grade.
- `lighting.lua`: Emerald 3DS's sun (voxel_lighting.c), baked into each vertex's shade as the
  meshes are built: the face term (n . sun over up . sun, the sun at (-0.85, 1, -0.55): ground 1,
  a west wall 0.955, a north one 0.865, south and east the ambient 0.70), the cast shadow (a ray a
  quarter tile of rise a step towards the sun, 32 steps, every point up to the casters' ceiling:
  their reference march), and contact darkening (0.035 for each of four points a quarter tile out
  that something stands in). The casters (their `Cell`/`CellOccludes`/`ObjectAt`) come from
  `init.lua`'s `sceneLighting` over the battle's window, in their frame (ours lifted by
  `grid.frameH`, the player's ground and the battle map's base, in height and rows): a tree's
  crown an ellipsoid (a small tree's half as wide), a model's 16x16 footprint to its top
  (`Buildings.cellTop`, `Buildings.footprints`; a deck over a wood casts instead), a sign's
  drawing on its board (voxel_sign.c ShadowOf), a drawn map's relief as a height field (their
  `BuildSurface`/`SurfaceAt`/`SurfaceTop`, built from the relief's lattices); past every map,
  nothing, at the base of the map north whose drawing reaches it. How each face is lit is their
  `LightFace` (`face4`): level ground a cell across refined into four quads where a shadow's edge
  crosses it (not past every map), a crown's card as the rounded crown, a relief lattice's quads
  from each point's own face term (`ReliefFace`, the slope a tile across; the lattice's shadows
  read ahead, `Lattice`, and spans merged only where the light runs linearly, `SpanLinear`), the
  drawing's own light kept on the relief (`artShaded`), an object lit as a whole (a sign: one
  sample; the ground run on under a terrace: 1), a model's triangle by its outside's facing
  alone (`ModelShade`: its drawn shade says which side). Terrain walls keep their baked shades,
  the light multiplying them. The quad's cut follows the diagonal lit most alike (`RawQuad`).
  Indoors (their `indoor`), no sun. Not ported: their cell skips and block bounds (the same
  answers), the ease stretch.
- `sunfx.lua`: the light in the air, drawn into the world's canvas after it (under the battle's
  Pokemon, as their world is the battle's background): sun rays (MakeRays/DrawRays: an 8x5 mesh
  from the top left, the dapple pattern stretched almost to lines, additive warm white, strength x
  (1 - pattern)), sunlit dust (DrawMotes: 32 soft diamonds in a wrapped box round the camera's
  target, drifting with the sun, depth tested), and bloom (VoxelBloomPrepare/Compose: the picture
  at a quarter of their 400-wide screen keeping what is over 0.85, x4, stretched back and added at
  the light's strength, and 0.7 x the landing's impact as the glide lands). The canvas is halved
  to their 400 across first, so a large window averages as their screen does. `bloomPrepare`
  takes the glow from the world as it stands, `bloomCompose` adds it after the blurs (their
  order); `air` is the motes and rays.
- `weather.lua`: the weather in the scene (MakeFog/DrawBanks, MakeWeather/DrawWeather and
  voxel_weather.v.pica as a GLSL shader). Rain, sand and ash: 768 streaks or 512 flakes built once,
  each at a fixed place in a box round the camera (24 x 8.5 x 28 tiles for rain), three groups of
  their own speed, wind and size drawn by setting the box's offset (wrapped in the shader) and
  `setDrawRange` to the share the game's weather has come in (`Light.amount`); thinning at the
  box's sides, at the lens and into the haze; white in a bolt. Fog: two 64-tile sheets at 0.30
  and 1.10 tiles over the target's ground, a 128-px coverage texture of four octaves of the
  dapples' noise, moved in whole periods plus the drift so the mist stays on the ground; the
  sandstorm's dust on the same sheets (`SAND_BANKS`). Depth tested, never written, alpha
  blended. The game's own weather is read off `R.state` (`Light.amount`, `fogDensity`,
  `lightning`) in `hazeFor`; none indoors, the fog's banks outdoors only (dark when
  `mapType == 4`, underground). While the world blows sand (`Scene.drawsSand(st)`, their
  CtrVoxel_DrawsSand), `src/gen3.lua` wraps the engine's `AnimTasks.REGISTRY.LoadSandstormBackground`
  and takes the BG1 picture off after its first call (their battle_anim_rock.c patch: no
  picture, the blend and the flying sprites kept). The task runs in the update, outside the draw
  pass, so it reads the scene's flag, not `hd.capturing`.
- `screenfx.lua`: the shot (3ds_video.c's VoxelDiorama, BattleIntroBlur, BattleIntroAtmosphere,
  BattleIntroFlash, BattleIntroBars; ctr_voxel.c's BattleCamera intro values). Their 400 x 240
  screen is the world's canvas, its height their 240 rows. The diorama blur: a copy of the canvas
  at their size (halved, then scaled) drawn back over the top 100 and bottom 56 rows half a pixel
  off each way, fading to nothing towards the middle (strength `Scene.blur`, the Scene Blur
  option). The intro (`ScreenFx.intro(progress, frames, TRAVEL)`): flight `sin(pi p)`, speed
  `16 p^2 (1-p)^2`, impact `exp(-5q)(1-q)`, bars `smooth(frames/18)(1 - smooth((q-0.35)/0.65))`;
  a zoom blur about the target's canvas point, twelve speed lines (their hash), the indigo
  vignette down to the text box's line (to the canvas's foot when the UI's box is narrower than
  the view), the landing's flash. The bars are drawn over the whole composite through
  `hd.sceneOverlay` (`Scene.overlay`), called after every item when a world was drawn. Their
  curtain (BattleWorldCurtain) is the `"win0"` item's. Not exact: their atmosphere is laid over
  the battlers' shadows, ours under them (the shadows are stage items).
- `Render.after` runs all of it in their order: fog banks, sand dust, motes and rays, weather
  particles, then bloom prepare, diorama, zoom blur, bloom compose, lines and vignette, flash.

### The 3D cache and the first-run prompt (`src/prompt.lua`)

WoobleView's own UI (not a port). The engine has no prompt, progress, action-row or
`options:set` API for mods, so:

- **Panel and notices:** drawn at window resolution in a `render.hud` wrapper (a dark rounded
  panel, the "WoobleView" chip in its corner, LÖVE's default font, pill buttons; a notice is a pill
  at the foot of the screen). While a panel is up, an empty layer `woobleview_prompt` on
  `src.ui.game3.stack` (`isMenu`, `hideBelow = false`) pauses the field and takes the buttons
  (`handleInput`: left/right, A/START, B). An `input.pointer` wrapper turns a release on a button
  into a press and swallows every pointer event meanwhile.
- **Options:** set through `ManagerState.setOption` with the Gen 3 manager's proxy
  (`P.setOption`). That saves them, emits `mod.options_changed`, and the pane shows them.
- **First run (each game in `P.GAMES_3D`, once):** `core.update` wrapper waits for
  45 quiet frames of the field (`Field.running`, no battle, `Runtime.uiBusy()` false, engine modules
  through `require`: a mod's `package.loaded` is not the engine's). `mod.cache` is the install's,
  shared by every game, so each game has its own flag file, `P.flagFor(game)`: Emerald's keeps the
  first name, `state/first_run_asked` (players asked before stay asked), the others add `_<game>`.
  If this game's flag is missing:
  - Battle Scene not on Overworld: "Battle in the world around you?" (yes: `battle_scene` =
    overworld, then "Build the 3D world now?").
  - Already on Overworld (chosen in another game) and this game's relief still building
    (`Scene.reliefRun.state()` "running"; started here if "idle", as the frame hook would):
    "Build <Game>'s 3D world now?" alone.
  - Already on Overworld and built (served from the cache): nothing asked, the flag written.
  Any answer writes the flag. `tests/scene_test.lua` checks each case with fake engine modules.
- **No garbage while idle:** the hook runs every frame for the whole session, so it allocates
  nothing (0.01 KB a tick, measured with the GC stopped). The engine modules are required once
  they load and kept, since the sandbox's `require` allocates on every call. The flag is kept in
  memory once seen. The checks after the quiet count run once each time the field settles
  (`quiet == QUIET_FRAMES`), not on every quiet frame. The panel reuses its meshes (`setVertex`),
  its wrapped body lines and its button records.
- **Build 3D Cache / Clear 3D Cache:** `choice` rows (`idle` / `go`, `visible_if` Overworld) under
  Battle Scene. `main.lua`'s `mod.options_changed` handler runs a row set to `go` and sets it back
  (Build's when the panel closes). A `go` left from the launcher runs once the field is quiet.
- **Gen 3 only rows:** `main.lua` defines `options.lua`'s rows with `mod.options:define`, and in
  Gen 1/2 (`Engine.generation() < 3`) it leaves out Battle Scene's (`battle_scene`, `scene_build`,
  `scene_clear`, `scene_blur`, `scene_cache`). The engine sets the game before it loads mods, and
  loads them again for another game. Their stored values stay; reads fall back to the defaults.
- **OPTION shortcut (`src/shortcut.lua`):** wraps `ui.options.rows` to add a `WOOBLEVIEW` row to the
  game's own OPTION screen (all generations). A opens the Mod Manager (Gen 1/2 `Screens.push(game,
  "ManagerState")`, Gen 3 `src.ui.game3.mod_manager`.show) and jumps it to this mod's settings page with
  an empty back stack, so B closes the Manager and returns to OPTION. Same as WoobleSpawns' row.
- **Build as I play:** the progress panel's one button, `Build as I play (B)`, is taken by B or a
  click, never by A, so mashing through text can't close it.
  - It closes the panel and keeps the job (`bgJob`). The build carries on as it would have in the
    background: the relief's frame hook, a slice a frame, and the models' warm-up, one a frame.
  - The prompt's tick checks `bgJob.done()` and shows "The 3D world is ready" (or a failure notice)
    when it finishes.
  - `FIRST_RUN_ANSWERS=a,a,b FIRST_RUN_BG=1` in `first_run.lua` runs this, stepping the build by
    hand, since a driver's frames skip the hook.
- **`Scene.cacheJob()`:** `warmAll` queued (Scene Cache forced on) and the relief run started.
  `job.step(budget)` works ~28 ms a frame on both. `job.progress()` = 0.95 × relief + 0.05 ×
  models, and `job.stage()` names the phase.
- **`Run.progress()` (relief_run.lua):** the work done over the whole build's work.
  - The build makes the same ticks for the same map data on every device: 117030 for Emerald, as
    two builds counted. So progress is counted in ticks, not guessed from time.
  - A tick's cost differs by phase. In ms a tick on a desktop (`Run.TICK_COST`): groups 0.32,
    world 1.96, export 0.37, terraces 1.61, the finish 1.05. Each phase's ticks are weighted by it.
  - `phase()` adds the finished phase's work and names the next. `progress()` adds the ticks of
    the phase under way, divided by `Run.TICKS[game]` (each phase's count) weighted the same way.
  - A finished build keeps its own counts beside the relief (`relief/v1/<key>.ticks`, kept by
    Clear), which other map data under the same game id then uses.
  - Measured: the bar stays within 8% of the clock over a whole build.
  - Without a known whole, the old phase-share estimate remains (groups 2%, world 21%, export 35%,
    terraces 42%, creeping on within a phase).
  - `Run.phase()` names the phase under way, for the panel's stage label.
- **Time left:** the pace since the panel opened, `(1 − p) × spent ÷ (p − p_open)`, shown after
  5 s and 2% done. It counts down between frames and eases toward the estimate by the real clock;
  a longer estimate eases up slowly.
  - The old version, the bar's pace over the last 20 s on phase shares measured on a desktop,
    told an Android player "67 minutes" at 26%, then about 7 a minute later. A phase that took a
    larger share of the time there stalled the bar.
  - Measured on a desktop: within 12% from 20% to 60% done. About 36% high at 10%, and a few
    seconds low near the end (the display rounds those).
- **`Scene.cacheClear()`:** deletes every file the cache holds:
  - each spec's `.lua`/`.rgba`;
  - each bridge's;
  - the rooms named in `rooms.index`, and the index;
  - the relief (`Run.clear`).

  It then drops them from memory (`spec._model`, the warm queue, the rooms' and bridges' jobs, the
  relief bytes). The flag file is kept.
- **Background build gate:** the relief's background build now starts only while the scene is
  wanted (`deps.wanted`: Battle Scene on Overworld).
- **Cache paths (`src/scene/cache.lua`):** every read of the engine's cache of the player's
  cartridge goes through `Cache.read(rel)` / `Cache.native()`.
  - The root comes from the engine's own constants (`src.core.game3.cache_paths`: `CACHE_ROOT`,
    `NATIVE_ROOT`, which follow the cache if it moves). Shipped files never spell it out.
  - `relief_input`'s `io.read`, `relief_run`'s `readCache` and `world.lua`'s `cread` take paths
    under that root (`map_tree/maps/<slot>/header.json`, `native/layout_files.lua`).
  - Why: `modkit pack` runs the engine's no-ROM-content gate, MK301, which refuses any shipped Lua
    or JSON naming the cache's path, comments included.
  - `assets_transforms` can't stand in: its sandbox reads only images under the generated assets
    and writes only PNGs, and nothing it makes reaches a mod's Lua.
  - The scene still reads the player's own cache at runtime, through `engine_internals`, as the
    engine's modules do, and ships none of it. The constants pass the tool. The rule's own
    wording ("nothing may point into the generated trees") is broader, which is worth knowing if
    the engine ever adds a map-data API to use instead.
  - Tests may name the paths (they don't ship).
- **Tileset families (`src/scene/family.lua`):** Emerald draws with the RSE family and FireRed /
  LeafGreen with FRLG. The two cut their tilesets differently, and everything that reads a
  metatile goes through the game's family:

  |                   | RSE (Emerald)  | FRLG (FireRed) |
  |-------------------|----------------|----------------|
  | primary metatiles | 512            | 640            |
  | primary tiles     | 512            | 640            |
  | primary palettes  | 6              | 7              |
  | attribute         | u16            | u32            |
  | behaviour         | bits 0-7       | bits 0-8       |
  | layer type        | bits 12-15     | bits 29-30     |

  - `Family.active()` reads the engine's game id.
  - Tilesets carry their family (`ts.family`), so `Art.pair` cuts and reads attributes by it (`P.behaviour`, `P.layer`, `P.NUM_PRIMARY`).
  - The plain modules that read tileset names are told the family on each scene build (`useFamily`): Roles, Signs, Trees, Buildings and Components.
  - Behaviour enums come from `Constants.of(game)`, compared by name. FireRed's own names (`MB_FAST_WATER`, `MB_CYCLING_ROAD_WATER`, `MB_WARP_DOOR`, `MB_RUNNING_DISALLOWED`) sit in the same lists; a name the game lacks is skipped.
  - **FireRed's names are its own.** The engine names FireRed's primary "general", like Hoenn's. `pairNames` puts `fr:` before each FireRed tileset name (`fr:general`), so no table read off Hoenn's tilesets ever matches FireRed's tiles: trees, fences, curbs, props, mountain rock, the relief's tables.
  - It also resolves the pairs the engine names otherwise (`pallet_outdoor` → General + Pallet Town, the engine's `versions_frlg.TILESET_PAIRS`).
  - **Maps:** World and the relief's input read the game's own maps by its prefixes (Emerald `EM_`, Ruby `RU_`, Sapphire `SA_`: `Family.RUBY` / `Family.SAPPHIRE` are RSE with their own prefixes; FireRed `FR_` and `SEVII_`).
  - FireRed's cache has no `native/layout_files.lua`. A layout id is named after its maps' baked layouts, found by the engine's own name match (`Family.normal`: upper case, letters and digits). Maps sharing a layout keep the first name in sorted order, as World names them.
  - In the scratch engine this gives 303 layouts from 419 of FireRed's 425 maps.
  - **Emerald's data stays Hoenn's** (Ruby and Sapphire take it where they draw Emerald's maps; see below):
    - the script-swapped alternates (Emerald's own: Ruby and Sapphire swap none in);
    - Emerald 3DS's hand marks and sea ramps (`relief_run` applies them for `Run.HOENN`);
    - the terrace groups (`T.chosenLayouts`). Emerald's `LAYOUT_SAFARI_ZONE_NORTH` is also a FireRed name;
    - the rooms (`ROOMS.ids` are Emerald's layout numbers; `roomJob` and `placeRooms` skip a game drawn with other tilesets);
    - `World.roles`' alias reference (Route 116) and the Shoal Cave tide swaps (`s.hoenn`).
  - **World root:** the relief's world starts at the player's home town (Littleroot, or Pallet in FireRed).
  - **Weather:** FireRed's weather is the engine's own FRLG field weather, not Emerald's state machine. `hazeFor` builds the state `light.lua` reads from it: rain as many drops as are falling (of 24), the others full once up.
  - **Relief key:** a game other than Emerald carries its relief rules' version (`Run.RULES`: `firered-r2-<fp>.bin`), so a relief built by older FireRed rules is rebuilt. Emerald's key is unchanged.
  - **Check:** Emerald's relief rebuilt after this was byte-identical (`emerald-0c3fad9f.bin`, same ticks).
- **Ruby and Sapphire (`src/scene/prints.lua`, `src/scene/games/emerald_prints.lua`):** Emerald's 3D
  - Emerald 3DS's specs, rooms and hand marks - where Ruby and Sapphire draw Emerald's maps. They do
  not all: of Ruby's 331 layouts 187 are Emerald's byte for byte, 88 differ (most routes in a few
  cells - Route 110 in 48 of 4000, the Safari Zone's new corners in 1200; every gym redrawn) and 56
  are Ruby's own. The tilesets differ little (the General's metatiles in 1 of 512, its art in 66
  tiles; the gyms' secondaries much more). Sapphire's maps are Ruby's (their reliefs are byte-identical).
  - **Prints, not maps:** `emerald_prints.lua` keeps, for every Emerald layout under each of its
    names, its size and one FNV-1a print per 8x8 block of metatile ids; for every reference
    rectangle a model reads (`Buildings.reference`: specs, solids, Fortree, `layoutArt`), its print;
    and for each room layout pret names apart (`LAYOUT_POKEMON_CENTER_1F`), the names of the maps
    Emerald draws with it (`aliases`). `Prints.checker(T)` answers `rect(layout, rect, ids)` and
    `layout(name, w, h, at)` -> `{ same, size, ok(x, y), share }`; `Scene.prints()` is Ruby's and
    Sapphire's checker over the table, any other game's passes everything.
  - **Where it applies:** a reference rectangle holds where its metatiles print as Emerald's
    (`ctx.trust`; else the spec has no reference: Slateport's Battle Tent and boats, the Space
    Center, the Safari wings drop out). Emerald's rooms are found by name or alias (`roomLayout`:
    the alias drawn as Emerald's, else the first of Emerald's size, its record under the name it
    was found by) where the layout is Emerald's size; a room's pieces over blocks Ruby draws
    otherwise are dropped (`trustedPieces`). Hand marks (`Post.trustedFixes`, run by
    `WorldMaps.solve`'s `trustFixes` once the maps are read): a layout of another size loses them;
    one the same size with more than `Post.MOSTLY` (half) of its blocks Emerald's keeps them all
    (Ruby's changes are details; dropping them block by block left the solver to read those blocks
    alone, worse: Route 120 896 cells off Emerald's, 2 with them kept); one mostly redrawn (the
    Safari Zone's corners) loses each mark in a redrawn block. 726 of 26295 dropped in Ruby. The
    terrace groups, sea ramps and Emerald's rock tables run as for Emerald (`Run.HOENN`); relief
    rules `ruby-r2` / `sapphire-r2`.
  - **Their own (`own`, never checked against the prints):** main.lua builds Ruby's and Sapphire's
    spec list (Emerald's and `models/specs_rs.lua`'s, with Emerald's named fields: `kits`,
    `decks`, `helpers`) and room list (Emerald's, each own room in the place of Emerald's of its
    layout or of the name it `replaces`, and `models/interior_specs_rs.lua`'s). `interior_specs.lua`
    exports its readers (`ROOMS.helpers`: piece, ownShell, runRects, gymBlock, rectPieces, cutRuns,
    tierTops, cellsRects, runsOf, rowsOf, cellsOf, trickHouseShell, ...).
    - Rooms, each proved by `room_check` over Ruby's drawing: the eight gyms (Ruby's own but
      Petalburg's, which Emerald's pieces hold in its unchanged blocks: 0 wrong but Rustboro's 34,
      the same 34 as Emerald's own, and Dewford's 4); the Trick House's puzzles (Emerald 3DS's
      puzzle maps are Emerald's blocked cells, rows 2-21 - checked - so Ruby's are Ruby's, at
      Emerald's heights); Team Magma's hideout (the Aqua Hideout's tiles and recipe); the Center's
      2F; and Emerald's rooms adopted whole (`adopt`, less the pieces Ruby doesn't draw: `drop`)
      where they read Ruby's drawing as Emerald's (the Mart, the League's lobby and corridors - Ruby's
      Corridor1 / 4 are Emerald's short hall / Hall4 - the Battle Tower's rooms, the lab, Devon, ...).
      Rooms no battle can take place in (contest halls and lobbies, the Battle Tower's lobby, a
      house) are not modelled.
    - Buildings, proved by `model_check`: the contest hall of Slateport, Verdanturf and Fallarbor
      (`flat_block` with its roof's back at z 30: `flat_block` takes `o.back`, 16 as before), the
      Space Center (Ruby's office block), and Emerald's wide Mossdeep house and Safari south wing
      adopted over Ruby's drawing.
  - **Regenerate** after any change to the specs' rectangles or the room specs' layouts: run
    `tests/drivers/emerald_prints.lua` in Emerald (it builds every spec afresh with the checker
    recording, then writes the table; `OUT=<file>` writes elsewhere).
  - **Check (scratch engine, Ruby; Sapphire's maps are Ruby's):** the 19 identical layouts with
    relief match Emerald's cell for cell but 4 (1-7 cells each, by their seams with redrawn
    neighbours); Mt Chimney (joined to no map) sits 80 higher than Emerald's, the same shape. The
    building placements are Emerald's but for what Ruby draws otherwise or Emerald alone has (the
    Battle Frontier, Mirage Tower, Trainer Hill, Route 109's extra chairs); left flat: the Battle
    Tower's grounds (no battle there) and Slateport's harbour boats. Emerald's relief, rooms and
    models unchanged. Build: about Emerald's ticks (`Run.TICKS.ruby`).
  - **Known:** the Mart's right-hand shelf stands again under the pot Ruby (and Emerald) draw on it
    (Emerald 3DS's own reading: its Mart has the same 629 pixels wrong).
- **FireRed's relief (`src/scene/games/firered.lua`):** Emerald 3DS's counted levels, run on our own
  reading of FireRed's General rock. No FireRed 3DS code is used (its FireRed files carry no
  licence); its screenshots were a visual reference only.
  - The table names ids and roles only: the rock's colours (palette 1, slots 9-14), the reference pieces (`lists`: south face, west and east bands), the rock a drawn map must hold (`rockTiles`), the mountain range, and the terraces' pieces (`terraces`: bands, heads, face ends, carved steps, faces, tree cards, the outline grey, the plain top). Its header says how each was read.
  - `Solve.useGame(game)` points the solver's tables at the game's own (`Solve.GAMES`, filled by main.lua from `src/scene/games/`). Emerald keeps its original tables, so its build is unchanged.
  - `Roles.useGame` does the same for the roles; the terraces read `Solve.game.terraces` (`T.G`), and `T.NP` is the family's primary size.
  - `groups = "drawn"`: every FireRed map read as drawn is rebuilt terrace by terrace (Emerald's are a chosen list).
  - **FireRed 3DS's relief (r15, `Run.borrow`):** `assets/scene/firered_relief.bin` is the `VXL4` section of FireRed 3DS's pak (`luajit tools/fr3ds_relief.lua <firered3ds.pak>`, modkitignored). After our own solve, terraces and caves, every layout it gives (any it encodes: cells or a base) takes its cells, cut tiles (their variants appended after ours, the cuts' indices shifted), edges and flags; ours there are dropped with our cave depths. Layouts it leaves out keep ours (Mt Ember's outside: theirs is flat). The building post-pass then runs again on the layouts taken, and the last passes (`cutFeet`, seam eases) run over the whole. `deps.borrowed(game)` (main.lua) serves the bytes for FireRed and LeafGreen. The workshop's ground marks ride over it as over ours. Review: `REVIEW_KINDS=relief` sets ours beside theirs layout by layout.
    - **Post-pass (FireRed only, `relief_run.lua`):** a cell a building model stands on is flattened to the level of the first cell south of it that no model holds, and its cuts are removed. A building drawn into a cliff (Lavender's tower, its door a cave door) then stands on its door's ground, not on a plateau.
- **FireRed 3DS's places (`specs_firered.lua`, the specs after `power_plant`):** the places FireRed 3DS's pak models a building and we modelled nothing (the review's pak list: 30, now 3 - Seven Island's Center, ours a row higher; Two Island's stall, ours in pieces; a slab Route 10 floats at 86 px). Each is our own spec, proved by `model_check` as every other, shaped after their mesh (the user's call; read with a VXB7 face dump: walls, roof planes, pitches): `shed` (one slope rising to the back: the underground path's huts, the Rocket warehouse), `box_house` (flat over its whole depth: the Safari rest houses), `hip_house` (28 degrees: Route 2's / 12's houses, Saffron's narrow one), a `K.Cylinder` basin and a jet (Celadon's fountain; `projMin`/`proj = false` - a broad basin's projected flanks stretch), `slabs` (the Memorial Pillar), `flat_top` (Tanoby's ruins, Viridian Forest's north gatehouse), `gate_roof` (a roof rising to the map's foot: the Safari Zone's and the forest's south gatehouse backs). Lavender's Center is the Center spec over Lavender's own drawing (`pokemon_center_lavender`: its colours differ, so no look-alike matched).
- **FireRed's buildings (`src/scene/models/specs_firered.lua`):** our own reading of each building,
  by Emerald 3DS's method, on our kernel. main.lua loads the file for FireRed and LeafGreen
  (`sceneDeps.SpecsByGame`), and `useFamily` picks the game's specs (Emerald keeps `specs.lua`).
  - **The proof (`tests/model_check.lua`, `tests/drivers/model_check.lua`):** Emerald 3DS's `ortho_check` and `density_check`, in Lua. A spec passes only when its model, rendered at 45 degrees, equals its drawing pixel for pixel over its `exact` rectangles, and no face stretches a texel. Run it with `MODEL_CHECK=<names or prefix*>`; `MODEL_VERBOSE` lists the wrong pixels and stretched faces, and each spec gets a `<name>_ortho.ppm` sheet (drawing | render | differences). All 96 FireRed specs pass, against FireRed's drawings and LeafGreen's.
  - **Kernel tags:** the kernel marks what the proof doesn't judge, as Emerald 3DS's does: `~clamp` (a constant strip row, a clamped projection), `~proj` (drawn diagonal walls, vault tops), `~depth` / `~behind` (depth the drawing never shows). Geometry is unchanged, and tags aren't stored in the model cache.
  - **What stands in front of a drawn band:** a board or canopy drawn over a wall or eave stands in front of it, and the wall or eave behind is cut from the same drawing, so from the battle's lower camera its copy of the board showed past it (the Center's Poke Ball twice). The board's underside slopes back to the wall at its last drawn row (edge-on at 45 degrees, a clamped projection), and an eave strip takes `patch = { a, b, lo, hi }` (`K.Strip`: columns [a, b) sampled from a plain run [lo, hi)). The Center's side walls take the plain panel right of its door (the left one carries the P.C letters, which tiled down the sides). A side or back wall's tile is a plain run of the facade (Cerulean's houses: their siding, not the windows, which stood two rows high), and boards and canopies have a plain back. **A spec's rectangle holds the whole drawing:** the Mart's started a row low, so its roof's top 14 rows lay flat behind it as the map draws them (the proof judges only the rectangle, so it passed); it now starts a row up (every town's Mart found at the same places, a row higher). **The Mart is built as the Center is** (one kit, the user's call): its dark blue band (rows 36-44) a fascia like the Center's red one, the sign a board on it, the roof at the Center's 22 degrees, its back wall at z 20 where that pitch and the roof's drawn rows put it (a 31-degree roof over a thin eave, the sign standing up before it like a plank, looked unlike the Center from the side). The aim is a believable 3D world: the 45-degree proof is a guide, and a consistent shape wins over an exact one.
  - **Helpers:** `pallet_house` (hipped, striped hips), `gable_house` (eave, front and back slopes, an optional chimney), `gym`, `flat_top` (a top flat as drawn, falling away behind), `HipRoof` uses for the Centers, and `slabs`: runs read column by column off an outline (`{ x0, x1, top, foot }`), each a block whose front is projected and whose top falls back at 45 degrees. That fall is edge-on in the GBA's view and faces away from every lower camera. Slabs make the Cinnabar Lab's capsule, the Power Plant's octagon and its stacks, and the trees, statues and gables standing before a wall.
  - **Placement:** `match_rows` skips a top row drawn over different backgrounds. A FireRed-only rule in `Buildings.find` drops a placement lying wholly inside a larger one (one kit drawn at several sizes). `anywhere` lets a kit stand in another secondary tileset when its pixels match: the Sevii houses and harbor, drawn alike in all three of the islands' tilesets.
  - **Model cache:** models are cached by spec name (`models/v<MODELS_VERSION>/<game key>/`). After changing a spec in development, delete the game's folder there (or bump `Scene.MODELS_VERSION`), or the old model is served.
  - **The outdoor leftovers:** `gantry` (a tower and its beam, a cell across: the six Sevii ports' and the Power Plant's, one drawing), `market_stall` and the goods round it (`crate`, `till`, and the pots and flower baskets turned with `H.ProjLathe`, tagged `~proj` as props are), `harbour_canopy` (Vermilion's two and the S.S. Anne's gangway), and `trainer_tower`: column runs off its outline (`TOWER`: its octagonal platform 8 high, the tower on it to the map's top, the porch). Trainer Tower's platform stands on the rock a level over the porch's grass: the model's base is its rect's bottom-middle cell (the porch's foot), so the platform and tower are lifted 16 and set 16 south (the same at 45 degrees), and the spec gives its cells' relief levels (`cell_level = { { i0, j0, i1, j1, tiles } }`, read by `Scene.modelCells`; other owned cells take the level south of the building) and grass under the porch (`cell_ground`).
  - **`anywhere` by pixels:** a secondary tileset's metatile number names nothing in another secondary, so where an `anywhere` spec's cell has the same number in another pair, `Buildings.find` asks the look-alike check too (the gantry's tower cell is 0x2E7 at Two Island and on Vermilion's dock; without it the gantries stood in 300-odd places). Emerald's placements are unchanged (all layouts, placement for placement).
  - **Mt Ember's volcano rock** stands, read as a cave (below, `F.caves`): its outside and its summit.
- **FireRed's rooms (`src/scene/models/interior_specs_firered.lua`):** `roomJob` takes the game's own room specs (`deps.RoomSpecsByGame`, loaded by main.lua), or Emerald 3DS's for a game drawn with Hoenn's tilesets. Our own reading of each room, by Emerald 3DS's method, in `interior_specs.lua`'s format (`piece`, `facet`; `repeated` stands one piece at more cells, each textured as drawn there: `at` + `variants`). FireRed's rooms draw with their own primary tileset (`fr:building`), and `Interiors.layoutOf` cuts tiles and palettes by the pair's family (640 / 7). Done: the Center's two floors (`LAYOUT_CELADON_CITY_POKEMON_CENTER_1F` / `_2F`, which every town's Center draws), the Mart (`LAYOUT_CERULEAN_CITY_MART`, every town's) and the eight gyms. The rest lie flat as drawn (Emerald 3DS's rule).
  - **The gyms:** `gymStatues` (a figure card on a 16-row pedestal; Pewter's pedestal and Vermilion's figure are found again by their pixels in the later gyms and stand there as their bare twins), `gymBlock` (a maze wall: a group of the layout's blocked cells, each drawn from `above` rows north of its cell, `height` rows of front: Viridian's 4 / 13, Cinnabar's 3 / 17; the groups read once off the metatile grid and kept as cell lists), `repeated` (Pewter's boulders, Vermilion's cans, Celadon's bushes as balls, Cinnabar's quiz machines: its copies stand by the cell their shape's bounds start in). What a script swaps (Vermilion's beams, Cinnabar's doors) and what is too thin to read as a block (Saffron's partitions) stays as drawn.
  - **The Pokémon League:** `eliteFourRoom` (Lorelei's, Bruno's, Agatha's: back wall, the south wall either side of the way out, side walls, three pillars a side), `lancesRoom` (the same 48 rows lower, its pillars dragon horns: a card on a pedestal; the small statues in his halls are found as Pewter's) and `championsRoom` (an octagon: the 55-row back wall, 32-wide cut corners, four posts). All five 0.0%.
  - **Silph Co. and the Rocket Hideout:** their walls are bands two rows deep, read off each floor by rule and kept as data (`SILPH_BANDS`, `ROCKET_BANDS`: { first column, last column, top row } a band): the blocked cells drawn at least half in the band's colours, grouped, kept where they run two rows deep, each run's columns filled in both rows (a plant's crown over a band leaves the wall whole behind it). Each stands 30 rows (Silph) or 28 (the Hideout) to its foot under its white edge. The bands were read once by that rule, over each floor's drawing, and are kept as data. The partitions seen from above stay as drawn. 2F's furniture (plants, desks, stools, computer tables) stands on every floor by reuse, and the lobby takes the Center's stools, tables and chairs. Each floor's bands are `alone`: another floor's, found by its pixels, stood on a floor's own at the same depth and its texture's filled-in spots showed. All 0.0%.
  - **The Pokémon Tower (`towerShell`):** every floor is the same round hall; its back wall steps down either side, each step a run of columns with the same panel row (`TOWER_STEPS`, from column 2) standing 26 rows to its foot, with the rim running down its inner end (8 px) from the step above's: the wall's top turning south. The cells that rim crosses are outside the hall and `skip`ped (else they'd be the piece's floor marks, and the front's skirt row reads them). The graves are one cell each (3F's, and 7F's gold ones, listed by their own pixels: a plain piece the later floors reuse, plus the rest `repeated`, which isn't registered for reuse); 7F's statues are a bust card on a pillar. All seven floors 0-0.1%.
  - **The Fighting Dojo:** back wall, two low partitions (24 rows, their cream tops running back to the wall's foot: the wall's rim shows above them), a vase card and `gymStatues(..., deep)` (pedestals 12 rows deep under a shorter figure). 0.0%.
  - **Walls by their rail (the Mansion, the S.S. Anne, Trainer Tower):** read per pixel column, not per cell: a column drawn as the rail or cornice (6 rows or more of its colours) with the foot line a set number of rows below (Mansion 40, Anne 24, the Captain's office 32, Trainer Tower 26), or, a foot hidden by something standing before it, the wall's own colour a set number of rows down; columns with the same rail row grouped, small gaps closed (3 px; a door's 16 px on the Anne), kept as `{ x0, x1, rail top }` (`MANSION_WALLS`, `ANNE_WALLS`, `TOWER_HALL_WALLS`). These walls are `alone`: without `fill` a piece registers as loose (found by its own pixels anywhere), and a wall would be found all over the next floor; each floor stands its own. The Mansion's furniture is modelled on 1F and 2F and reused on the floors below (its plants and the Anne's are the Center's); Trainer Tower's posts are modelled on 1F, its console is each floor's own. The Mansion 0.0%, the Anne 0-0.7%, Trainer Tower 0.0%. Trainer Tower's lobby and roof and the Mansion's partitions seen from above stay as drawn.
  - **Pallet's rooms:** the engine gives them Gen 1's names (`FR_OAKS_LAB`, `FR_PLAYERS_HOUSE_1F`, `FR_RIVALS_HOUSE`), which aren't their maps' (`PalletTown_ProfessorOaksLab`), and prepares each layout (`native/layouts`) only once the player has been in. `relief_input` names a map no engine name matches by the longest name no other map took that its own name ends with (`LAYOUT_OAKS_LAB`). **Oak's lab** (the first rival battle's room): the back wall (a 7-row rim over 25 rows of front), against it the two machines, the desks with the PC standing at their back, the bookshelves; in the room the Poke Ball machine, the green table, two rows of bookshelves, the plants by the door. 0.0% (2 px: the table's rounded corners). A room the player hasn't been in yet lies flat.
  - **Five Island's Rocket Warehouse** (Team Rocket): its rooms' walls (a 5-row rim over 25 rows of front to the dark line) and the white posts at the partitions' ends (13 rows of top over 25), read per pixel column by their band (5 rows of 6AA4AC over the line) or their grey (20 rows or more of B4B4A4 over it) and kept as data; the crate stacks, each a group of the crate cells (metatiles 395 / 099, 4-connected) standing as a box over its cells with 7 rows of front (`gymBlock`). 0.0%. The Mart's boxes (on its counter, 9 rows up) are the crates' drawing: found by their pixels they floated over every stack, so they are `alone`. The warehouse's crates are found again on Silph Co.'s floors, which draw the same crates, and stand there too. Silph's computer racks are its own (5F's, found on the other floors and in the Hideout): Oak's lab's machine draws the same racks, but its top behind the lab's wall is the wall's there, so it stays `alone` in the lab. The rack's top reaches back to the wall's face (64) and no further: behind it the wall hides the top's first row.
  - **The Power Plant** (wild Pokemon, Zapdos): its walls read by rule per pixel column, by their blue base (839CB4 under A4BDD5, the dark line 4 rows below), columns with the same foot grouped and the diagonal braces at each run's ends taken in, kept as `POWER_WALLS` { x0, x1, the row under the line }: each stands 25 rows of front to the line under a 15-row top. 0.0% (a wall to the row under its line covered that row: the foot is the line's own row). Its partitions (tops alone, in the floor's colours), drums, rubble and generators stay as drawn.
  - **The Tanoby Chambers** (Seven Island, wild Unown; all seven): each a maze of teal stone walls round the room, read as Viridian's gym's are: a wall a group of the layout's blocked cells inside the room (4-connected, read once by `blocked_groups.lua` in the scratchpad and kept as `TANOBY_WALLS`), its light top drawn from 13 rows above its cells over 19 rows of dotted front (`gymBlock`); the brick back wall, 22 rows of front to 32. All seven 0.0%. The narrow corridors leave the stage little open floor: a foe can stand right behind a wall.
  - **The S.S. Anne's deck** (sailors battle there): the cabin on its east side a block (its roof, 32 rows of front; its light west face and the doors' notch lie on its top), the barrels in rows (each row its own block: a block's top is its shape's bounds, so a stack in an L is two pieces), the two deck chairs and three round tables. The railings and the hull stay as drawn. 0.0%.
  - **Celadon's Game Corner** (a Rocket guards its poster): the back wall; the prize counter, a green L each side with the shelves on it standing at its back, a glass case between; the purple counter; four columns of two-sided slot machines (each a block, 16 rows of front: the GBA draws them from above), the outer two half drawn at the room's edges; 30 stools (`repeated`, five a column either side); the plants and the machine by the door. 0.0%: a column's top corners, drawn on the diagonal (its machines' side panels), are kept by the notch (Reading a room).
  - **Reading a room:** its corners are measured column by column (FireRed's Center and Mart: 35 rows, their top at 13 - x, their foot at 48 - x); a piece's depth is read off its drawing (`back` = the row its top starts + its front's height: the Cable Club's counter is 10 px deep, the Mart's gondolas 3). Colours that are both wall and furniture (the Mart plant's greens, Pewter's sand and wallpaper) are left out of `leave`, the piece bounded by its shape (an ellipse for Pewter's boulders; the back row's leaves the shadow under it out, or the dome fitted to it grows a row past the drawing). A top's first drawn row stands at the wall's face, not behind it (the Center's healer is 16 tall, its bookcase 21, Silph's racks 20): a top reaching behind the face loses its first row to the wall.
  - **Corners (`notch`):** FireRed's pieces (`corners`, on by default in `interior_specs_firered.lua`) reach back to their `back` column by column, each only as far as the drawing shows a thing there: not past the floor (or its shade), a wall, or a piece standing behind (its foot no nearer than the top's back) drawn where its back would be seen, above the piece's own pixels. A corner rounded or cut keeps its shape at 45 degrees (tables, counters, pillars, the slot machines, a pedestal's corners beside its figure, a barrel's round top before the barrel behind it); a figure standing in front stops it. `Relief` takes it per column (`notch`); Emerald's pieces don't set it.
  - **Copies (`at`):** `repeated` writes each copy's cell as the cell its shape starts in; the room moves them to stand by the piece's rectangle (where its first drawn pixels are), a row or two lower when the shape is drawn over the cells above (Silph 2F's stools and plants, Cinnabar's quiz machines).
  - **The proof (`tests/drivers/room_check.lua`, `Check.render` in `tests/model_check.lua`):** every piece standing in a room drawn together at 45 degrees, the nearer over the farther, against the room's drawing (`exports._roomLayout`): wrong (a covered pixel in another colour, but for `over`: a top rising over what another piece owns), missing (a piece's own pixels left bare), stretched faces. Emerald's own rooms, ported number for number and confirmed against Emerald 3DS's release, set the bar: 0-10% of covered pixels wrong (the Center 0.8%, the Mart 5.0%, the lab 10.6%), nothing missing, only the cut corners stretched. FireRed's: all 71 rooms 0 wrong, nothing missing, nothing stretched (LeafGreen's the same); Emerald's 145 of 193 under the same proof. What lies under the ground (a face's skirt, run a unit below the floor so no seam shows) is hidden by the floor in the game, and the proof hides it too. `ROOM_PROBE=x,y;...` logs every face covering those pixels (piece, tag, depth, texel): the way to find which part draws a wrong pixel. A room whose build failed is listed as such. A piece reused in a later room is listed with the room it was modelled in (its `reused_at`, or `bare_at` when found by its own pixels): the proof looks through every room's pieces. `ROOM_VERBOSE=<text>` lists what each room places. `ROOM_CHECK=name,...` picks rooms; each writes `room_<name>.ppm` (drawing | the room at 45 degrees | marks).
- **First run (`src/prompt.lua`):** the question and Build 3D Cache come up in the games whose world is built in 3D (`P.GAMES_3D`: Ruby, Sapphire, Emerald, FireRed, LeafGreen). `Run.TICKS` holds each game's measured build (FireRed 62,662 ticks against Emerald's 117,030; LeafGreen draws the same maps). Measured in the scratch engine: FireRed's whole build in 46 s, LeafGreen's in 41 s. `tests/drivers/first_run.lua` takes `FIRST_RUN_SPOT=MAP:x:y` for another game's field (`FR_ROUTE_1:10:20`).
- **FireRed's caves (`src/scene/relief_caves.lua`, `F.caves` in `games/firered.lua`):** our own rule, after Emerald 3DS's counted levels (they leave their caves flat but Rusturf Tunnel). The solver reads outdoor maps only, so caves had no relief; `relief_run` now adds them after the terraces (not for Emerald).
  - **Pieces:** each cave piece is a shape over its cell, in levels over its own base: a face 1 → 0 down its rows, a west / east side 0 → 1 / 1 → 0 across its columns (a slope a tile across a level, as drawn), a face's end (`SW` / `SE`: the lower of face and side), an inside corner (`FE` / `FW`: the higher), a rim (`N`, `NW`, `NE`: flat, its north edge, and a corner's west or east edge, a step: the top's back), a side's head (`HW` / `HE`: a block's rim corner over its side, falling as the side does, as Emerald 3DS's band heads; flat corners left the side and the rim apart, and the top looked sunk between them; over anything but its side the same piece is the rim's flat corner, `NW` / `NE`), a thin wall's sheer side (`TW` / `TE`), the dark past the rock (`void`) and the water (`water`: by behaviour, the relief's water names plus the table's own, Seafoam's currents; it joins nothing and lies at the lowest of its banks, so banks at two levels no longer tie together through it). Everything else is flat; the General's carved stairs (091, Cerulean Cave's) are faces.
  - **Levels:** two neighbours join wherever their shared edges have the same profile (offset = the level step); edges whose profiles differ are steps that `Relief.cliffWalls` closes. Joins go through a union-find with offsets: flat beside flat first (the floors and tops, and a rim beside a rim: flat, its north edge a step), then piece beside piece (the walls: a wall two faces or two sides deep is two levels however its ends meet the floor), then each wall against the flat it meets, and each rim against the floor or a piece, by vote, the offsets the most edges agree on first, and on a tie the join with the floor (a rim strip between a two-tile side and the floor it runs into lies level with the floor, its step at the side: a rim joined to the side first left the Dunsparce Tunnel's pit rim a level low, a hole beside it in game). A misread piece, or a one-tile end of a two-tile wall, shows as a disagreement at its own edges and never tears a floor apart or flattens a wall (first come, a wall's one-tile end outvoted the wall: Mt Ember's B5F chamber read a level shallow). Each connected part counts from the level most of its flat cells stand at (0). The void takes the highest top of the rock it touches and spreads through itself.
  - **Records:** cells with any height are written; a wall record (`face`, `BLOCK_WALLS`) wherever a cell's west, east or south edge stands over its neighbour; a rim's back (ground = the cell north of it, or `ground` under a piece) where the cell behind is a level lower. Layouts are flagged drawn.
  - **The table:** FireRed's cave tilesets draw their rock alike up to 2E0 (shared `pieces`); past it each has its own (`groups`, keyed by layout name so LeafGreen's other tileset addresses don't matter: Mt Moon's with Victory Road, the Lost Cave and the Dunsparce Tunnel, whose side walls' tunnel mouths 30A / 309 are drawn on the side; Mt Ember shares Mt Moon's 2E rows and has rims with ash on them, 328 / 32A; Seafoam and the Icefall Cave, their ice ledges' rims 2A0-2A2; Rock Tunnel and the Altering Cave). A mouth drawn on a face (294) is the face. 2A3 is a rim's end in some caves and the plain rock top along a map's edge in others (Mt Moon 1F), so it stays flat but in Seafoam's tileset. Each shared id was checked in every cave tileset against Mt Moon's by its pixels' classes (floor / top / face colours).
  - **Proof (scratchpad probes, run from the engine root):** `cave_levels.lua` draws each cave with its levels tinted (and its ids, `<name>.ids.txt`) and counts the disagreeing joins (the review sheet's caves too), 61 in all FireRed's caves (55 before the rims joined their floor first, which moved the Dunsparce Tunnel's to the side and set some of Mt Ember's at the other end of their side; 588 before the Sevii pieces and the vote, 185 before the tilesets' own rims, heads and shore corners): the Lost Cave's rooms, Diglett's Cave (its entrances' pit pieces only theirs: the same tiles rim the tunnel's raised rock tops), the Icefall Cave (its sides 33D / 33E, the snow's rims over the water 30B / 2FE / 2FF, its outer sides' heads 2A0 / 2A2, the shore's corners 366 / 367 / 36E / 36F) and Seafoam B4F read with none. The rest are local and the drawing doesn't settle them: Mt Moon B2F 13 (a raised floor that one join puts level with the floor west of a gully and another with the floor below a thin wall), Navel Rock 19 (its summit's peak), the Dunsparce Tunnel 7 (a ledge between two cliffs a face below the plateau to its north, open to the same plateau to its south), Mt Ember 14, Cerulean Cave 1F 2, Mt Moon B1F 1, the Sapphire Room 5. `cave_verify.lua` checks the shared ids per tileset. In game, shoot caves with `RELIEF_BUILD=1`: without it `scene_battle.lua` loads no relief and the shots are flat.
  - **Mt Ember's outside and summit** (the Sevii outdoor tileset's grey rock, stepped as Emerald's mountains are) read with their own group: `LAYOUT_MT_EMBER_EXTERIOR$` / `LAYOUT_MT_EMBER_SUMMIT$` (a name ending `$` is that layout alone, not a prefix), `over = true` (read over the outdoor relief, which left the mountain flat: its records for the layout are dropped), its own `face` (35C) and `ground` (385) for walls and rims. Its pieces were read by sight off the summit: the summit's sand has 353 on its west and 355 on its east, so 353 is a side falling west and 355 one falling east (an earlier try had them the other way and read the plateau two levels low, 518 disagreements); faces 35C / 359 (and the mouth 346, the stairs 091 / 089), ends 35B / 35D and their sand / grass forms, inside corners 335 / 334. Each band is a full level a tile, as Emerald's are: read so, the drawing disagrees with itself at 14 edges of the outside's 3078 cells (at the entrance's two pillars); read as 35C over 359 one step two tiles deep, at 283; with 35C flat, 652. Emerald's own relief uses the same shapes (a face 16, 12, 8, 4, 0; an end the lower of face and side; an inside corner the higher), so the steps look as Route 112's do. The outside stands 23 levels from its lowest grass to the summit's stairs.
  - **Hand marks (`marks` on a group):** `{ [layout name] = { ["x,y"] = kind } }` sets a cell's kind by sight where the drawing contradicts itself (`"."` flat). The summit's crater foot: its last face (8,3 / 9,3), the funnel's inner sides (7,3 / 7,4 / 10,3 / 10,4) and the sides beside the sand's tongue (6,6 / 6,7 / 12,6 / 12,7) lie level with the sand; without them two slots opened beside the sand in game. 5 disagreements remain, high on the summit's rock.
  - **Layouts a script swaps in (FireRed):** `Input.ALTERNATES_FRLG` (`Input.alternatesFor(game)`, with the baked layouts' prefix `FR_`): the scripts' four `setmaplayoutindex` layouts, each matched to its base by its cells - the Dunsparce Tunnel dug open (319; the game draws it from the start, special 403, while the stored layout 318 is a small room in solid rock), Seafoam B3F / B4F with the currents stopped (278 / 279), the Seven Island house's room with its door open (264). They are read, stood and reviewed as Emerald's alternates are, and `World.settle` picks the one the game draws (its cells against the live ones).
  - **Left flat:** the rubble, ladders, holes (a cave's round boulders are its tileset's own: not the General's); the Underground Path (its own tileset). Tanoby's chambers are rooms (their mazes: `interior_specs_firered.lua`).
  - **Taller or sheer (off):** `C.stand` (tiles a level) and `C.sheer` (sides as sheer walls) stand the rock apart from its drawing (`Caves.standing` heights, `Caves.depths` where each point of the drawing stands: a face's drawing a tile tall at the top of its wall, the wall below closed a course at a time). Tried and turned down in game: two tiles a level was too tall, sheer sides too vertical. They write the relief's optional depths (`DPTH` after the `EDGE` block: per cell, 25 depths; `Relief.view` → `L.depths`, `cell.s` in placement; `emitCell`, `cliffWalls`, `northFace` and the seam skirts place points by depth, heights by height). Without depths depth = height, and a relief with none writes nothing new (Emerald's bytes are unchanged). The stage search counts standing rock over the camera's line of sight (`sightBlocked`, only cells with depths).
  - **Build:** about 1 s and 3,850 ticks (`Run.TICKS.firered.finish` 3,993). FireRed's rules version is 10.
- **FireRed's boulders on land (`props.lua` `fr_boulder`):** the round boulder (metatiles 09F / 0A7 / 0AF / 0B7: Routes 11 and 23, Kindle Road, ...) is the same four upper-layer tiles of the General every time (120 / 121 over 136 / 137, palette 1) over whatever ground its cell draws, so it is found by its tiles as Emerald's sand boulder is and stands as the same low dome on its cell's ground.
- **FireRed's picket fences and mailboxes (`props.lua` `fr_picket`, `fr_mailbox`):** both are the General's upper-layer tiles, palette 2, whatever town tileset's metatiles carry them (Pallet's 284 / 287, Celadon's, ...): every picket post is one 8-pixel column, tile 14 over 30, and a mailbox tiles 336 / 337 over 352 / 353 over 368 / 369. Each stands as a turned shape (`lathe`, its drawing projected, cut to the drawing's box), read off the drawing: a post 6 px across, its cap drawn from row 2 and its foot at row 12 (radius 3, depth 0.6, standing at 10.2, 6.4 tall); the mailbox 12 px across, its arched top from row 2, its front's foot at row 19 (radius 6, 0.6, at 15.4, 9.8 tall, its top rounded). The fence has no rails: what is drawn between the posts lies on the ground. FireRed's specs hand the props Emerald 3DS's two shape helpers (`ProjLathe`, `ProjDome`: geometry alone; their faces "~proj", the drawing projected).
  - **What a prop's model leaves bare lies flat (`bareOf`, `md.bare`):** the object's drawn pixels the model doesn't cover at 45 degrees (a mailbox's post and its shadow, a picket's rail stubs and shadow, a log's shadow) are laid on its cells' ground; the ground under a prop leaves the object's upper layer out, so they were lost. Pallet's mailbox 70 px, a picket 31, a log 20, a log side-on 9; Emerald's props leave none bare (their ground unchanged).
  - **Log fences (`fr_log`, `fr_log_side`, palette 1):** a post is tile 46 over 62 (6 px across, its cut top rows 2-6, its foot row 12: radius 3.2, depth 0.8, at 10.6, 6.1 tall; its grey shadow a `ring`, laid as ground); seen down the fence's length the posts stand 8 rows apart, each tile 63 a post's top and the body of the one behind it (one post a tile, its top on the cap). Two props share each fence cell, and their cells are "covered" (both layers under the player, the game's composite has the posts in its lower image): `placeProps` gathers the quarters every prop on a cell leaves out before laying any ground, so neither post is laid flat by the other's ground. A tree's tip cell is read as the ground it lays (`propMid`: `World.subtiles(L, remap)`, the prop's art and its ground): Four Island's saplings' tips are drawn over the fence in the island's own tile, its posts on the lower layer in other tiles, and stand as the plain fence's.
  - **Picket fences seen down their length (`fr_picket_side`, `fr_picket_end_n`, `fr_picket_end_s`):** tile 47 is a picket seen side-on (4 px across, its cap rows 1-6, the body of the post behind over it: radius 2, depth 1.5, at 10.4), as the log's 63; a run's ends are the front post with the run behind it (15 over 30) or going on south (14 over 31). Route 5's hut fence. **`extend`** (a prop spec's): its drawing carried down that many rows past each column's last drawn row - a side-on post's body, hidden at 45 degrees by the next post's cap, is drawn nowhere, so its lathe came out see-through (clipped or not) and looked like half shells from the side; carried down, it is the post's own body colours (`fr_picket_side`, `fr_log_side`: 6).
- **The Safari Zone's tree (`games/firered.lua` `forests[4]`):** 3 cells across, drawn four rows tall - the crown's crest in the cell over the tip row (`alone.crest`: 310-312 on the grass) - and stacked two rows apart as Viridian Forest's. A species naming `alone.crest` has 64-texel art (`Trees.rowsOf`, `S.rows`): it stands from a row higher, its profile reads the crest row too, and `Check.tree` judges all four rows. The woods are lower layer and the alone tree's crown upper (`leavesBelow`, its `groundColours` the grass, shadow and ring); every tip-row variant is `tipToo` (a stack's top, or under a crest). Its trunk forks out under the crown to column 9, so in an atlas wide enough (four species: 512) a species' trunk has its own columns past the ground (`trunkX = 32 * w`), and the trunk card takes only the columns whose trunk colours reach the trunk's lower half (`trunkCol`: the fork's branch tips lie with the ground; the whole fork stood a board seen from behind). Proved 0 / 3072 wrong (the other four species still 0).
- **The flat census (`tests/drivers/flat_census.lua`, `Scene._layoutCover` / `hd._layoutCover`):** every cell of a layout nothing stands - `placeBuildings` over the whole layout (buildings, rooms, props, bridges, components) and the trees taken off - that draws on its upper layer or blocks the player; one line a cell to `SHOT_DIR/flat.tsv` (layout, x, y, metatile, upper-layer pixels, blocked; `FLAT_IDS` a file of layout ids). Cells a building cut by the layout's edge leaves are listed too (the scene's window finds it across the seam), and so is rock the relief shapes: set the relief's cells aside. The General tree's tips over a picket (0D6 / 0D7: the fence in the lower layer) are read as the plain fence (0E7) for its props: `propMid` is `Trees.groundMetatile` for the General's cells too.
- **A game's own components (`games/<game>.lua` `components`, `Components.useGame`):** run specs after Hoenn's, keyed by the family's tileset names (`fr:rom082d4b84`, so neither game's are drawn by the other's). Route 23's gate walls (`fr_route23_wall`): `K.Relief` runs of the walls' upper layer, 31 texels of front (the cornice's dark band and the façade, rows 33-63 of its two rows) and the rest the top - the slats and the column ridges; no `block` (a seam copies `height` rows of the one cell south, and 31 > 16), so each run is built whole. The statues before the pillars are `league_statue`'s (the run leaves their cells: each pillar's front ends at its plinth, an alcove). The arches over the gaps are a spec (`route23_arch`, `anywhere`: over grass, water or path): two lintel boxes on the pillars' tops (front z 74, 8 deep: 30-38 and 59-62 high) and an upright card for the struts and flared ends, their faces clear where nothing is drawn. The court's round stones are a prop (`fr_route23_stone`: a squat turned stone, keyed to the route's tileset). Route 23's flat cells 1109 -> about 90 (left: the League gate's roof, cut by the seam; the pedestals' and walls' shadows, flat as drawn). Routes 12 and 13's boardwalks (`fr_boardwalk`, rom_082d4b0c): the decks and the cells under their south edges (308-30B: the dark edge, the pilings, the shade on the water) one run, 6 texels of front (rows 31-36), `hull = 1` joining a north-south walk's planks across their one-texel gaps (left clear); 802 -> 205 flat cells (the rest shores and grass). Saffron's iron railing (`fr_saffron_railing`, rom_082d4b9c): Rustboro's railing recipe - 11 texels (the top rail rows 3-5, the bars to row 13), `hull` 11 so each bar's column is a whole front, `bridge` 3, 319's bars the `flank` of a run down a column; 324 -> 72 flat cells (slopes, signposts, the gatehouses at the seams). Fuchsia's pens (the Safari's tileset, rom_082d4b54): the hedges (`fr_fuchsia_hedge`, 9 texels of front) and the grey panel fence (`fr_fuchsia_fence`, 12; 338 / 339 draw it in their lower layer, so it reads both layers less the grass). **`propAlias`** (`games/<game>.lua`, read by `propMid`): a secondary's own lower-layer drawing of a General prop read as the General's metatile - Fuchsia's pickets 336 / 337 / 33F as 0E7 / 0ED / 0F5 - so their posts stand as the picket props and their ground is the plain grass. **Lower-layer props (`lower` in `Props.OBJECTS`):** found on the raw metatiles' lower layer (`World.subtiles(L, nil, true)`, `Props.find` passing `lower` to its `subtiles`), their art the cell's own lower layer less what the plain ground it is aliased to (`propAlias`) draws alike there; the ground laid under them is that plain ground. The Safari's stakes (`fr_stake`: the General's 340 over 356, palette 1, only ever in the lower layer of 308-30A under a tree's crest; the log post's lathe), the Safari's 308-30A aliased to grass (001).
- **FireRed's sea rocks (`props.lua`):** `fr_sea_rock` and `fr_sea_rock_pale`, each four General tiles in a square at the corner four metatiles share (as Emerald's sea rock): tiles 420-423 in palette 4 (metatiles 0x110-0x119) and 173/174 over 189/190 in palette 2 (0x1CB-0x1D4). They stand as Mounds on the General's plain water (0x12B), their pale outline the foam. The relief solver's own copy of the objects is unchanged (FireRed's relief bytes stay the same); the rocks' cells are water to it.
- **A forest's own tree (`trees.forests`):** Viridian Forest's tileset (Six Island's Pattern Bush's
  too) draws its own tree, 3x3 cells (tip 288-28A, crown 290-292 / 2A0-2A2 / 28E-2A1-28F, trunk
  298-29A / 2A3-2A5), stacked two rows apart. It stands as the General tree does, as a species of
  its own (`Trees.species[k]`, k >= 1; `[0]` the General tree): named by the maps drawn with it
  (`layouts`, resolved to this game's tileset by `Trees.resolveForests` through `layoutCtx`: its
  tilesets are named by ROM address, LeafGreen's apart), its parts numbered from 16
  (`Trees.partCell(part)` -> col, row, width, species; the General tree's stay 0-3), its art at its
  own place in the tree atlas (row 64: crown 0-47, ground 48-95, trunk 96-127), read off its own
  tileset (`Trees.kantoArt(px, set, k)`; a species whose art can't be read is `failed` and lies
  flat). It draws the whole tree on the upper layer, its grass and shadow too: `groundColours` are
  read as ground, and rows under the skirt (`cone.skirt`) are read as the trunk row is (the
  drawing: trunk, the cone's cover, or ground). Its crown is a dome whose flat top is drawn on row
  0: the profile runs on above the drawing's top row to the apex (`tip` -6), seen from above. 299
  is also the middle of a stack's top tip row (`tipToo`: no crown row over it, it lays the tip's
  ground and stands nothing). Lighting finds a wider crown's middle by `crownCol` / `crownRow` /
  `crownW`. Checked at 45 degrees with the scratchpad's `tree_check2.lua` (species k): 0 of 2304
  texels wrong (the General tree still 0 of 1536). Three Island's Berry Forest draws the same tree
  (same ids, trunk and shadow) golden in a tileset of its own: a second species from the same data
  (`forests[2]`), its art read off its own tiles. Four Island's saplings are a third (`forests[3]`):
  one wide (`w = 1`: its art's trunk card after the ground, from column 0, `trunkMin`), its parts
  the General's tiles (01B over 023: `Trees.part` asks the map's forest for a primary metatile the
  General tree doesn't have), its tip drawn in the island's own tile over the fence (2BF, its
  ground the plain fence 0E6, the fence's colours in `groundColours`). Its crown row is drawn
  under the player (its layer type): the game's pixel source has its leaves on the lower layer,
  where pret's composition (the offline probes') has them on the upper, so `leavesBelow` takes
  leaves off either layer, less the ground's colours. With more than one forest the atlas is 256 x 256
  (`Trees.KANTO_W/H`, and `Trees.DIM`, which the tree meshes' uvs are divided by; Hoenn's stays
  128). A dome's crown is its front only, as the General tree's cone is: seen from above (the
  swoop) it read as a crescent. `cone.lid` (25) closes it: the crown's quads whose front stands at
  least that high, laid level at that height, each texel where the 45-degree view draws it, so the
  lid hides behind the front at 45 degrees (still 0 wrong) and fills the crown from above.
- **Kanto's trees (`src/scene/trees.lua`, `games/firered.lua` `trees`):** Kanto's General tree (2x2:
  a crown row whose upper layer covers the player, over a trunk row, stacked through the woods, its
  tip drawn in the cell above) stands as its own model, built off its drawing as the rooms' pieces
  are: seen at 45 degrees it is its drawing, texel for texel. `Trees.useGame` takes the game's
  table: its parts (crown row `01C`-`01F`, trunk row `014`-`017`, `024`-`027`), the tree alone on
  grass (`alone`: tip `00E`/`00F`, crown `01E`/`01F`, trunk `024`/`025`), the tip cells' ground
  (`00E`/`00F` lay `001`), the trunk's colours, and `cone`: numbers read off the drawing (the tip's
  row 3, the skirt's front edge 41 (its last leaves and their shade over the trunk's top), the tree standing on row 40, the middle of its shadow's
  ellipse, the squash 0.65 that puts the skirt's sides where they're drawn). Every variant stands
  as the one tree, from its crown row's west cell (or its trunk row's, the crown row drawn over or
  past the scene's window: `partAt`'s second value).
  - **The model (`Trees.kantoTree`, `Trees.kantoFront`):** the crown is turned about its axis, as
    wide at each height as the drawn crown is on the row its side is drawn on (`KANTO_PROFILE`), so
    its outline is the drawing's. Its front is cut into quads on a grid of the drawing's columns and
    rows (`KANTO_QUADS`, those holding a texel of it); each corner is the point the 45-degree view
    puts there (solved up the height: past the outline, the plane through the axis; under the
    skirt, straight down from its edge), so every quad's uvs are a rectangle of the drawing. The
    trunk is a card upright at its drawn foot, from the ground into the skirt. The shadow lies flat.
  - **The art (`Trees.kantoArt`, read off the player's tiles once a game, into a 128x128 atlas,
    `init.lua` `treesArt`):** the crown (0, 0) is the tip and crown rows' upper layers and, of the
    trunk row, what the cone covers; the ground (32, 0) is each row's lower layer, the trunk row's
    with the cone's and the trunk's texels replaced: behind the tree's foot (row 40) by the shadow's drawn front turned about that row, so its back is as round as its front; else by the first ground below them,
    and grass (the tip row's) under the leaves of the rows above, as a reader may give the crown
    row's lower layer with its leaves; the trunk (64, 0) is its colours, carried up each column
    where the cone hides it, with what is drawn between the skirt and the trunk's top. Colours are
    compared at 5 bits a channel: the engine and the tests' reader widen them differently. It is
    graded as Hoenn's tree texture is, over its crown (`Light.gradeTrees(data,
    Trees.KANTO_CROWNS)`). The proof: one tree's emitted quads rendered at 45 degrees
    (`Check.render`) against the alone tree's drawing, 0 of 1,536 texels wrong.
  - The workshop's tree settings (lean, height, foot, sink) shape Hoenn's crown cards. Kanto's
    trees (the General's and the forests') take their own two, the game's alone (not a tree's
    mark): `depth` (the crown front to back, a share of its reading: the cone's squash) and `stand`
    (texels south of its reading: the trunk and the crown's axis). Whatever they are, the tree is
    its drawing at 45 degrees (the cone is solved row by row; past its profile's rows its radius is
    its widest); its art is read again when they change (`Trees.artKey`, the art's cache key).
    Their `hide` mark hides a tree.
  With `Trees.kanto` set, `Trees.tilesets` finds the General by the family's name (`fr:general`),
  so the scene's tree passes (shadows, the stage's tree heights, the relief's trunk ground) run in
  Kanto as in Hoenn.
- **The review sheet (`tests/drivers/review.lua`, `tools/review.ps1`):** every model the scene
  stands, proved against the game's own drawing at 45 degrees and gathered into one page.
  - **Run it:** `.\tools\review.ps1 [-Game firered] [-Kinds building,room,tree,cave] [-Engine ..\gen1recomp]`.
    It boots a new game in the engine (which must load this mod), runs the proofs and opens
    `%TEMP%\woobleview-review\<game>\index.html` (a PNG sheet an item beside it; they show the
    game's art, so they stay on this machine). About three minutes for FireRed.
  - **What it judges:** buildings by `Check.building` (the spec's exact rectangles: wrong, missing,
    extra pixels and stretched faces), rooms by `Check.room` (every piece standing in the room:
    wrong and missing; `over` is not a fault), each tree species alone on grass against its three
    drawn rows, and each cave's levels as `relief_caves.lua` counts them, an edge marked where its
    two sides draw it at different levels. Each sheet is the drawing | the model at 45 degrees (a
    cave: its levels tinted) | the marks.
  - **Shots:** every item (`REVIEW_SHOTS`, default `all`; a number: that many of the worst) gets
    in-game shots: a wild battle three cells south of where its faults gather (`Check.focus`: the
    cell whose 5 x 5 neighbourhood holds the most; with none, where most rock stands, or a tree's
    trunk), as played, and the camera aimed at it (`_sceneLook`); a building two rows south of its
    rectangle, shot from the front, both front corners and behind (its sides and back: where a
    facade tile papered over them shows). The relief is built first if it isn't cached. Items are
    shot map by map; all of FireRed takes a long while.
  - **Unsettled caves:** a cave whose drawing disagrees with itself somewhere is "unsettled", not
    "off" (the drawing allows either level there; they were checked in game).
  - **Another build (`REVIEW_PAK`, `-Pak`):** a pak in Emerald 3DS's format (FireRed 3DS's) read to
    compare: its `VXL4` relief's levels tinted beside each cave's (and how many cells
    agree once aligned; it lifts rock a single level), and its `VXB7` buildings' placements against
    ours (`_layoutModels` in every layout: each building "models it in n of our m places"; a list of
    the places it models a building and we model nothing). With `REVIEW_KINDS=relief` and
    `REVIEW_OURS=<our relief cache .bin>`, every layout's levels side by side (drawn | ours |
    theirs, each tinted over its commonest level), the `REVIEW_RELIEF_TOP` (40) that differ most.
    `REVIEW_ONLY=name,name`: those buildings alone (their proofs and shots).
  - **The page:** filters by kind and name, only-mismatches (on by default), sorting by the share
    or the count of pixels off. Each item takes "looks fine" / "needs work" and a note, kept in the
    browser (`localStorage`, by game); "copy my notes" lists them as text to paste back. "Open in
    workshop" starts the Scene Workshop at the item (its map, the shots' spot, its cell selected
    and proved: `WORKSHOP_SELECT`) through a `woobleview-workshop:<game>/<MAP:x:y>/<x,y>` link,
    registered once for your Windows user by `tools/register-workshop-link.ps1` (`-Remove` takes it
    away; `tools/workshop.ps1 -Url` reads it).
  - `tests/drivers/model_check.lua` and `room_check.lua` run the same proofs (`Check.building`,
    `Check.room`) and write `.ppm` sheets, for one spec or room at a time. The trees' and caves'
    proofs read the game's layouts as the relief reads them (`Check.layoutsOf`); a tree species is
    proved by `Check.tree`, a layout's map found by `Check.mapIdOf` (the shots, the workshop).
- **The Scene Workshop (`tests/drivers/workshop.lua`, `tools/workshop.ps1`, `src/scene/tune.lua`):**
  tune the scene's models by eye and keep the result as data.
  - **Run it:** `.\tools\workshop.ps1 [-Game firered] [-Spot FR_ROUTE_2:5:5] [-Engine ..\gen1recomp]`.
    It boots a new game in the engine (which must load this mod), stands the player at the spot,
    starts a wild battle with Battle Scene on (for the session only; no option or save changes),
    and opens the scene it built. The game is held still, and the workshop takes the window's
    drawing and input. Its log and F12 shots go to `%TEMP%\woobleview-workshop`. It reads the land's relief (the 3D cache) first, building it if it isn't yet: the workshop holds the game still, so the frame hook that loads it in play never runs (without this every map lay flat there but its props and border).
  - **Use:** click a tree (or any cell) to select it; right-drag orbits, middle- or left-drag pans,
    the wheel zooms (WASD, Q/E, R/F, Z/X too); B is the battle's camera, O 45 degrees, T from
    above. The panel lists the trees' settings (`Tune.DEFS.trees`: crown lean, crown height, foot,
    sink): Up/Down picks one, Left/Right or its -/+ change it (Shift: x5), Backspace resets it.
    Tab switches between all trees (the game's settings) and this tree (a mark on its four cells);
    H hides this tree (its ground stays). Each change rebuilds the scene (`Scene._rebuild`, about
    0.3 s). Ctrl+S saves, Ctrl+R goes back to the saved file, Esc quits (unsaved changes are
    dropped).
  - **The proof (G):** the selection against the game's own drawing in the GBA's projection, as
    the review sheet proves it (`tests/model_check.lua`): a tree, its species alone on grass under
    the settings being tuned (`Check.tree` with the scene's own `Trees`); a building, its spec
    (`Check.building`; a fence or curb is the scene's own, with no spec); anything else indoors,
    the room the spot is in (`Check.room`). It shows the counts and drawing | model | marks; V
    turns to the model laid over the drawing (pulsing) and to the marks alone. It is proved again
    after every rebuild. Kanto's tree holds the drawing at 45 degrees by construction (its crown
    textured by projection, its cone's radius fitted row by row on screen): its depth and stand
    change it only away from 45 degrees, and its proof stays 0. A prop: its drawn subtiles
    (`Check.prop`; what lies flat counted `flat`, amber, not missing). `WORKSHOP_SCRIPT` hooks:
    `prove`, `proof`, `setView`, `hd`, `defs()` and `group()` (the panel's, following the selection).
  - **Ground (Shift+click / Shift+drag):** Shift+click adds or drops a cell, Shift+drag selects a
    box; the panel turns to the cells' `ground` (`Tune.DEFS.ground`, marks only): Level (levels
    over the map's base; shown as the land reads it until set) and Shape (`Relief.GROUND_SHAPES`:
    flat, a slope falling south / north / west / east a tile a level, a rounded outer corner falling
    two ways - a quarter cone - or a rounded hollow at one corner; corners and hollows meet the
    slopes beside them edge to edge). A change marks every selected cell. The scene applies the
    marks where it reads the relief (`placeRelief`: `Relief.markedCell` over the cell's heights,
    its read heights kept as `gRead`; its depths `s` flat at the foot of `gRead`, so its drawing
    stays where it lay and a raised cell stands straight up - the relief's own points stand a level
    south a level up, which would lean a hand-raised block's walls back 45 degrees), with a wall record (`markCut`: the layout's face tile, block
    walls) on it and on any unmarked neighbour left standing over it, so steps close; a map with no
    relief of its own takes an empty one for its marks. No cache rebuild: they ride over the relief
    in every battle as the trees' marks do, saved in the game's tune file (Ctrl+S).
  - **Props:** clicking a prop turns the panel to its own settings (`Tune.PROP_DEFS` by its shape,
    each spec its group `prop_<name>`, registered by the scene: `Tune.useProps(Props.SPECS)`): a
    turned prop's radius, height, depth (its squash) and stand; a heap's radius, height and stand;
    a mound's rise. Each is a share of (or a shift from) the spec's own reading, so a game with no
    tune file draws as before; a prop's model is built again when they change (its cache key carries
    them). Its drawing is projected, so the 45 degree picture holds whatever they are: they shape it
    seen from elsewhere, and the proof's `flat` shows how much of the drawing stands on the model.
  - **The data:** `Tune.DEFS` names each group's settings with their defaults (the models' own
    constants, so a game with no tune file draws as before) and ranges. Ctrl+S writes
    `src/scene/games/<game>_tune.lua` (`Tune.source`: `groups` and `marks`, keyed `MAP:x:y` in the
    map's own cells; FireRed's serves LeafGreen). main.lua loads `tune.lua` and each game's file
    (`Tune.put`); `useFamily` hands the trees their game's settings (`Trees.useTune`), and the tree
    pass looks up each tree cell's mark (`c.treeMark`, passed to `Trees.emit`). The tune files
    ship; the workshop and its launcher don't (`.modkitignore`).
  - **Hooks:** `exports._workshop()` gives the workshop the tuning, the camera, the trees, the last
    scene (which keeps its `grid` and `where`), `rebuild`, `view(pose, w, h, k)` (the scene from any
    pose, settled, at k screen pixels a canvas pixel: `Scene._view`), the mod's path and the game.
    Picking hits the ground under the ray (lifted cells by their lift), and a tree by its crown
    card's outline on screen, the nearest first.
  - **Checking it unattended:** `WORKSHOP_SCRIPT=<file>` runs a script with the workshop's hooks
    instead of the interactive loop, and `WORKSHOP_TUNE_FILE` saves elsewhere.
- **Performance (FireRed, measured 2026-11-14 in the scratch engine, 1920x1080, desktop GPU):**
  `scene_battle.lua` with `SCENE_TIME=n` times n frames of the settled battle with vsync off (mean
  and worst). Viridian Forest (its trees: 120 crown quads and the lid each, stacked through the
  wood) 5.6 ms a frame, worst 9; Route 1 (the General tree: 84 quads) 7.7 / 12.5; Pallet Town 8.1;
  the rooms 5.3-5.9 (Oak's lab, the Game Corner, the Power Plant); Emerald's Route 101, Petalburg
  Woods and Route 119 7-8 / 11-17. The scene's build: its render stage 490 ms in Viridian Forest,
  600 on Route 1, 460 on Emerald's Route 112. The relief's background build: FireRed's whole build
  in 34-36 s, 57 slices over 50 ms (longest 175-240 ms) against Emerald's 95-117 (longest 430-460);
  `RELIEF_WATCH` finds no stretch between two ticks over 80 ms, and `RELIEF_SLOW=1` spreads the slow
  slices over every phase, one or two a town: the collector's pauses on the build's heap, not any
  one piece of work.
- **LeafGreen:** it draws FireRed's maps with its own palettes. All FireRed specs pass against LeafGreen's drawings, and placements match FireRed's. Its caves read the same as FireRed's (all 78, layout for layout), its 71 rooms check the same (`room_check.lua` with `POKEPORT_GAME=leafgreen`, room for room), and its three trees (the General, Viridian Forest's, Berry Forest's) are 0 wrong at 45 degrees; Oak's lab, the forests, the caves and the Power Plant checked in game.
- **Driver:** `tests/drivers/first_run.lua` (`FIRST_RUN_RESET`, which removes every game's flag,
  `FIRST_RUN_SCENE=overworld` with it for the build-only question, `FIRST_RUN_CLEAR`,
  `FIRST_RUN_ANSWERS`, `FIRST_RUN_ACTIONS`). A driver's frames skip `core.update`, so it ticks the
  prompt through `exports._promptTick`.

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
| `art` | `{x0, y0, x1, y1}`: the art's box over its whole animation (quad pixels). Battle Fit keeps it in the Pokémon's room (shrinking one too big for it); without it the frame is taken as the art, from `top` down |
| `height` | the real height in metres of the tag's art box (feet to the top of its animation). With it (and a `side`), the 3D world stands it at the world's scale (`worldSize`); the classic backgrounds draw it at its `scale` (shrunk only to fit its room). Check `features.speciesSize` |
| `flip` | `true`: the `texture`/`quad` frame is drawn mirrored about its `pivot` (a stand-in the mod drew mirrored; `lowPivot` is in the stand-in as drawn). Check `features.flip` |
| `shades` | a shader: the stand-in is in the Game Boy's four shades, made by this shader from the frame's colours. The `texture`/`quad` frame is drawn through it and then coloured as the stand-in is: in Gen 1 into a canvas a whole number of times the pass's size, then through the Renderer's blit (its SGB zones); in Gen 2 (a direct pass) 1:1 into a canvas, then drawn under the palette shader in force. Without it a tagged frame under a shader falls back to the stand-in. Check `features.shades` |
| `shadow` | `{ texture, quad?, w, dx, dy }`: a contact shadow the stand-in has baked in under the Pokémon, drawn first: `w` wide, its bottom middle at (`dx`, `dy`) from the `pivot`, all in the frame's pixels, so it takes the frame's final size and `flip`. Not under a part of the pic drawn on its own (a row-by-row move), nor through a shader mapped to the frame. Check `features.shadow` |

Also `untag(image)`, `tagOf(image)` (the spec an image was tagged with, or nil: a mod that
draws a tagged pic outside the battle, field and Pokédex passes can draw the full-resolution
texture itself), `isActive()`, `enabled(pass)`, `setEnabled(pass, on)`, `cap(pass)`,
`setCap(pass, n)`, `features` (`{ quadPivots = true, dex = true, battleFit = true, tagOf = true, flip = true, shades = true, uiMap = true, speciesSize = true, shadow = true }`),
`fitEnabled()`, `setFit(on)` (the old `"off"` / `"fit"` / `"tall"` still work), `fillEnabled()`, `setFill(on)`,
`sceneEnabled()` / `setScene(on)` (Battle Scene: OVERWORLD), `realSizes()` / `setRealSizes(on)` (Real
Sizes: `fit.worldSizes`), `sizeMode()` / `setSizeMode(m)` (3D Sizing's choice: `"off"`, `"minimal"`,
`"medium"`, `"accurate"`), `sceneZoom()` (the battle scene's zoom this
frame; 1 = none), `sceneDecks(layout)` (a layout's deck table, for an overworld view: see Battle
Scene) and `stats()` (`splits`, `composites`, `flattened`, `overCap`, `zoom`,
`zoomTarget`, `lift`, `extraLift`, `hiddenEnemyUI`, `hiddenOwnUI`, `backTop`, `shiftEnemy`, `shiftPlayer`, `dropPlayer`, `raisePlayer`, `fill` (the scene's scale over the Renderer's, 1 = none), `uiScale`, `uiTopDy`, `card`, `grow`, `inward`, `topY`, `uiK`,
`failed`), `uiMap()` (below). The export `version` is 2.

`uiMap()`: where this frame's UI canvas went when WoobleView placed it (Fill Screen, a card), or
nil when the Renderer blitted it itself (its `blitCanvas` arguments say where). It is for a mod
drawing over the UI at window resolution (WoobleDex's Stat Hints, from `render.hud`): valid from
the UI canvas's blit until the next frame begins (`hd.uiLive`: set by the engine wrap's blit when
WoobleView placed the UI canvas, cleared by its `beginFrame` wrap). It is the live `hd.uiMap`: read it, never write or keep it. UI canvas pixel
(x, y) lands at window (`x + x * sx`, `Y + y * sy`), `Y` = `topY` when `banded` and y < `split` (an
upright battle's top band, moved up), else `y`; clip to `box` (or `topBox` / `lowBox` by band),
each `{x, y, w, h}`. The Renderer may blit the UI canvas again in the same frame (a docked text
box apart): the first is the one placed, the rest are taken as done. Tags are weak: an image that is freed drops its tag. Keep the tagged
image itself a real low-res picture: it is what shows whenever a frame falls back.

## Tests

`luajit tests/hd_test.lua` (a fake `love.graphics`; no game needed). Every test file is listed by
exact path in `.modkitignore`. The drivers in `tests/drivers/` run in the game
(`POKEPORT_DRIVER`, each file's header says how) and screenshot what they check; for the Game
Boy games: `gen1_battle.lua` (with `GEN1_INTRO_SHOT`, `GEN1_COLORS` and `GEN1_FIT` on / off, `GEN1_MON` the lead), `gen2_battle.lua` (`GEN2_FIT` on / off, `GEN2_MON`, `GEN2_SLIDE_SHOTS` for the intro slide),
`field_gb.lua` (Field HD with Vivid Worlds: OG), `screens_gb.lua` (Red's whole screens) and
`dex_gb.lua` (the Pokédex and summary in each colour mode, HD on and off). Battle Scene:
`luajit tests/scene_test.lua` (camera, cells, stage search, vertices, trees, the building kernel,
specs and placement, look-alike cells, solids, component runs, fences, kits, signs, relief and its
last passes), `luajit tests/roles_test.lua` (the cell roles) and the drivers
`scene_battle.lua` (`SCENE_SPOTS`, `SCENE_FITS` for the settled battle with Battle Fit on and off, `SCENE_LOOK` for shots aimed elsewhere, each also saved as the
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

Keep [README.md](README.md) and the player guides in [docs/](docs) describing the mod as it is
now (players read them; the guides ship with the mod).
