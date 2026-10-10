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
    type = "choice",
    default = "fit",
    choices = {
      { "Off", "off" },
      { "Fit Sprites", "fit" },
      { "Fit Tall Too", "tall" },
    },
    description = "When a battle Pokemon is too tall for the screen, the camera pulls back so the whole Pokemon fits, its platform shrinking with it. The text box and HP bars never change. Fit Tall Too pulls back further for the very biggest (Lugia, Koraidon). Needs Battle HD.",
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
    label = "Pokedex HD",
    type = "toggle",
    default = true,
    description = "Draw the Pokedex's Pokemon that a sprite mod has tagged at your screen's full resolution, scaled to fit the Pokedex. Off: the game's usual pixel grid.",
  },
}
