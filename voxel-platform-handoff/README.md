# Voxel Platform Handoff Package

Briefing package for a **genius-mode AI** implementing a Space-Engineers-style voxel build/destroy platform in the John Godot 4.7 project, with phased Big Globe world generation.

**This folder contains no game code.** It is context, requirements, block catalogs, and references only.

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
