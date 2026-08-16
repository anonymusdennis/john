# Voxel Platform Handoff Package

Briefing package for a **genius-mode AI** implementing a Space-Engineers-style voxel build/destroy platform in the John Godot 4.7 project, with phased Big Globe world generation.

**This folder contains no game code.** It is context, requirements, block catalogs, and references only.

> **Status: IMPLEMENTED.** See [IMPLEMENTATION-NOTES.md](IMPLEMENTATION-NOTES.md) for the
> architecture, bake instructions and runtime controls. Code lives in:
>
> | Path | Purpose |
> |------|---------|
> | [`../scripts/voxel/voxel_world.gd`](../scripts/voxel/voxel_world.gd) | Runtime terrain host + edit API (carve/place/paint) |
> | [`../scripts/voxel/voxel_edit_tool.gd`](../scripts/voxel/voxel_edit_tool.gd) | B build mode: mine/place, material cycle, brush |
> | [`../scripts/voxel/block_registry.gd`](../scripts/voxel/block_registry.gd) | 04-block-catalog.json → 16 material channels |
> | [`../scripts/voxel/voxel_terrain.gdshader`](../scripts/voxel/voxel_terrain.gdshader) | SE-style procedural terrain shader (Mixel4) |
> | [`../scripts/voxel/voxel_water.gdshader`](../scripts/voxel/voxel_water.gdshader) | Stylized static water |
> | [`../tools/worldgen/bg_model.gd`](../tools/worldgen/bg_model.gd) | Big Globe-inspired generator math |
> | [`../tools/worldgen/bake_world.gd`](../tools/worldgen/bake_world.gd) | Offline baker → `res://world/world.sqlite` |
> | [`../tools/worldgen/bg_generator.gd`](../tools/worldgen/bg_generator.gd) | Live dev generator (editor iteration) |
> | [`../tools/worldgen/validate_voxel_build.gd`](../tools/worldgen/validate_voxel_build.gd) | Checks your Godot build has the voxel module |
> | [`../tools/worldgen/bake_config.json`](../tools/worldgen/bake_config.json) | World size / seed / LOD config |

---

## Read order

| # | File | Purpose |
|---|------|---------|
| 1 | [01-USER-REQUIREMENTS.md](01-USER-REQUIREMENTS.md) | What the user wants and does not want |
| 2 | [02-PROJECT-CONTEXT.md](02-PROJECT-CONTEXT.md) | Current Godot project structure, physics, scripts |
| 3 | [03-BIG-GLOBE-SOURCE.md](03-BIG-GLOBE-SOURCE.md) | Big Globe mod reference, scripting language, phase-2 options |
| 4 | [04-BLOCK-CATALOG.md](04-BLOCK-CATALOG.md) | Human-readable block include/exclude rules |
| 4b | [04-block-catalog.json](04-block-catalog.json) | Machine-readable block registry |
| 5 | [05-SPACE-ENGINEERS-AESTHETIC.md](05-SPACE-ENGINEERS-AESTHETIC.md) | Visual and feel targets |
| 6 | [06-INTEGRATION-POINTS.md](06-INTEGRATION-POINTS.md) | How voxels connect to player, nav, enemies |
| 7 | [07-PHASE-PLAN.md](07-PHASE-PLAN.md) | Phase 1 and Phase 2 acceptance criteria |
| 8 | [08-DOWNLOAD-MANIFEST.md](08-DOWNLOAD-MANIFEST.md) | URLs to fetch (AI cannot download — human runs script) |
| 9 | [09-SMART-AI-PROMPT.md](09-SMART-AI-PROMPT.md) | Copy-paste prompt for implementation session |

## Vendor data (Big Globe)

**Status: downloaded locally** — see [vendor/big-globe/README.md](vendor/big-globe/README.md).

| Script | What it fetches |
|--------|-----------------|
| `scripts/fetch_big_globe_refs.sh` | Docs + feature list from `scriptable-generators` branch |
| `scripts/fetch_mod.sh` | Release JAR + unpack to `vendor/big-globe/mod-unpacked/` |

Refresh both:

```bash
./voxel-platform-handoff/scripts/fetch_big_globe_refs.sh
./voxel-platform-handoff/scripts/fetch_mod.sh
```

Current mod: **Big.Globe-6.1.2-MC26.1.2.jar** (V6.1.2) — 17 GlobeScript `.gs` files + ~1800 JSON worldgen configs inside `mod-unpacked/`.

## Project root

```
/home/headadmin/Documents/projects/john
```

Run the game:

```bash
flatpak run org.godotengine.Godot --path /home/headadmin/Documents/projects/john
```

Headless validation:

```bash
flatpak run org.godotengine.Godot --headless --path /home/headadmin/Documents/projects/john --quit-after 5
```
