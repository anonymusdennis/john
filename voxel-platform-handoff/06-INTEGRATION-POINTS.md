# Integration Points

How the voxel platform connects to existing John systems.

## Player (`scripts/player.gd`)

### New behaviors needed

| Feature | Suggestion |
|---------|------------|
| Mine / destroy | Raycast from camera; remove voxel at hit cell; play feedback |
| Place | Raycast; place on adjacent face of hit cell; ghost preview optional |
| Tool mode | Toggle build vs destroy; bind to keys or hotbar |
| Reach | Similar to `punch_reach` (~2–5 m) or longer for creative |

### Preserve

- Movement, vault, sprint, crouch, jump
- Punch/grenade on **entities** (enemies, rigid bodies) — separate from mining
- Camera modes (first/third person)
- `nav_target` group membership

### Collision

Player mask should include voxel chunk static bodies (world layer). Voxel chunks: layer `world | nav_surface` (33).

## Inventory (`scripts/inventory.gd`)

Optional phase 1 enhancement:

- Hotbar slot = selected block type for placing
- Mined blocks add to inventory (if survival mode desired)
- Creative mode: infinite place without pickup

User did not mandate survival vs creative — smart AI may ship creative first.

## NavGraph (`scripts/nav/nav_graph.gd`)

Current system ray-marches **columns** against physics layer 32 (`nav_surface`). It does not read terrain data directly.

### After voxels exist

1. Voxel chunk meshes must expose `nav_surface` collision (or equivalent static geometry on layer 32).
2. On chunk edit: **invalidate/rebake** nav nodes in affected AABB (incremental or full rebake).
3. Consider sampling voxel data directly for faster nav (optional optimization).

### Enemy AI (`scripts/enemy.gd`)

Enemies use NavGraph + trail fallback. No changes required for phase 1 if nav_surface collision is correct. Tall Big Globe terrain (phase 2) may need larger bake bounds and vertical jump links.

## World builder migration (`scripts/world_builder.gd`)

### Phase 1

- Add `VoxelWorld` node alongside or instead of flat `Ground`.
- Keep demo zones optional (disable via export flag).
- Nav graph bounds should cover voxel play area.

### Phase 2

- Replace procedural boxes with generated voxel terrain.
- Structures (jenga, ball pit) may remain as rigid-body toys in a "playground" pocket.

## Main scene (`scenes/main.tscn`)

```
Main
├── VoxelWorld          # NEW — chunk manager + mesher
├── Ground              # REMOVE or disable when voxels ready
├── WorldContent        # KEEP or trim demo content
├── Player
└── ...
```

## Physics layers

No new layer required if voxels use `world | nav_surface`. Fluids (water, lava, river water) may need trigger areas or separate fluid sim — smart AI decides.

## Grenades and explosions

`grenade_projectile.gd` sphere overlap destroys rigid bodies. Phase 2: optionally **carve voxel sphere** on explosion (user did not require — nice to have).

## Grabbable ledges

Vault system uses `grabbable` group. Voxel cliffs won't be grabbable unless tagged. Smart AI may:

- Auto-mark voxel edges above threshold height as grabbable, or
- Leave vault for placed structures only

## Signals / architecture sketch

```
VoxelWorld
  signal chunk_changed(chunk_pos)
  signal voxel_edited(world_pos, old_id, new_id)

NavGraph listens → schedule_rebake(aabb)
Player reads → get_block_at(pos), set_block_at(pos, id)
BlockRegistry → id ↔ material properties
```

## File layout suggestion (smart AI may differ)

```
scripts/voxel/
  voxel_world.gd
  voxel_chunk.gd
  voxel_mesher.gd
  block_registry.gd
  voxel_edit_tool.gd
  big_globe/          # phase 2
    gen_bridge.gd
```

## Headless boot

Voxel system must not crash when no GPU/player present. Defer mesh build or guard editor-only code.
