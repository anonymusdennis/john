# User Requirements

## Primary goal

Build a **voxel-based world-building platform** inside the existing John Godot 4.7 game where the player can **destroy and place voxels** in the world.

## Visual target: Space Engineers, NOT Minecraft

- The game must **not** look like a cube-game (Minecraft-style 1m blocks with pixel textures on every face).
- Target feel: **Space Engineers** — industrial, smooth or deformed surfaces, readable PBR materials, sense of mass and scale.
- Voxels are a **logical storage unit**; rendering can use smoothing, beveling, dual contouring, material blending, or other techniques. Implementation is up to the smart AI.

## Block content

### Include

- All default **environment** voxels from **vanilla Minecraft** (terrain, stone, dirt, wood, leaves, plants, fluids, decorative building blocks).
- All **Big Globe** environment/terrain/decoration blocks (clouds, river water, overgrown variants, charred wood, chorus blocks, quartz geode blocks, etc.).
- See [04-block-catalog.json](04-block-catalog.json) for the authoritative list.

### Exclude

- **All ores** (coal, iron, copper, gold, redstone, lapis, diamond, emerald, ancient debris, sulfur ore, nether quartz ore blocks, etc.).
- **Non-environment blocks**: items, tools, weapons, armor, food, redstone components, containers with loot tables as placeable blocks.
- **Mechanics-only blocks** that exist primarily as game systems, not terrain:
  - Big Globe: waypoints, hyperspace portals, automata, molten-rock-to-ore conversion, spelunking anchor/rope as functional items.
  - Vanilla: spawners, command blocks, structure blocks, end portal frames (unless smart AI decides structures are gen-only).

Structures (dungeons, villages, geodes, mega trees) are **world-generation features**, not necessarily creative-palette placeable blocks.

## World generation: phased delivery

User chose **phased compatibility**:

### Phase 1 (first)

- Working voxel engine: chunked storage, meshing, collision.
- Build + destroy tools integrated with player.
- Space Engineers aesthetic.
- Basic test terrain or flat world so the game is playable.
- Do not break existing player, inventory, enemy systems.

### Phase 2 (second)

- **Big Globe world generation** integrated.
- End goal: terrain that matches Big Globe's design intent — tall overworld (2048 blocks), nether/end (1024), biomes, caves, skylands, structures, custom Big Globe blocks.
- Smart AI **chooses the technical approach** (script VM port, algorithm reimplementation, offline bake pipeline, hybrid, etc.).
- Phase 2 does **not** require running Big Globe Java verbatim on day one, but should move toward real Big Globe behavior over time.

## Integration constraints

- Keep existing platformer player (vault, sprint, jump, punch, grenades) working.
- NavGraph should eventually sample voxel surfaces for enemy pathfinding.
- Migrate off the flat 400×400 `Ground` mesh and procedural `world_builder.gd` playground **gradually** — do not need to delete all demo content on day one.

## What the smart AI may decide freely

- Chunk size, voxel resolution, meshing algorithm.
- Data structures, threading, LOD.
- How exactly to bridge Big Globe scripts.
- Hotbar/creative menu UX for block selection.
- Whether to keep a small demo zone alongside the voxel world.

## What the smart AI must not do without user request

- Commit or push to git.
- Redistribute copyrighted Minecraft/Big Globe textures or assets without license compliance.
- Replace the entire game with a Minecraft clone aesthetic.

## Success criteria (summary)

| Phase | Done when |
|-------|-----------|
| 1 | Player can mine/place voxels; world has collision; looks SE-style; headless boot passes |
| 2 | Procedural world resembles Big Globe (tall, varied biomes, caves, BG custom terrain blocks) |
