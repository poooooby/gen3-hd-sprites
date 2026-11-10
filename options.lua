-- Mod Manager options for gen3-hd-sprites. Labels are at most 14 characters.
return {
  {
    key = "battle_hd",
    label = "Battle HD",
    type = "toggle",
    default = true,
    description = "Draw battle Pokemon that a sprite mod has tagged at your screen's full resolution, at any size. Off: the game's usual pixel grid.",
  },
  {
    key = "battle_fit",
    label = "Battle Fit",
    type = "toggle",
    default = true,
    description = "When a battle Pokemon is too tall for the screen, the camera pulls back so the whole Pokemon fits, its platform shrinking with it. The text box and HP bars never change. Needs Battle HD.",
  },
  {
    key = "fill_screen",
    label = "Fill Screen",
    type = "toggle",
    default = true,
    description = "With Battle Fit, the battle scene fills your whole screen, top to bottom and out to the sides, while the text box, HP bars and menus keep their sharp size, docked to the bottom. The summary, party, bag, Pokedex page, evolution and nickname screens fill it too. Off: the usual framed battle screen.",
  },
  {
    key = "field_hd",
    label = "Field HD",
    type = "toggle",
    default = true,
    description = "Draw overworld Pokemon that a mod has tagged (wild Pokemon, your follower) at your screen's full resolution. Turn off on a slow device: it adds a few full-screen layers to each frame.",
  },
  {
    key = "dex_hd",
    label = "Pokedex & Summary HD",
    type = "toggle",
    default = true,
    description = "Draw the Pokemon that a sprite mod has tagged in the Pokedex and on the Pokemon summary screen at your screen's full resolution, scaled to fit their frame. Off: the game's usual pixel grid.",
  },
}
