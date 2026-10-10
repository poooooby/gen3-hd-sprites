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
