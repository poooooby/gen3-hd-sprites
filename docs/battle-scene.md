# 🏞️ 3D battles

[← Back to the README](../README.md)

With **Battle Scene** set to **Overworld**, your battles take place in the world around you, with
its 3D land, buildings and trees, instead of on the game's flat backdrop. This works in FireRed,
LeafGreen, Ruby, Sapphire and Emerald.

## Getting started

The first time you play each Gen 3 game, WoobleView asks whether you'd like 3D battles and
whether to build that game's 3D world now or a little at a time while you play. Building it all
at once takes a minute or two. You can also do it later with **Build 3D Cache**, or start over
with **Clear 3D Cache**. When an update improves the 3D world, WoobleView asks once whether to
rebuild it now or while you play.

With **Scene Cache** on, built towns and rooms are kept so battles load straight away.

## Where battles happen 🗺️

- **Where you stand:** Each battle is set on the nearest spot where both Pokémon stand on level,
  open ground, with nothing between them and nothing blocking the view.
- **Towns and rooms:** Hoenn's and Kanto's towns, gyms, Pokémon Centers, Marts and many other
  buildings and rooms stand in 3D, rebuilt from the game's own art. Places without a 3D model
  are drawn flat.
- **Indoors:** Anything past the walls fades into the room's own colours instead of black.
  Battles inside the Abandoned Ship are fought out on its deck.
- **No world around you:** A battle with no overworld around it, or no open ground nearby, keeps
  the game's own background.

## True to size 📏

Every Pokémon stands on the ground at its real size, with a map tile being about a metre, and
nearer the camera looks bigger. How true to life those sizes are is up to you, with **3D Sizing**:

| Choice | What you see |
|---|---|
| **Medium** (default) | Real sizes, with giants kept within reach and small Pokémon easy to see. Big Pokémon are gently scaled down the bigger they are, up to about 5 m tall (a little less for an opponent), so a Groudon still stands taller than a Blaziken and a Wailord towers over a Pikachu without leaving the screen. Very wide ones are kept to 6 m across, while a tall, thin Steelix keeps its height. The tiniest are raised so they're easy to see, and a long, low one like Zigzagoon a little more. |
| **Minimal** | Like Medium, with everyone drawn a little closer to the middle: small Pokémon a touch bigger, big ones a touch smaller. A Pikachu facing a Wailord is about 0.7 m against 3 m. |
| **Accurate** | Every Pokémon at its real measured height, so a Wailord dwarfs a Pikachu at over 6 m. They're scaled down only to fit the screen or the room. On a phone held upright, a giant can fill most of the view. |
| **Off** | Drawn and framed as in Classic battles, at your sprite pack's own sizes, shrunk only if too big. |

Indoors, the biggest are held to about a room's height, so a gym or a ship's cabin stays in
view. A small Pokémon beside a giant is drawn the same on an upright phone as on a wide screen.

**Double battles** 👥: the four Pokémon are drawn at your sprite pack's own sizes, as on the
game's own screen, which shows their differences best when four share it. The camera pulls back
only as far as it needs to keep every one of them in view.

## The camera 🎬

- **Entrance:** The camera swoops down from the overworld into the battle.
- **Following the battle:** A single battle opens at the camera's usual view, so the trainer is
  shown at their proper size. As the opponent's Pokémon comes out, the camera zooms out to fit a
  giant, then adjusts again when yours comes out. It comes in close when every Pokémon on the
  field is small, and a little closer for a small opponent. One too big even for the widest view
  is shrunk just enough to fit.
- **Between Pokémon:** When a Pokémon faints, the camera holds still until the next one is out.
  It returns to its usual view for the trainer's last words.
- **Wide Pokémon:** A wide Pokémon steps back toward its own side of the screen, partly out of
  view, rather than reaching across the middle and covering its opponent. Most of it always
  stays in view.

## HP boxes 🏷️

The opponent's HP box (both of them in a double battle) sits just above the tallest Pokémon's
head, and the camera leaves room for it. It only moves when a new Pokémon comes out, so it never
jumps about when one faints or the battle ends.

## Moves 🎯

A move lands on the middle of the Pokémon it hits, however small or big, and its effects grow
with a giant: a Hyper Beam widens as it reaches a Wailord. Move effects fill your whole screen,
however far the camera pulls back.

## Light, weather and time ☀️🌙

- **Weather:** Sunlight, shadows, rain, sand, ash and fog fill the scene.
- **Time of day:** With **Time of Day** on, outdoor battles are lit by the clock: a warm morning,
  the plain day, an orange evening and a blue, moonlit night, easing from one to the next, under
  a sky that deepens overhead with the hour and glows warm at sunset.
- **Which clock:** Ruby, Sapphire and Emerald follow the game's clock, FireRed and LeafGreen your
  device's. With [WoobleDex](https://github.com/poooooby/national_dex_gen3), battles follow its
  Clock Source and its Day & Night setting, so they match the overworld around you.
- **Scene Blur:** A soft, miniature-style blur on the far and near ground. Turn it off for a
  crisp view.
