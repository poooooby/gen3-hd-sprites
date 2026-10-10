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

## ⚙️ Options

Open **OPTIONS → MODS → Gen 3 HD Sprites**.

| Option | Choices | Default | What it does |
|---|---|---|---|
| **Battle HD** | On / Off | On | Battle Pokémon at full resolution. |
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

---

Licence: [MIT](LICENSE). Making a mod that uses it? See [DEVELOPMENT.md](DEVELOPMENT.md).
