-- Ruby's and Sapphire's own buildings (Battle Scene: Overworld): the ones they draw where Emerald
-- draws otherwise, in the format of specs.lua, after Emerald 3DS's (which hold wherever Ruby and
-- Sapphire draw Emerald's maps: src/scene/prints.lua).
--
-- WoobleView's own reading of Ruby's drawing (Sapphire's is Ruby's), with Emerald 3DS's kernel and
-- readers (specs.lua's `helpers`): pixels and metatile ids only. Each is checked by
-- tests/drivers/model_check.lua against its drawing.

return function(K, H, EMERALD)
  local flat_block = H.flat_block
  local GRASS = H.GRASS
  local specs = {}
  -- Emerald 3DS's spec `name` over Ruby's drawing of the same building (o: its fields replaced -
  -- another layout or rectangle), proved by model_check
  local function adopt(name, o)
    for _, s in ipairs(EMERALD or {}) do
      if s.name == name then
        local c = {}
        for k, v in pairs(s) do if k ~= "_ref" and k ~= "_model" then c[k] = v end end
        for k, v in pairs(o or {}) do c[k] = v end
        c.name = "rs_" .. name
        specs[#specs + 1] = c
        return
      end
    end
  end

  -- ── the contest hall (Slateport, Verdanturf and Fallarbor; Emerald's Battle Tents stand there) ──
  -- 5 x 5 cells (80 x 80): a flat glass roof, dotted, rows 0-49; a dark cornice, rows 50-55; the
  -- red front with its door, rows 56-79; the roof's back at z 30 (its top 30 over its front's foot,
  -- its back edge drawn on row 0). Each town draws it with its own secondary tileset, so a
  -- reference in each.
  local function hall()
    return flat_block(80, 80, { { 6, 50 }, { 10, 18 }, { 0, 6 } }, { 50, 56 }, 56, { back = 30 })
  end
  for _, h in ipairs({
    { "slateport", "LAYOUT_SLATEPORT_CITY", 8, 8, { 0x016, 0x243, 0x209, GRASS } },
    { "verdanturf", "LAYOUT_VERDANTURF_TOWN", 2, 3, { 0x204, 0x07C, GRASS } },
    { "fallarbor", "LAYOUT_FALLARBOR_TOWN", 6, 3, { 0x269, 0x279, 0x223 } },
  }) do
    specs[#specs + 1] = { name = "rs_contest_hall_" .. h[1], layout = h[2], rect = { h[3], h[4], 5, 5 }, ground = h[5],
                          parts = hall }
  end

  -- ── Mossdeep's Space Center (Ruby's: an office block, no rocket) ─────────────────
  -- 9 x 8 cells at (60, 6) (144 x 128): a flat green roof with its two dishes, rows 0-27; a
  -- cornice, rows 28-31; the front, five floors and the door, rows 32-127; the roof's back at z 100.
  specs[#specs + 1] = { name = "rs_space_center", layout = "LAYOUT_MOSSDEEP_CITY", rect = { 60, 6, 9, 8 },
    ground = { GRASS, 0x002 },
    parts = function() return flat_block(144, 128, { { 0, 28 }, { 4, 8 }, nil }, { 28, 32 }, 32, { back = 100 }) end }

  -- Mossdeep's wide house: Emerald 3DS's, over Ruby's drawing of it (a grey roof for a red)
  adopt("mossdeep_house_wide")

  -- the Safari Zone's south wing, which Ruby draws in its south-east
  adopt("safari_south_wing", { layout = "LAYOUT_SAFARI_ZONE_SOUTHEAST" })

  return specs
end
