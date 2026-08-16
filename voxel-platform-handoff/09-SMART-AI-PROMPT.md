# Smart AI Implementation Prompt

Copy everything below the line into a new genius-mode chat session.

---

You are implementing a voxel world-building platform in Godot 4.7 at `/home/headadmin/Documents/projects/john`.

## Read first (in order)

1. `voxel-platform-handoff/README.md`
2. `voxel-platform-handoff/01-USER-REQUIREMENTS.md`
3. `voxel-platform-handoff/02-PROJECT-CONTEXT.md`
4. `voxel-platform-handoff/04-block-catalog.json`
5. `voxel-platform-handoff/07-PHASE-PLAN.md`
6. `voxel-platform-handoff/06-INTEGRATION-POINTS.md`
7. `voxel-platform-handoff/03-BIG-GLOBE-SOURCE.md` (phase 2)
8. `voxel-platform-handoff/05-SPACE-ENGINEERS-AESTHETIC.md`
9. If `voxel-platform-handoff/vendor/big-globe/docs/` is empty, ask the user to run:
   `./voxel-platform-handoff/scripts/fetch_big_globe_refs.sh`

## User requirements

- **Voxel platform** with **build + destroy** (mine/place).
- Visual target: **Space Engineers** — industrial, smooth/deformed surfaces, PBR feel. **NOT** Minecraft cube aesthetic.
- **Blocks:** environment only (vanilla + Big Globe per `04-block-catalog.json`). **No ores.** No non-environment mechanics blocks (waypoints, automata, items).
- **Phase 1:** working voxel world + player tools + collision + basic terrain. Integrate with existing player movement.
- **Phase 2:** Big Globe world generation — tall worlds, biomes, caves, structures, BG custom blocks. **You choose** the technical bridge (script port, reimplementation, hybrid, etc.).
- Do not break player, inventory UI, enemy systems. Migrate off flat `Ground` / `world_builder` gradually.
- NavGraph should eventually sample voxel `nav_surface` collision; hook rebake on chunk edits.
- **Full technical freedom** on chunk size, meshing, threading, data structures.

## Constraints

- Godot 4.7 GDScript, match existing code style in `scripts/`.
- Do **not** commit unless user asks.
- Do **not** redistribute Minecraft/Big Globe copyrighted textures.
- Headless boot must pass:
  `flatpak run org.godotengine.Godot --headless --path /home/headadmin/Documents/projects/john --quit-after 5`

## Deliverables

1. **Phase 1 playable:** mine/place voxels, SE-style visuals, collision, spawn on voxel ground.
2. **Phase 2:** procedural Big Globe-inspired worldgen (document approach chosen).
3. Create `voxel-platform-handoff/IMPLEMENTATION-NOTES.md` describing architecture, files added, and phase-2 bridge.
4. Update `voxel-platform-handoff/README.md` with links to new `scripts/voxel/` code.

## Suggested starting steps

1. Read all handoff docs above.
2. Write a short architecture comment (chunk format, mesher choice, edit tool API) before coding.
3. Implement `scripts/voxel/` — `VoxelWorld`, chunk storage, mesher, `BlockRegistry` loading `04-block-catalog.json`.
4. Wire player raycast mine/place.
5. Replace or disable `Ground` in `main.tscn`.
6. Phase 2: study vendored Big Globe scripting docs; implement gen bridge.

Start now.
