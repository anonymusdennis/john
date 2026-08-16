# Block Catalog (Human Reference)

Authoritative machine-readable list: [04-block-catalog.json](04-block-catalog.json)

## Include rules

1. **Vanilla environment** — terrain, stone, dirt, sand, wood, leaves, plants, fluids, nether/end natural blocks, decorative building blocks (bricks, terracotta, glass, prismarine).
2. **Big Globe environment** — custom terrain/decoration from [List of features.md](https://github.com/Builderb0y/BigGlobe/blob/scriptable-generators/List%20of%20features.md) blocks section.
3. **Fluids** — water, lava, Big Globe river water, soul lava (as voxel types; simulation optional).

## Exclude rules

### Ores (never generate or place in creative palette)

- All vanilla ore blocks (coal, iron, copper, gold, redstone, lapis, diamond, emerald, nether quartz, ancient debris)
- Big Globe: `sulfur_ore`, `molten_rocks` (ore conversion mechanic)

### Non-environment / mechanics

- Items, tools, weapons, armor, food
- Big Globe: waypoints, automata, spelunking anchor/rope, voidmetal blocks, sulfur block (storage)
- Vanilla: spawner, command blocks, end portal frames

### Structures

Mega dungeons, villages, geodes as **worldgen features** — not individual hotbar blocks unless smart AI adds a structure brush.

## Categories in JSON

| Category | Examples |
|----------|----------|
| `terrain` | stone, dirt, grass_block, sand, deepslate |
| `wood` | logs, planks, stems |
| `leaves` | oak_leaves, cherry_leaves |
| `plants` | flowers, grass, cactus, vines |
| `fluids` | water, lava, river_water, soul_lava |
| `nether` | netherrack, basalt, nylium |
| `end` | end_stone, chorus_plant |
| `decorative` | bricks, terracotta, glass, glowstone |
| `bigglobe` | clouds, overgrown_sand, charred_wood, void_clouds |

## Block properties (JSON fields)

| Field | Meaning |
|-------|---------|
| `solid` | Occupies cell; blocks movement |
| `transparent` | See-through (leaves, glass, ice) |
| `fluid` | Liquid voxel |
| `gravity` | Falls when unsupported (sand, gravel, overgrown_sand) |
| `emissive` | Emits light |
| `fall_damage_cancel` | Big Globe clouds — negate fall damage on land |

## Extending the catalog

Smart AI may add:

- Colored terracotta/concrete/wool (decorative)
- Slabs, stairs, walls (partial voxels — harder meshing)
- More tree variants

Keep ores and mechanics blocks out unless user changes requirements.

## Counts (starter catalog)

- **Included blocks:** ~120 entries in JSON (starter set; expandable)
- **Explicitly excluded:** listed in `excluded` section of JSON

Phase 1 may implement only 10–20 block types visually; registry should still parse full JSON for phase 2.
