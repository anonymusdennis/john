# Voxel Platform — Implementation Notes

**Status: Phase 1 + Phase 2 implemented.** Space Engineers-style smooth destructible
voxel world with Big Globe-inspired generation, baked offline once and shipped as data.

---

## Architecture in one page

```
                    OFFLINE (dev machine, never shipped)
┌──────────────────────────────────────────────────────────────────┐
│ tools/worldgen/bg_model.gd      pure-math Big Globe-style model  │
│ tools/worldgen/bake_world.gd    CLI baker → world.sqlite + meta  │
│ tools/worldgen/bg_generator.gd  live dev generator (editor only) │
│ tools/worldgen/bake_config.json world size / seed / LODs         │
└───────────────┬──────────────────────────────────────────────────┘
                │  bake (once, ~1-3 h for 2048², resumable)
                ▼
        res://world/world.sqlite  +  world_meta.json     ← SHIPPED
                │  copied on first launch
                ▼
        user://voxel/world.sqlite  (player's editable copy)
                    RUNTIME (in game)
┌──────────────────────────────────────────────────────────────────┐
│ scripts/voxel/voxel_world.gd     terrain host, edits API, water  │
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
  triplanar-style detail noise, emissive "Core" glow below y≈-430). No Minecraft
  textures anywhere.
- **Stock-Godot safety:** every script under `scripts/voxel/` is duck-typed via
  `ClassDB` and parses on stock Godot. Without the module the game boots normally
  on the legacy flat Ground and prints a warning. `tools/worldgen/bg_generator.gd`
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

- Config: `tools/worldgen/bake_config.json` — seed 1337, 2048×2048 m, y −512..256,
  sea level 0, 5 LODs. Override ad hoc: `-- --seed 42 --size 1024 --force`.
- Writes `res://world/world.sqlite` + `world_meta.json` (bounds, spawn, water tiles).
- **Resumable:** progress is checkpointed every 4096 blocks (`bake_progress.json`);
  rerun to continue after an interrupt. `--force` restarts.
- Budget: ~900k blocks across LODs. Expect ~1–3 h for the full 2048² world
  (GDScript, single thread). Use `--size 512` (~10 min) for iteration; visual
  tuning is fastest with the **live dev generator** (just run the game with no
  baked world — `voxel_world.gd` falls back to `bg_generator.gd` automatically).

## The generator (Big Globe port, `bg_model.gd`)

Ported from the vendored BG configs (`voxel-platform-handoff/vendor/big-globe/
mod-unpacked/data/bigglobe/.../overworld/`), simplified where sane:

| Big Globe concept | Port |
|---|---|
| `river/macro` 4-oct noise (3072..384, persistence 0.4) | `_n_macro` fBm, same params |
| `raw/mountainness = ((r²)+(r²)²)/2` | same curve (amplified ×1.55 for taller ranges) |
| rivers at macro zero-crossings | `river_t = 1 − smoothstep(0, .045, |m|)` + channel carve + water at bed+2 |
| `flat_river_elevation` (Newton flattening) | elevation × `smoothstep(.02, .30, |m|)` |
| `raw/elevation` 5-oct (4096.., pers 0.4) | `_n_elev`, ±190 m |
| temperature / humidity fields | 2 fBm fields, altitude-cooled → grass/sand/snow/moss/mesa surfaces |
| deepslate blend at y≈−64 | 3D-noise-jittered boundary |
| granite/diorite/andesite/tuff/calcite pockets | two 3D pocket noises, thresholds |
| `rock_stripes` + terracotta mesa banding | sine strata × mountainness/mesa gate |
| caves (`n²/(n²+w²)` worm curves, type cells) | 2 tunnel zero-surface noises ∩ + cheese caverns, width grows with depth, sealed near water and The Core |
| features | deterministic per-16m-cell trees (wood/leaves SDF) + boulders |
| nether / end / skylands | **excluded** (user decision) |
| ores / mechanics blocks | **excluded** (requirements) |

Output per voxel: smooth SDF (isosurface at 0, negative=solid) + one of the 16
material channels of `block_registry.gd`, Mixel4-packed. The 149-block catalog
maps onto those channels (`ID_CHANNEL_OVERRIDES` + category fallback).

## Runtime behavior

- `VoxelWorld` (in `scenes/main.tscn`) activates only when the module + a world
  source exist; it then hides the flat `Ground`, spawns the player at the baked
  spawn point on a temporary safety platform until terrain collision streams in,
  builds merged water planes from `world_meta.json`, and autosaves edits every
  30 s and on quit (`save_modified_blocks`).
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
  ~5-10×. Within the stated 2 h budget at 2048², so left simple.
- Water is visual-only (no swim volumes — the game has no swim system yet).
  Tiles are 32 m quads; a polish pass could weld + skirt them.
- Trees/boulders are SDF features baked into the terrain (mineable!), not scene
  props. Decorative plants from the catalog (flowers, kelp…) are not scattered yet.
- NavGraph re-bake after mining is hooked only via the `voxel_edited` signal;
  wire it to `nav_graph.configure()` throttled if enemies need to path into mines.
- `VoxelViewer.view_distance` and `lod_distance` are conservative; tune per rig.
