# Space Engineers Aesthetic Reference

## What the user means

**Not Minecraft.** The voxel grid is invisible to the player. Surfaces should feel **constructed, industrial, and physical** — like Space Engineers (Keen Software House), not like placing textured cubes in a sandbox.

Space Engineers uses **2.5 m voxels** with:

- Smooth or beveled edges where blocks meet
- PBR materials (metal, stone, ice) with wear and variation
- Large-scale structures that read as engineering, not pixel art
- Strong sense of mass; lighting and shadows sell weight

## Visual goals for John

| Aspect | Target |
|--------|--------|
| Scale | Blocks feel **large** (consider 1–2.5 m cells; SE uses 2.5 m) |
| Silhouette | Avoid obvious 1×1 Minecraft stair-step everywhere |
| Materials | Procedural or PBR: roughness/metalness variation, not 16×16 textures |
| Edges | Chamfer, smooth normals, or dual-contouring — smart AI picks technique |
| Color | Muted industrial palette for stone/metal; saturated accents for plants/fluids |
| Sky/light | Existing main.tscn has good baseline (SSAO, fog, directional sun) |

## Rendering techniques (options — not requirements)

- **Greedy meshing + normal smoothing** — simple, fast
- **Dual contouring / surface nets** — organic caves and SE-like smooth rock
- **SDF blending** — smooth joins between materials
- **Per-material shader** — triplanar mapping hides UV seams on deformed meshes
- **LOD** — required for large Big Globe worlds in phase 2

## What to avoid

- Visible grid lines on every face
- Per-face grass/dirt pixel textures at 1 m scale
- Bright saturated "Minecraft beta" colors as default
- Tiny voxel size that turns terrain into noise

## Audio / feel (optional, phase 2+)

SE has satisfying weld/grind sounds. Phase 1 can use placeholder feedback on place/destroy.

## Reference media (human may gather)

- Space Engineers: stone asteroids, planetary surfaces, large armor blocks
- Not reference: Minecraft shaders, block texture packs

## Acceptance check

Ask: *"Would a player describe this as Space Engineers-like or Minecraft-like?"* Phase 1 should lean SE.

See [05-SPACE-ENGINEERS-AESTHETIC.md](05-SPACE-ENGINEERS-AESTHETIC.md) — this file is the aesthetic brief.
