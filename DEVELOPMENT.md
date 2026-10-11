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
- Either target is clamped to `[zMin, 1]`. `zMin` is 0.5 for Fit Sprites and 0.4 for Fit Tall
  Too. The wallpaper does not rise: its rows below y = 112 are hidden by the text box on the cart, so its bottom edge stays on the text box line.
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

  Levels are relaxed in order: own side first, then headroom. Without headroom, at most
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
    `side, trainer = true`. The player's back pic also gets `pinBottom = 112`: its frame's
    bottom is kept on the text box's line however the camera rises, so its cut stays hidden.
  - **The engine's coordinates move too,** before each battle frame:
    - `AnimCoords.SINGLES`, which move animations aim at;
    - `Anim.ENEMY_MON` / `PLAYER_MON` (ball targets, the catch, a switch);
    - `Pokedude.sendOutOrigin`, where the player's ball leaves the trainer's hand.
  - **Double-shift guard:** a Pokémon drawn inside `Anim.drawParticles` (an afterimage, a
    move's copy of it) is flagged `inAnim` and not shifted again.
  - **Not fitted:** trainers are left out of the fit itself.
- The zoom snaps to the target at a battle's first frame and eases out about 20% per frame.
  The extra rise eases the same way.
- It eases back in about 5% per frame, but only after the target has stayed larger for 45
  frames.
- A frame with no UI seam (the post-catch Pokédex scene) is not zoomed.

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
`fitEnabled()`, `setFit("off" | "fit" | "tall")`, `sceneZoom()` (the battle scene's zoom this
frame; 1 = none) and `stats()` (`splits`, `composites`, `flattened`, `overCap`, `zoom`,
`zoomTarget`, `lift`, `extraLift`, `hiddenEnemyUI`, `hiddenOwnUI`, `backTop`, `shiftEnemy`, `shiftPlayer`). The export `version` is 2. Tags are weak: an image that is freed drops its tag. Keep the tagged
image itself a real low-res picture: it is what shows whenever a frame falls back.

## Tests

`luajit tests/hd_test.lua` (a fake `love.graphics`; no game needed). Every test file is listed by
exact path in `.modkitignore`.

Keep [README.md](README.md) describing the mod as it is now (players read it).
