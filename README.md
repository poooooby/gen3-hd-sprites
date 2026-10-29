<div align="center">

# WoobleView 🖥️

*Sharp Pokémon and battles that fit any screen, in FireRed, LeafGreen, Ruby, Sapphire and
Emerald.*

</div>

A display mod for [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp)'s Generation 3 games.
On its own, battles fill your screen in any shape, from a widescreen monitor to a phone held
upright. With a sprite mod that supports it, its Pokémon are drawn at your screen's full
resolution, and the camera pulls back so even the biggest ones fit.

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
  so the opponent never sinks behind your HP bar, while your own platform stays tucked under
  the text box like on the original, for a true sense of scale.
- 🐋 **Your Pokémon too:** A small Pokémon of yours stands a little behind its platform so most
  of it shows above the text box. A big one never stands taller than the biggest original back
  sprites, so its head keeps clear of the opponent's HP bar, and its whole animation stays on
  screen.
- ↔️ **Spreads out:** When the camera pulls back, the two Pokémon, their platforms and the
  trainers spread back out toward the sides from the first moment of the battle, and the
  attacks follow them. In trainer battles the camera is set for the Pokémon before they're sent
  out, so nothing jumps when they appear. Your trainer stays planted on the text box, just like the original.
- 🖥️ **Fills your screen:** With **Fill Screen**, the battle fills your screen in any shape,
  with no black bars. On a widescreen monitor or a phone held sideways it reaches from the top
  of the screen out to both sides. The battle's opening fills it too: the black curtain opens
  across the whole screen and the grass, sand or waves sweep across its full width, and the sky
  stretches up to the top of the screen.
- 📱 **Made for phones held upright:** The text box and menus stretch the full width, sharp and
  even, right above the touch controls. The battle grows into the space above them, with
  both Pokémon and both platforms always whole on screen. With a sprite mod, the two sides
  slide a little toward each other so they can be bigger, without overlapping, and your
  Pokémon may stand in front of the foe's platform. The
  foe's HP box moves up out of the way, to just above the battle. With no controls on screen,
  the battle sits centred, with sky above and ground below.
- 🧭 **The UI stays sharp:** The text box, menus and HP bars never shrink with the camera, and
  stay crisp.
- 🌄 **Depth:** The far background pulls back less than the platforms, like a real camera.
- 🎚️ **Smooth:** The camera eases out when a tall Pokémon arrives and drifts back in a moment
  after it leaves. It doesn't bob with a Pokémon's animation.

## ⚙️ Options

Open **OPTIONS → MODS → WoobleView**.

| Option | Choices | Default | What it does |
|---|---|---|---|
| **Battle HD** | On / Off | On | Battle Pokémon at full resolution. |
| **Battle Fit** | On / Off | On | Pull the battle camera back so tall Pokémon fit. Needs Battle HD. |
| **Fill Screen** | On / Off | On | The battle fills your screen in any shape. Wide: the text box and HP bars along the bottom. Upright phone: a full-width text box above the controls, the foe's HP box above the battle. Off: the usual framed battle screen. Needs Battle Fit. |
| **Pokedex HD** | On / Off | On | Pokédex Pokémon at full resolution, fitted to the Pokédex. |
| **Field HD** | On / Off | On | Overworld Pokémon at full resolution. Turn it off on a slow device. |

## 💾 Installation

1. Download the latest release from the
   [Releases](https://github.com/poooooby/gen3-hd-sprites/releases) page.
2. Import it with the Gen1Recomp Mod Manager, or drop it in your mods folder.
3. Enable it. Add a sprite mod that supports it for full-resolution Pokémon.

## 🔗 Works With

- [WoobleSpritePack](https://github.com/poooooby/g9-battle-sprites-gen3): sharp battle
  and Pokédex sprites, each Pokémon sized to match its original sprite.
- [Wilds of Hoenn](https://github.com/poooooby/wilds-of-hoenn): wild Pokémon and your partner at
  their true relative sizes, with its **Species Sizes** and **Overworld Size** options.

## 📌 Good to Know

- The camera only pulls back for Pokémon drawn by a sprite mod that supports this one. With
  the game's own sprites the battle keeps its original framing, and Fill Screen still fits it
  to your screen.
- The camera pulls back to 40% at most, enough for the very biggest (Lugia, Koraidon).
- A full-screen menu opened in a battle (a summary or a care screen) shows framed, like the
  original, while Fill Screen is on.
- If your device can't draw battles this way, the mod steps aside for that session and the
  game draws everything as usual.

---

Licence: [MIT](LICENSE). Making a mod that uses it? See [DEVELOPMENT.md](DEVELOPMENT.md).
