<div align="center">

# Gen 3 HD Sprites 🖥️

*Crisp Pokémon at any size. Battle and overworld Pokémon drawn at your screen's full
resolution in FireRed, LeafGreen, Ruby, Sapphire and Emerald.*

</div>

A library mod for [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp)'s Generation 3 games.
On its own it changes nothing; sprite mods that support it look sharper with it.

## ✨ Features

### Core Mechanics

- 🔍 **Every pixel kept, at any size:** The game scales its screen up by whole numbers, so a
  Pokémon drawn at 62% or 75% normally comes out lumpy. With this mod it's drawn at your
  window's resolution and keeps every pixel of its art.
- 🚶 **Smooth movement:** Overworld Pokémon glide between pixels instead of stepping on the
  game's grid.
- 🧱 **Nothing out of place:** The battle HUD, text box and menus stay on top. On the field,
  roofs and tree tops still cover what walks beneath them, and Pokémon still sort in front of or
  behind the player and NPCs.
- 🛟 **Never breaks a frame:** If a frame can't be drawn this way (a weather effect, a battle
  transition), it's drawn the usual way instead. Nothing goes missing.

### Battle Fit 🎥

- 📐 **Big Pokémon fit on screen:** When a Pokémon is too tall for the battle screen (a Lugia, a
  Koraidon), the camera pulls back just enough to show all of it. Its platform, your Pokémon and
  the move effects shrink with it, so the scene keeps its perspective. The camera also rises,
  so the opponent never sinks behind your HP bar, and your own platform shows whole instead of
  cut off at the text box.
- 🐋 **Your Pokémon too:** A big Pokémon of yours stays in view. It never stands taller than the
  biggest original back sprites, so its head keeps clear of the opponent's HP bar. At least 70%
  of it stays clear of your HP bar and the text box, and its whole animation stays on screen.
- ↔️ **Fills the screen:** When the camera pulls back, the two Pokémon, their platforms and the
  trainers spread back out toward the sides from the first moment of the battle, and the
  attacks follow them. In trainer battles the camera is set for the Pokémon before they're sent
  out, so nothing jumps when they appear. Your trainer stays planted on the text box, just like the original.
- 🧭 **The UI stays put:** The text box, menus and HP bars never move or shrink, and stay crisp.
- 🌄 **Depth:** The far background pulls back less than the platforms, like a real camera.
- 🎚️ **Smooth:** The camera eases out when a tall Pokémon arrives and drifts back in a moment
  after it leaves. It doesn't bob with a Pokémon's animation.

## ⚙️ Options

Open **OPTIONS → MODS → Gen 3 HD Sprites**.

| Option | Choices | Default | What it does |
|---|---|---|---|
| **Battle HD** | On / Off | On | Battle Pokémon at full resolution. |
| **Battle Fit** | Off / Fit Sprites / Fit Tall Too | Fit Sprites | Pull the battle camera back so tall Pokémon fit. **Fit Tall Too** pulls back further for the very biggest. Needs Battle HD. |
| **Pokedex HD** | On / Off | On | Pokédex Pokémon at full resolution, fitted to the Pokédex. |
| **Field HD** | On / Off | On | Overworld Pokémon at full resolution. Turn it off on a slow device. |

## 💾 Installation

1. Download the latest release from the
   [Releases](https://github.com/poooooby/gen3-hd-sprites/releases) page.
2. Import it with the Gen1Recomp Mod Manager, or drop it in your mods folder.
3. Enable it alongside a mod that uses it.

## 🔗 Works With

- [G9 Battle Sprites (Gen 3)](https://github.com/poooooby/g9-battle-sprites-gen3): sharp battle
  and Pokédex sprites, each Pokémon sized to match its original sprite.
- [Wilds of Hoenn](https://github.com/poooooby/wilds-of-hoenn): wild Pokémon and your partner at
  their true relative sizes, with its **Species Sizes** and **Overworld Size** options.

## 📌 Good to Know

- Battle Fit only reacts to Pokémon drawn by a sprite mod that uses this one. With the game's
  own sprites, battles look exactly as they always have.
- **Fit Sprites** pulls back to 50% at most; **Fit Tall Too** to 40%.

---

Licence: [MIT](LICENSE). Making a mod that uses it? See [DEVELOPMENT.md](DEVELOPMENT.md).
