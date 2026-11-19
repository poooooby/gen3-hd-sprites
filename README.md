<div align="center">

# WoobleView 🖥️

*Sharp Pokémon, battles that fit any screen, and battles set in a 3D world.*

</div>

A display mod for [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp). It's built for FireRed,
LeafGreen, Ruby, Sapphire and Emerald, and does part of the job in Red, Blue, Yellow, Gold, Silver
and Crystal.

## ✨ Features

### Core Mechanics

- 🔍 **Sharp at any size:** With a sprite mod that supports it, Pokémon are drawn at your
  screen's full resolution instead of the game's blocky scaling.
- 🚶 **Smooth movement:** Overworld Pokémon glide smoothly instead of stepping pixel by pixel.
- 🛟 **Safe:** Menus and text always stay on top. Any frame that can't be drawn this way is drawn
  the normal way, so nothing ever goes missing.

### Battle Fit 🎥

- 📏 **Your sprites, as drawn:** Every Pokémon is drawn at the size your sprite mod gives it,
  in single and double battles. One too big for its space is shrunk just enough to fit, so it
  is never cut off by the top or the sides of the screen.
- 📐 **Nothing cut off:** If a Pokémon still doesn't fit (a head flung high in its animation),
  the camera pulls back just enough to show it in full, and eases back in when it leaves.
- 🖥️ **Fills your screen:** With **Fill Screen**, battles, menus, the Pokédex, the summary, the
  bag and the intro fill any screen shape without black bars. The text box and HP bars stay
  sharp. In Gen 3's classic battles and double battles the opponents' HP boxes move up to the
  top of the screen, giving the Pokémon more room. Gold, Silver and Crystal keep the game's own framed screen.
- 📱 **Phone-friendly:** On a phone held upright, the text box runs full width above the touch
  controls, the battle grows into the space above it, and in classic battles the opponent's HP
  box stays put just inside the battle's top edge, whatever the Pokémon do.

### Battle Text Box 💬

- ✨ **A sharp, modern text box:** In Ruby, Sapphire and Emerald the battle's text box and its
  FIGHT / BAG and move menus are redrawn as one smooth bar across the bottom of the screen,
  in the game's own colours: the red-framed teal message box and the white menus, joined
  side by side.
- 🖥️ **Fills the bottom:** The bar spans the whole width of any screen, the menu on the right,
  your text on the left.
- 📏 **More battle on screen:** The bar is a quarter shorter than the game's box, so more of the
  battle shows above it.
- 🎮 **Plays nicely with KantoGear:** When KantoGear's GEAR screens take over the battle's
  menus, the bar and the battle's text step aside.

### Battle Scene 🏞️

- 🗺️ **Battle where you stand:** With **Battle Scene** on **Overworld**, battles take place in
  the world around you, with its 3D land, buildings and trees.
- 🏠 **Towns and rooms in 3D:** Hoenn's and Kanto's towns, gyms, Pokémon Centers, Marts and
  many other buildings and rooms stand in 3D, rebuilt from the game's own art.
- 🎯 **A fair place to fight:** Each battle is set on the nearest spot where both Pokémon stand
  on level, open ground, with nothing between them and nothing blocking the view.
- 📏 **True to size:** Every Pokémon stands on the ground at its real size, a map tile being
  about a metre, and nearer the camera looks bigger. Big Pokémon are gently scaled down the
  bigger they are, up to about 5 m tall (a little less for an opponent), so a Groudon still
  stands taller than a Blaziken, and a Wailord towers over a Pikachu without leaving the
  screen. Very wide ones are kept to 6 m across, while a tall, thin Steelix keeps its height.
  A small Pokémon beside a giant is drawn the same on an upright phone as on a wide screen.
- 🎬 **A camera that follows the battle:** A single battle opens at the camera's usual view, so
  the trainer is shown at their proper size. As the opponent's Pokémon comes out, the camera
  zooms out to fit a giant, then adjusts again when yours comes out, coming in close when every
  Pokémon on the field is small; one too big even for the widest view is shrunk just enough to
  fit. When a Pokémon faints the camera holds still until the next one is out, and it returns
  to its usual view for the trainer's last words. A wide Pokémon steps back toward its own side
  of the screen, partly out of view, rather than reaching across the middle and covering its
  opponent, always with most of it in view.
- 👥 **Double battles:** The four are drawn at your sprite pack's own sizes, as on the game's
  own screen, which shows their differences best when four share it, and the camera pulls back
  only as far as keeps every one of them in view. Prefer your sprite pack's sizes everywhere?
  Turn **3D Sizing** off.
- 🏷️ **HP box over their heads:** The opponent's HP box (both of them in a double battle) sits
  just above the tallest Pokémon's head, and the camera leaves room for it. It only moves when a new Pokémon
  comes out, so it never jumps about when one faints or the battle ends. The tiniest are never drawn too small to see. Indoors, the biggest
  are held to about a room's height, so a gym or a ship's cabin stays in view, and anything past
  the walls fades into the room's own colours instead of black. Battles inside the Abandoned
  Ship are fought out on its deck.
- ☀️ **Light and weather:** Sunlight, shadows, rain, sand, ash and fog fill the scene.
- 🌙 **Time of day:** Outdoor battles are lit by the clock: a warm morning, the plain day, an
  orange evening and a blue, moonlit night, easing from one to the next, under a sky that deepens
  overhead with the hour and glows warm at sunset. Ruby, Sapphire and
  Emerald follow the game's clock, FireRed and LeafGreen your device's. With WoobleDex, battles
  follow its Clock Source and its Day & Night setting, so they match the overworld around you.
- 🎥 **Cinematic entrance:** The camera swoops down from the overworld into the battle.

## ⚙️ Options

Pick **WOOBLEVIEW** on the game's own OPTION screen (or open **OPTIONS → MODS → WoobleView**);
B there takes you straight back. Battle Textbox, Battle Scene and the five options after
it only show in FireRed, LeafGreen, Ruby, Sapphire and Emerald.

| Option | Choices | Default | What it does |
|---|---|---|---|
| **Battle HD** | On / Off | On | Battle Pokémon at full resolution. |
| **Battle Fit** | On / Off | On | Pokémon at the sprite mod's own size, one too big for its space shrunk just enough to fit; the camera pulls back if anything still doesn't fit. Off: the sprite mod's own sizes. Needs Battle HD. |
| **Fill Screen** | On / Off | On | Battles and full screens fill your screen in any shape. Needs Battle Fit. Not in Gold, Silver and Crystal. |
| **Battle Textbox** | On / Off | On | Ruby, Sapphire and Emerald: the battle's text box and menus redrawn as one sharp bar across the bottom, a quarter shorter. Off: the game's own boxes. Needs Battle HD. |
| **Battle Scene** | Classic / Overworld | Classic | Overworld: battles set in the 3D world around you (Gen 3 games). Needs Battle Fit. |
| **3D Sizing** | On / Off | On | With Battle Scene on Overworld: the Pokémon at their real size in the world, the biggest gently scaled down to about 5 m tall and 6 m wide, the camera zooming out for giants and in for small ones, and the opponent's HP box over their heads. Off: drawn and framed as in Classic battles, at your sprite pack's own sizes. |
| **Build 3D Cache** | Press A | – | Builds the 3D world now (a minute or two) instead of a little at a time while you play. |
| **Clear 3D Cache** | Press A | – | Deletes the saved 3D world. It's rebuilt when needed. |
| **Scene Blur** | On / Off | On | A soft miniature-style blur on the far and near ground. |
| **Time of Day** | On / Off | On | Outdoor battle scenes lit by the time of day (morning, day, evening, night), by the game's clock or WoobleDex's. Off: always day. |
| **Scene Cache** | On / Off | On | Keeps built towns and rooms on disk so battles load straight away. |
| **Field HD** | On / Off | On | Overworld Pokémon at full resolution. Turn off on a slow device. |
| **Pokedex & Summary HD** | On / Off | On | Pokédex and summary Pokémon at full resolution. |

## 💾 Installation

1. Download the latest release from the
   [Releases](https://github.com/poooooby/gen3-hd-sprites/releases) page.
2. Import it with the Gen1Recomp Mod Manager, or drop it in your mods folder.
3. Enable it. Add a supported sprite mod for full-resolution Pokémon.

## 🔗 Works With

- [WoobleSpritePack](https://github.com/poooooby/g9-battle-sprites-gen3): sharp battle and
  Pokédex sprites for every Pokémon.
- [Vivid Worlds](https://github.com/poooooby/wilds-of-hoenn) and
  [Vivid Worlds: OG](https://github.com/poooooby/vivid-worlds-og): overworld Pokémon drawn sharp
  and at their true sizes.

## 📌 Good to Know

- 👋 **First run:** The first time you play each Gen 3 game, WoobleView asks whether you want 3D
  battles and whether to build that game's 3D world now or while you play. You can change this
  any time in the options.
- 🔄 **Updates:** When an update improves the 3D world, it asks once whether to rebuild it now or
  while you play.
- **Battle Scene** works in FireRed, LeafGreen, Ruby, Sapphire and Emerald. Places without a 3D
  model are drawn flat. A battle with no overworld around it, or no open ground nearby, keeps the
  game's own background.
- True-to-size battles need Pokémon from a supported sprite mod. With the game's own
  sprites, Fill Screen still fits the battle to your screen.
- 🔴 **Red, Blue, Yellow, Gold, Silver and Crystal:** sharp battle and Pokédex sprites, and sharp
  overworld Pokémon from supported mods. Fill Screen in Red, Blue and Yellow; Gold, Silver and
  Crystal keep the game's own framed battle screen, so their battles look as other mods (Facets'
  battle scenes) draw them. There's no Battle Scene in these games.
- If a frame ever can't be drawn this way, that moment is drawn the game's usual way (sprites at
  their normal size) and the mod tries again a couple of seconds later. Only if it keeps
  happening does it step aside until you restart the game.

## 🪪 Credits

- **Battle Scene** is adapted from the 3D battles of
  [Emerald 3DS](https://github.com/ZallaxDev/emerald-3ds) by Zallax and contributors: its camera,
  entrance, battle placement, trees, buildings, rooms, land shapes, lighting, day-night cycle and
  weather. The
  battle text box's modern look follows its HD text box.
- **Kanto's land** in FireRed and LeafGreen comes from
  [Pokémon FireRed 3DS](https://github.com/NachoGonzalez2001/Pokemon-FireRed-3DS) by
  NachoGonzalez2001, and a few of WoobleView's Kanto buildings are modelled after its own.

## 💡 Inspirations

- [Pokémon FireRed 3DS](https://github.com/NachoGonzalez2001/Pokemon-FireRed-3DS) by
  NachoGonzalez2001 first showed Kanto standing in 3D.

---

Licence: [CC BY-NC-SA 4.0](LICENSE) (versions up to 0.6.0: MIT). Making a mod that uses it? See
[DEVELOPMENT.md](DEVELOPMENT.md).
