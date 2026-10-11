# Gen 3 HD Sprites: developer guide

For mod authors and contributors. Players only need the [README](README.md).

## How it works

Gen 3 draws a battle into a 240×160 canvas and the field into a world canvas, then scales them up
by a whole number, so a sprite shrunk or moved by part of a pixel is resampled on that grid. This
mod lifts tagged sprites off it.

A "pass" is the drawing of one canvas: the battle (from `Battle.draw` to the frame's end), a
Pokédex screen (from its `Pokedex.draw`; inside a battle the battle pass covers it) or the field
(`Renderer:beginWorldPass` … `endWorldPass`). While a pass runs, a draw of a tagged image is
recorded instead of drawn, and everything drawn after it goes to a fresh transparent layer. When
the Renderer blits that canvas to the window (`Renderer:blitCanvas`), the blit becomes: the
canvas, each recorded sprite at window resolution, the next layer, and so on. The game's draw
order is kept exactly: the battle HUD, text box, menus and fades stay on top; in the field, roofs
and tree tops still cover what walks under them, and the player and NPCs still sort against
tagged Pokémon.

When a frame can't be composited that way it is drawn the usual low-res way, so nothing is ever
lost: a canvas swapped out mid-pass (Ruby/Sapphire/Emerald weather that reads the field), tilt
mode, a battle transition, or more tagged draws in one frame than the cap (8 in battle and the
Pokédex, 12 in the field; `cap(pass)` / `setCap(pass, n)`). Tagged draws with nothing drawn
between them share one layer. A layer is one window-sized canvas, so a high cap costs memory
only in scenes that use it.

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
  on it goes to `hd.band`, which draws it at the scene's zoom, repeated across the whole view
  and transparent above and below, so the zoomed-out scene shows no ends. It zooms about the
  text box's line but does not rise with the camera, so its bottom stays on that line, where
  the cart puts it.
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
- A frame with no UI seam (the post-catch Pokédex scene) is neither zoomed nor filled.

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
      art (`fit.artTop`, from `fitStep`).
    - **The straddle guard:** a visible UI draw that crosses the split but does not cover the
      whole canvas (the level-up window, the intro's closing wipe) sets `cur.uiStraddle`. That
      frame's UI is drawn in one piece.
  - **The scene** grows by `fit.grow` about the line into the space above, up to the top, its
    sides cropped. It grows only as far as both sides' art (`fit.span`: each side's frame
    across, zoomed, shifted) stays `cropMargin` clear of the edges. It is centred and moved
    sideways only as far as that needs. `grow` eases like the zoom.
  - **The sides slide in** when the width stops it short of the top: `fitStep` gets the art
    width the growth needs (`fit.wantW`) and moves the enemy left and the player right
    (`shift.enemy` / `shift.player`, so attacks follow).
    - A back whose body's top is below the enemy's feet (`feetY`) may slide until the
      centres line up.
    - One level with the enemy may stand in front of its platform, over up to `overlapFoe`
      (30%) of the enemy's frame.
    - The player's share stops at its own HP box's left edge; the enemy takes the rest.
  - **`fit.topY`,** the canvas y of the area's top in scene pixels (negative with sky above),
    is the highest art may rise, in `fitZoom` and the solver. So a tall foe rises into the
    sky instead of the camera pulling back.
  - **No controls below** (`view.bottom` nil): the whole block is raised by `fit.raise`,
    settling over a few frames, until the sky over the HP box equals the ground under the text
    box.
- The wallpaper, ground band and intro grass cover the view's full width and height either way.
- **The fit sees a smaller UI.** Over the bigger scene the UI covers less of it, so its rects,
  `feetMax` and `backTopMin` are shrunk by `fit.uiK = 1/f` about the focus before the search.
  That is why a filled widescreen battle pulls back less.
- **Whole-scene layers** (a move's background, a flash), and UI draws over the whole canvas (a
  fade), get a layer of their own, cover-scaled to the view.
- **Sitting out:** an opaque draw over the whole 240×160 canvas after the UI seam (a summary or
  care screen opened in the battle, a fade at full black) sets `cur.uiCovers`, and that frame is
  composited framed, as without fill. A half-faded cover keeps the fill, so a fade doesn't jump.
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

Also `untag(image)`, `isActive()`, `enabled(pass)`, `setEnabled(pass, on)`, `cap(pass)`,
`setCap(pass, n)`, `features` (`{ quadPivots = true, dex = true, battleFit = true }`),
`fitEnabled()`, `setFit(on)` (the old `"off"` / `"fit"` / `"tall"` still work), `fillEnabled()`, `setFill(on)`, `sceneZoom()` (the battle scene's zoom this
frame; 1 = none) and `stats()` (`splits`, `composites`, `flattened`, `overCap`, `zoom`,
`zoomTarget`, `lift`, `extraLift`, `hiddenEnemyUI`, `hiddenOwnUI`, `backTop`, `shiftEnemy`, `shiftPlayer`, `dropPlayer`, `raisePlayer`, `fill` (the scene's scale over the Renderer's, 1 = none), `uiScale`, `uiTopDy`, `grow`, `inward`, `topY`, `uiK`,
`failed`). The export `version` is 2. Tags are weak: an image that is freed drops its tag. Keep the tagged
image itself a real low-res picture: it is what shows whenever a frame falls back.

## Tests

`luajit tests/hd_test.lua` (a fake `love.graphics`; no game needed). Every test file is listed by
exact path in `.modkitignore`.

Keep [README.md](README.md) describing the mod as it is now (players read it).
