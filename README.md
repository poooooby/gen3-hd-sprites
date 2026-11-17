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

- 📏 **True-to-size battles:** Both Pokémon are drawn to one scale by their real heights. The
  bigger one fills all the room it has, never hidden under the HP boxes or the text box, and the
  other stands at its true size beside it: a Bulbasaur comes up to about a third of a Meganium.
  Your own Pokémon is a touch bigger than the same one on the far side, being nearer to you, and
  two giants both fill the screen. The opponent slides in at its normal size and settles to its
  true size when your Pokémon comes out.
- 📐 **Nothing cut off:** If a Pokémon still doesn't fit, the camera pulls back just enough to
  show it in full, and eases back in when it leaves.
- 🖥️ **Fills your screen:** With **Fill Screen**, battles, menus, the Pokédex, the summary, the
  bag and the intro fill any screen shape without black bars. The text box and HP bars stay
  sharp. In Gen 3 the enemy's HP box moves up to the top of the screen, giving your Pokémon
  more room. In Gold, Silver and Crystal both sides slide in from the screen's edges.
- 📱 **Phone-friendly:** On a phone held upright, the text box runs full width above the touch
  controls and the battle grows into the space above it.

### Battle Scene 🏞️

- 🗺️ **Battle where you stand:** With **Battle Scene** on **Overworld**, battles take place in
  the world around you, with its 3D land, buildings and trees.
- 🏠 **Towns and rooms in 3D:** Hoenn's and Kanto's towns, gyms, Pokémon Centers, Marts and
  many other buildings and rooms stand in 3D, rebuilt from the game's own art.
- 🎯 **A fair place to fight:** Each battle is set on the nearest spot where both Pokémon stand
  on level, open ground, with nothing between them and nothing blocking the view.
- ☀️ **Light and weather:** Sunlight, shadows, rain, sand, ash and fog fill the scene.
- 🎥 **Cinematic entrance:** The camera swoops down from the overworld into the battle.

## ⚙️ Options

Open **OPTIONS → MODS → WoobleView**. Battle Scene and the four options after it only show in
FireRed, LeafGreen, Ruby, Sapphire and Emerald.

| Option | Choices | Default | What it does |
|---|---|---|---|
| **Battle HD** | On / Off | On | Battle Pokémon at full resolution. |
| **Battle Fit** | On / Off | On | Both Pokémon drawn to one scale by their real heights: the bigger fills its space, the other stands at its true size beside it, yours a touch bigger for being nearer; the camera pulls back if anything still doesn't fit. Off: the sprite mod's own sizes. Needs Battle HD. |
| **Fill Screen** | On / Off | On | Battles and full screens fill your screen in any shape. Needs Battle Fit. |
| **Battle Scene** | Classic / Overworld | Classic | Overworld: battles set in the 3D world around you (Gen 3 games). Needs Battle Fit. |
| **Build 3D Cache** | Press A | – | Builds the 3D world now (a minute or two) instead of a little at a time while you play. |
| **Clear 3D Cache** | Press A | – | Deletes the saved 3D world. It's rebuilt when needed. |
| **Scene Blur** | On / Off | On | A soft miniature-style blur on the far and near ground. |
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
- 🔴 **Red, Blue, Yellow, Gold, Silver and Crystal:** Fill Screen, sharp battle and Pokédex
  sprites, and sharp overworld Pokémon from supported mods. There's no Battle Scene in these games.
- If your device can't draw battles this way, the mod steps aside and the game draws as usual.

## 🪪 Credits

- **Battle Scene** is adapted from the 3D battles of
  [Emerald 3DS](https://github.com/ZallaxDev/emerald-3ds) by Zallax and contributors: its camera,
  entrance, battle placement, trees, buildings, rooms, land shapes, lighting and weather.
- **Kanto's land** in FireRed and LeafGreen comes from
  [Pokémon FireRed 3DS](https://github.com/NachoGonzalez2001/Pokemon-FireRed-3DS) by
  NachoGonzalez2001, and a few of WoobleView's Kanto buildings are modelled after its own.

## 💡 Inspirations

- [Pokémon FireRed 3DS](https://github.com/NachoGonzalez2001/Pokemon-FireRed-3DS) by
  NachoGonzalez2001 first showed Kanto standing in 3D.

---

Licence: [CC BY-NC-SA 4.0](LICENSE) (versions up to 0.6.0: MIT). Making a mod that uses it? See
[DEVELOPMENT.md](DEVELOPMENT.md).
