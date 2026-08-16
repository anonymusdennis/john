# Project Context — John (Godot 4.7)

## Engine and rendering

| Setting | Value |
|---------|-------|
| Godot | 4.7, Forward Plus |
| Physics | Jolt (`project.godot` → `[physics] 3d/physics_engine`) |
| Viewport | 1280×720 |
| MSAA | 2× |
| Autoload | `Inventory` → `res://scripts/inventory.gd` |

## Scene tree (`scenes/main.tscn`)

```
Main (Node3D)
├── WorldEnvironment     — sky, SSAO, glow, fog
├── Sun (DirectionalLight3D)
├── Ground (StaticBody3D) — 400×400×1 box at y=-0.5, layers world+nav_surface
├── Player               — res://scenes/player.tscn
├── WorldContent         — scripts/world_builder.gd (procedural demo map)
└── InventoryUI          — scripts/inventory_ui.gd
```

**Voxel work will eventually replace `Ground` and much of `WorldContent`.**

## Physics layers (`project.godot`)

| Bit | Name | Mask value | Used by |
|-----|------|------------|---------|
| 1 | world | 1 | Static geometry, rigid props |
| 2 | player | 2 | Player CharacterBody3D |
| 3 | grabbable | 4 | Vault/climb ledges |
| 4 | enemy | 8 | Enemy CharacterBody3D |
| 6 | nav_surface | 32 | NavGraph column sampling |

**Suggested for voxels:** static voxel chunks on `world | nav_surface` (layer 33), same as current ground.

## Key scripts

| Path | Role |
|------|------|
| `scripts/player.gd` | Platformer: move, sprint, crouch, jump, vault, punch, grenade throw, camera modes |
| `scripts/world_builder.gd` | Spawns demo geometry, enemies, nav graph, zones on 400×400 map |
| `scripts/nav/nav_graph.gd` | Voxel-column nav sampler + async A* (NOT terrain — separate system) |
| `scripts/nav/path_recorder.gd` | Player breadcrumb trail for enemy AI fallback |
| `scripts/enemy.gd` | Procedural-animation enemy AI + chase/path/home states |
| `scripts/inventory.gd` | Hotbar + bag inventory (autoload) |
| `scripts/inventory_ui.gd` | UI for inventory |
| `scripts/grenade_projectile.gd` | Throwable explosive |
| `scripts/grabbable_ledge.gd` | Marks vaultable surfaces |
| `scripts/anim/proc_animator.gd` | Procedural enemy animation |

## Player capabilities relevant to voxels

- **Raycasts** already used for vault, punch, crouch stand-up check.
- **Collision mask** = 13 (world + grabbable + enemy).
- **Groups:** `player`, `nav_target`.
- Punch uses sphere overlap + impulse (`punch_reach`, `punch_radius`).
- No mining/placing yet — new tool modes needed.

## Current world generation

There is **no terrain voxel system**. `world_builder.gd` places:
- Static boxes (platforms, stairs, roads, buildings)
- Rigid bodies (jenga, cubes, ball pit)
- Enemies (~12+ near spawn, more in zones)
- `NavGraph` baked over `AABB(-180,-6,-180, 360×56×360)` (approximate; check `world_builder.gd` for current bounds)

## Assets

```
assets/models/potato.glb
assets/models/enemy.glb   (enemies use proc anim, not this mesh)
icon.svg
```

No block textures exist yet. Smart AI will need procedural materials, generated atlases, or placeholder PBR.

## Run commands

```bash
# Editor
flatpak run org.godotengine.Godot --editor --path /home/headadmin/Documents/projects/john

# Play
./run.sh

# Headless smoke test
flatpak run org.godotengine.Godot --headless --path /home/headadmin/Documents/projects/john --quit-after 5
```

## Git state

Repo: `anonymusdennis/john` on GitHub. Last known pushed commit includes platformer + procedural enemies. Local uncommitted work may exist (enemy AI, etc.). Do not commit unless user asks.

## Related handoff doc

Enemy AI overhaul notes (separate feature): `/home/headadmin/Documents/projects/john/everything new.md`
