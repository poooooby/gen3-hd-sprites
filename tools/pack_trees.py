#!/usr/bin/env python3
"""Pack Emerald 3DS's tree artwork (3ds_port/assets/voxel/trees/*.png, by Zallax and
contributors, CC BY-NC-SA 4.0) into assets/scene/trees.png, at the places its own packer
(3ds_port/scripts/gen_voxel_trees.py) puts them, so src/scene/trees.lua's texel coordinates are
the port's own. Here a plain 128x128 RGBA image, top row first (the port's is the 3DS's
Morton-tiled RGBA5551, its top row v = 1).

    python tools/pack_trees.py <emerald-3ds checkout>
"""

import sys
from pathlib import Path

from PIL import Image

DIM = 128
SOURCES = (("tree_crown.png", (32, 36), (0, 0)),
           ("tree_trunk.png", (32, 32), (32, 0)),
           ("tree_small_crown.png", (16, 32), (32, 32)),
           ("tree_small_trunk.png", (16, 16), (48, 32)),
           ("tree_2_small_crown.png", (16, 32), (64, 0)),
           ("tree_2_small_trunk.png", (16, 16), (80, 0)),
           ("tree_small_trunk_jungle.png", (16, 16), (48, 48)),
           ("tree_small_trunk_grass_road.png", (16, 16), (80, 16)),
           ("tree_small_trunk_volcan.png", (16, 16), (64, 32)),
           ("tree_crown_base_floor.png", (32, 32), (96, 0)),
           ("tree_crown_base.png", (32, 32), (0, 64)),
           ("tree_crown_base_open.png", (32, 32), (32, 64)),
           ("tree_crown_mossdeep.png", (32, 32), (64, 64)),
           ("tree_north_crown.png", (32, 32), (96, 64)),
           ("tree_base_mossdeep.png", (32, 16), (64, 96)),
           ("tree_base_water_mossdeep.png", (32, 16), (96, 96)),
           ("tree_north_base_rock.png", (32, 16), (0, 96)),
           ("tree_north_base_ash.png", (32, 16), (32, 96)),
           ("tall_grass.png", (16, 32), (80, 32)),
           ("tall_grass_floor.png", (16, 16), (96, 32)),
           ("tree_small_trunk_access.png", (16, 16), (112, 32)))


def main():
    root = Path(sys.argv[1]) / "3ds_port/assets/voxel/trees"
    atlas = Image.new("RGBA", (DIM, DIM), (0, 0, 0, 0))
    for name, size, (ox, oy) in SOURCES:
        with Image.open(root / name) as source:
            if source.size != size:
                raise SystemExit(f"{name}: expected {size}, got {source.size}")
            # (alpha to 0 or 1, as the port's RGBA5551 has it)
            image = source.convert("RGBA")
            px = image.load()
            for y in range(size[1]):
                for x in range(size[0]):
                    r, g, b, a = px[x, y]
                    px[x, y] = (r, g, b, 255 if a >= 128 else 0)
            atlas.paste(image, (ox, oy))
    out = Path(__file__).resolve().parents[1] / "assets/scene/trees.png"
    atlas.save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
