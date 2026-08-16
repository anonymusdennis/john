# Phase Plan

## Phase 1 — Voxel platform (ship first)

### Scope

Build the core voxel engine and player tools. World can be flat, simple noise, or small test island. Big Globe gen is **out of scope** for phase 1 except block registry entries for BG blocks.

### Acceptance criteria

- [ ] Chunked voxel storage (bounded or infinite with streaming)
- [ ] Mesh rebuild when voxels change
- [ ] **Space Engineers** visual feel (not Minecraft cubes) — see [05-SPACE-ENGINEERS-AESTHETIC.md](05-SPACE-ENGINEERS-AESTHETIC.md)
- [ ] Player can **destroy** voxels (raycast mine)
- [ ] Player can **place** voxels (raycast place adjacent face)
- [ ] Collision works — player walks on voxel terrain
- [ ] Block registry loads environment blocks from [04-block-catalog.json](04-block-catalog.json) (at least a starter subset; full catalog can be incremental)
- [ ] `nav_surface` collision on chunk meshes OR documented follow-up task
- [ ] Game boots headless: `flatpak run org.godotengine.Godot --headless --path . --quit-after 5`
- [ ] Existing player movement (jump, vault, sprint) still works
- [ ] No regression to inventory UI (may not integrate placing yet)

### Suggested milestones

1. **M1:** `VoxelWorld` + flat chunk + greedy/smooth mesher + collision
2. **M2:** Edit tool on player (mine/place) + block selection
3. **M3:** Replace/disable flat `Ground`; player spawns on voxels
4. **M4:** NavGraph rebake hook on edit (can be stub with manual rebake)

### Out of scope for phase 1

- Big Globe script execution
- All 200+ blocks textured (subset OK)
- Fluids simulation
- Multiplayer
- Save/load (nice to have)

---

## Phase 2 — Big Globe world generation

### Scope

Procedural world matching **Big Globe design intent**: tall overworld, biomes, caves, rivers, skylands, structures, custom BG blocks.

### Acceptance criteria

- [ ] World generates without manual placement (infinite or large seeded world)
- [ ] Vertical range supports tall terrain (BG overworld concept: up to ~2048 blocks — scale as needed for Godot performance)
- [ ] Multiple biomes visible across travel distance
- [ ] Caves / overhangs / varied elevation (not flat noise)
- [ ] Big Globe custom environment blocks appear in correct contexts (clouds, river water, overgrown sand, etc.)
- [ ] Structures or structure proxies (geodes, mega trees, dungeons) — at least a subset
- [ ] Ores still **excluded** from generation per user request
- [ ] Performance: playable FPS on target hardware (define budget in implementation)
- [ ] Document chosen bridge approach in handoff README

### Bridge decision (smart AI picks one)

See options in [03-BIG-GLOBE-SOURCE.md](03-BIG-GLOBE-SOURCE.md):

- Script VM port
- Algorithm reimplementation in GDScript
- Offline bake import
- Hybrid

### Suggested milestones

1. **M1:** Heightmap + biome map (2D) → basic column filler
2. **M2:** Cave carving (3D noise or BG script equivalent)
3. **M3:** BG block rules (river water, clouds, overgrown borders)
4. **M4:** Structure placement (geodes, trees, dungeons)
5. **M5:** LOD + distant terrain preview (optional, BG has LOD system)

### Reference materials

After `fetch_big_globe_refs.sh`:

- `vendor/big-globe/docs/scripting/*`
- `vendor/big-globe/List of features.md`
- `vendor/big-globe/docs/files/*` (JSON schemas)

---

## Testing checklist (both phases)

| Test | Phase |
|------|-------|
| Walk, jump, vault on voxel ground | 1 |
| Mine a wall, place block back | 1 |
| Visual: not Minecraft-cube aesthetic | 1 |
| Enemy chases player on voxel terrain | 1+ |
| Travel 500m — biome/terrain changes | 2 |
| Find cave, skyland, or river feature | 2 |
| No ore blocks in world | 2 |
| Headless boot | 1+ |

---

## Documentation deliverable

After implementation, smart AI updates:

- `voxel-platform-handoff/README.md` — link to new `scripts/voxel/` files
- Short `IMPLEMENTATION-NOTES.md` in handoff folder (create if missing) with architecture chosen
