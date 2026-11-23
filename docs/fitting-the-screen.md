# 🎥 Fitting battles to your screen

[← Back to the README](../README.md)

WoobleView draws battles for the screen you actually have, whether it's a wide monitor, a tablet
or a phone held upright, instead of a small box in the middle of it.

## Your sprites, as drawn

With **Battle Fit** on, every Pokémon is drawn at the size your sprite mod gives it, in single
and double battles. If one is too big for its space, it's shrunk just enough to fit, so it's
never cut off by the top or the sides of the screen.

Sometimes a Pokémon still won't fit, say when a head is flung high in its animation. Then the
camera pulls back just enough to show it in full, and eases back in once it's done.

## Moves in full

When the camera pulls back, a move's effects, backgrounds and waves reach the edges of your
screen, instead of stopping in a box the size of the original screen. With
[WoobleDex](https://github.com/poooooby/national_dex_gen3), its move animations play in full too,
their backgrounds, waves and mists filling your whole screen.

## Filling the screen

With **Fill Screen** on, battles, menus, the Pokédex, the summary, the bag and the intro fill any
screen shape without black bars, while the text box and HP bars stay sharp.

In Gen 3's classic battles and double battles, the opponents' HP boxes move up to the top of the
screen, which gives the Pokémon more room. In a double battle they leave room above for
WoobleDex's stat chips beside them. Gold, Silver and Crystal keep the game's own framed
screen.

With [OmniUI](https://github.com/1Jamie/omni_ui)'s modern UI on, the battles, menus and other
screens it redraws are left to it: there WoobleView doesn't fit, fill or move anything, and 3D
battles show the classic battle. Turn OmniUI's MODERN HIGH-RES UI off and WoobleView takes them
back.

When KantoGear's GEAR screens take the battle's menus to their own screen, nothing is left at
the bottom of the battle, so your Pokémon's HP box moves down into that space to sit level
with your Pokémon's feet, upright or sideways, and always stays on the screen.

## On a phone 📱

Held upright, the text box runs full width above the touch controls and the battle grows into
the space above it. In classic battles the opponent's HP box stays put just inside the battle's
top edge, whatever the Pokémon are doing.

## A modern battle text box 💬

In Ruby, Sapphire, Emerald, FireRed and LeafGreen, **Battle Textbox** redraws the battle's text
box and its FIGHT / BAG and move menus as one smooth bar across the bottom of the screen, in the
game's own colours, joined side by side: in Hoenn the red-framed teal message box and white
menus, in Kanto the gold-framed blue message box and white menus with their violet frames.

- The bar spans the whole width of any screen, with your text on the left and the menu on the
  right.
- It's a quarter shorter than the game's own box, so more of the battle shows above it.
- The same bar carries the words after a catch (the Pokédex page and the nickname question),
  when a Pokémon evolves and when an egg hatches.
- When KantoGear's GEAR screens take over the battle's menus, the
  bar and the battle's text step aside.
