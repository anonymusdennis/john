# Voxel Platform — Implementation Notes

**Status: Phase 1 + Phase 2 implemented, terrain reworked.** Space Engineers-style
smooth destructible voxel world with a **steered fantasy terrain** (Skyrim-like
mountain ranges around a flat hub vale), baked offline once and shipped as data.

---

## Architecture in one page

```
                    OFFLINE (dev machine, never shipped)
┌──────────────────────────────────────────────────────────────────┐
│ scripts/voxel/terrain_model.gd  steered fantasy terrain math     │
│ tools/worldgen/bake_world.gd    CLI baker → world.sqlite + meta  │
│ tools/worldgen/terrain_generator.gd live dev generator (editor)  │
│ tools/worldgen/bake_config.json world size / seed / LODs         │
└───────────────┬──────────────────────────────────────────────────┘
                │  bake (once, resumable)
                ▼
        res://world/world.sqlite  +  world_meta.json     ← SHIPPED
                │  copied on first launch
                ▼
        user://voxel/world.sqlite  (player's editable copy)
                    RUNTIME (in game)
┌──────────────────────────────────────────────────────────────────┐
│ scripts/voxel/voxel_world.gd     terrain host, edits API, water  │
│ scripts/voxel/terrain_model.gd   height/material queries, spawn  │
│ scripts/voxel/vegetation.gd      streamed grass + real mesh trees│
│ scripts/voxel/voxel_edit_tool.gd B build mode: mine/place/paint  │
│ scripts/voxel/block_registry.gd  catalog → 16 material channels  │
│ scripts/voxel/voxel_terrain.gdshader  triplanar procedural PBR   │
│ scripts/voxel/voxel_water.gdshader    stylized static water      │
└──────────────────────────────────────────────────────────────────┘
```

- **Voxel engine:** [godot_voxel (Zylann's Voxel Tools)](https://github.com/Zylann/godot_voxel)
  — `VoxelLodTerrain` + `VoxelMesherTransvoxel` (smooth isosurface, **not cubes**) +
  `VoxelStreamSQLite` (baked world file).
- **Materials:** Transvoxel *Mixel4* texturing — every voxel stores 4 material
  indices + blend weights; the shader colors them procedurally (muted SE palette,
  triplanar-style detail noise). No Minecraft textures anywhere.
- **Stock-Godot safety:** every script under `scripts/voxel/` is duck-typed via
  `ClassDB` and parses on stock Godot. Without the module the game boots normally
  on the legacy flat Ground and prints a warning. `tools/worldgen/terrain_generator.gd`
  is the only file that statically extends a voxel class — it lives in `tools/`
  (excluded from exports) and is only `load()`-ed when the module exists.

## Getting a voxel-enabled Godot

The module must be in the *editor/export templates* you run — it is a C++ module,
not an addon.

1. **Precompiled (easiest):** grab `godot.linuxbsd.editor.x86_64.zip` from the
   [v1.6 release](https://github.com/Zylann/godot_voxel/releases/tag/v1.6)
   (Godot 4.6 + Voxel Tools 1.6), or the GDExtension build (`v1.6x`) for stock Godot 4.5+.
2. **Headless baking needs module master (v1.6.1-dev+):** a crash when running
   `--headless` was fixed in [PR #884](https://github.com/Zylann/godot_voxel/pull/884)
   (merged 2026-08-06). For baking, build Godot 4.6/4.7 from source with the module
   at master, or run the baker from an editor build that includes the fix.
3. **Building yourself** (you said rebuilding is no trouble):
   ```bash
   git clone -b 4.7 https://github.com/godotengine/godot
   git clone https://github.com/Zylann/godot_voxel godot/modules/voxel
   cd godot && scons platform=linuxbsd target=editor -j$(nproc)
   ```

Verify any build with:
```bash
<godot> --headless --path . --script res://tools/worldgen/validate_voxel_build.gd
```

## Baking the world (once, offline)

```bash
<voxel-godot> --headless --path . --script res://tools/worldgen/bake_world.gd -- --force
```

- Config: `tools/worldgen/bake_config.json` — seed 1337, 2048×2048 m, y −80..320,
  sea level −6, 5 LODs. Override ad hoc: `-- --seed 42 --size 1024 --force`.
- Writes `res://world/world.sqlite` + `world_meta.json` (bounds, spawn, water
  tiles **and the full terrain config** — the runtime rebuilds the same
  `TerrainModel` from it for height queries, vegetation and nav bounds).
- **Resumable:** progress is checkpointed every 4096 blocks (`bake_progress.json`);
  rerun to continue after an interrupt. `--force` restarts.
- The world is much shallower than before (y −80..320 instead of −512..256), so
  bakes are correspondingly faster. Use `--size 512` for iteration; visual
  tuning is fastest with the **live dev generator** (just run the game with no
  baked world — `voxel_world.gd` falls back to `terrain_generator.gd` automatically).

## The terrain (`scripts/voxel/terrain_model.gd`)

The old "imitate Minecraft" noise-stack (Big Globe port) was replaced with a
**steered fantasy model** — the map has a deliberate macro shape instead of
uniform random hills:

| Element | How |
|---|---|
| **Hub vale** | perfectly flat meadow disc (r=195 m, blend to 290 m) at y=0 holding the entire playground; wildness ramps 0→1 across the rim |
| **Mountain ranges** | ridged (1−\|n\|) domain-warped noise, sharpened, strengthened away from the hub — Skyrim-style crests and shoulders |
| **Passes** | a second noise's zero-lines suppress ridges → walkable corridors between regions |
| **Benches** | soft terracing on mountain flanks (stand-able shelves, mapper sites) |
| **Glades** | deterministic flat clearings in the wilderness (96 m cells), intentionally left EMPTY as build sites — nothing fabricated |
| **Lakes** | basin noise pressed into lowlands, static water at sea level −6 |
| **Crags** | slope-gated 3D displacement → overhangs and nooks on steep faces only (no caves — caves were removed by request) |
| **Bedrock** | indestructible DEEPSLATE slab at the world floor (y −80..−77); SDF clamps solid and `carve_sphere` refuses to breach it |
| **Materials** | slope/altitude/moisture steering: grass, moss, dirt, gravel scree, bare stone, snowcaps, sand shores, terracotta strata, granite/diorite/calcite/andesite/tuff pockets |
| **Trees** | NOT voxels anymore — the model only emits deterministic placements (`trees_in_rect`); `vegetation.gd` renders real oak/pine meshes with trunk collision |
| **Grass** | `vegetation.gd` streams MultiMesh tufts with wind sway on grassy ground |

Output per voxel: smooth SDF (isosurface at 0, negative=solid) + one of the 16
material channels of `block_registry.gd`, Mixel4-packed. The 149-block catalog
maps onto those channels (`ID_CHANNEL_OVERRIDES` + category fallback).

## Runtime behavior

- `VoxelWorld` (in `scenes/main.tscn`) activates only when the module + a world
  source exist; it then hides the flat `Ground`, spawns the player at the baked
  spawn point on a temporary safety platform until terrain collision streams in,
  builds merged water planes from `world_meta.json`, spawns the vegetation
  streamer, and autosaves edits every 30 s and on quit (`save_modified_blocks`).
- When the ground under the spawn becomes solid, `VoxelWorld` emits
  **`terrain_ready`** — `world_builder.gd` waits for it before building the nav
  graph and spawning enemies (so the graph actually samples terrain collision
  and enemies never fall through the streaming world).
- Enemy spawns are **queued and drained one per frame** — every enemy builds a
  procedural mesh in `_ready()`, and the old same-frame burst froze the game
  above ~10 enemies. Spawn heights snap to the terrain surface, and a fall
  guard teleports anything below bedrock back to its home position.
- Terrain collision uses layers **1 (world) + 32 (nav_surface)** so NavGraph
  column sampling keeps working on voxel ground. `voxel_edited` signal is emitted
  after every carve/place for future nav refresh hooks.
- **Build mode (B):** LMB carve sphere, RMB place sphere (SDF add + Mixel4 texture
  paint), R cycles material, wheel resizes brush (1.5–6 m), ghost preview + HUD.
  Player punching/item-use is suppressed via the `build_mode_active` meta flag.
- **Potatonades carve craters** (`grenade_projectile.gd` → `carve_sphere`, 70% of
  blast radius) — outside build mode, so LMB still throws them normally.
- Edits persist in `user://voxel/world.sqlite`; delete it or run with
  `--voxel-reset` to restore the pristine shipped world.

## Export checklist (when shipping builds)

1. Export with a **voxel-enabled export template** (module builds) or ship the
   GDExtension alongside.
2. Add `world/world.sqlite` + `world/world_meta.json` as *non-resource* export
   files (Export → Resources → include filter `world/*`). The runtime copies the
   packed file to `user://` via `FileAccess`, which works from inside a .pck.
3. Exclude `voxel-platform-handoff/` and `tools/` from the export filter.

## Known limitations / next steps

- Bake is single-threaded GDScript; a worker-thread pool or C# port would cut it
  ~5-10×. The shallower world keeps it inside the stated budget, so left simple.
- Water is visual-only (no swim volumes — the game has no swim system yet).
  Tiles are 32 m quads; a polish pass could weld + skirt them.
- Boulders are SDF features baked into the terrain (mineable!). Trees are scene
  meshes streamed by `vegetation.gd`; carving the ground under one leaves it
  floating until its cell restreams.
- NavGraph re-bake after mining is hooked only via the `voxel_edited` signal;
  wire it to `nav_graph.configure()` throttled if enemies need to path into mines.
- `VoxelViewer.view_distance` and `lod_distance` are conservative; tune per rig.
