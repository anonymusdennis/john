# Big Globe Source Reference

## Official source

| Item | URL |
|------|-----|
| Repository | https://github.com/Builderb0y/BigGlobe |
| Default branch | `scriptable-generators` |
| Releases (JAR) | https://github.com/Builderb0y/BigGlobe/releases |
| Modrinth | https://modrinth.com/mod/big-globe |
| Discord | https://discord.gg/ucR5K6XNNP |
| Feature list | https://github.com/Builderb0y/BigGlobe/blob/scriptable-generators/List%20of%20features.md |

## What Big Globe is

Big Globe is a **Minecraft Fabric mod** that overhauls all three vanilla dimensions:

| Dimension | Height (blocks) |
|-----------|-----------------|
| Overworld | 2048 |
| Nether | 1024 |
| End | 1024 |

It replaces vanilla terrain generation with custom features: tall mountains, deep caves, skylands, rivers, mega structures, geodes, and 100+ custom blocks. Most terrain logic is written in a **proprietary scripting language** (not JavaScript — custom DSL documented in `docs/scripting/`).

## Repository layout (branch `scriptable-generators`)

```
BigGlobe/
├── src/                    # Java source (symbolic links, hard to compile)
├── v6/                     # Version 6 sources
├── docs/
│   ├── readme.md
│   ├── scripting/          # Language spec (READ THESE for phase 2)
│   │   ├── 0 - Low level text format.md
│   │   ├── 1 - Basic syntax.md
│   │   ├── 2 - Builtin environment.md
│   │   ├── 3 - Quirks.md
│   │   ├── 4 - Optimizations.md
│   │   ├── 5 - Templates.md
│   │   └── environments/
│   ├── files/              # JSON schemas for generator configs
│   ├── common/             # Shared schemas
│   └── tutorials/
├── mapping/                # Mappings
├── List of features.md     # Biomes, structures, blocks, items
├── build.gradle            # Incomplete dependency declarations
├── LICENSE.txt             # ARR — All Rights Reserved
└── GUIDELINES.md
```

**Compile warning (from README):** dependencies undeclared, symbolic links in source sets. Treat the repo as **reference material**, not a buildable library.

## Scripting language (phase 2)

Big Globe's worldgen scripts define:

- Noise sampling, branching, loops, templates
- Block placement via builtin environment APIs
- Feature placement rules (often **not** biome-tied in BG — unlike vanilla)
- Height-dependent generation for 2048-tall worlds

**Key docs for porting:**

1. `0 - Low level text format.md` — bytecode/text representation
2. `1 - Basic syntax.md` — language grammar
3. `2 - Builtin environment.md` — APIs available inside scripts (block placement, queries)
4. `5 - Templates.md` — reusable script fragments

Scripts live inside the mod JAR and data packs. After running `fetch_big_globe_refs.sh`, check `vendor/big-globe/` for vendored copies.

## Biomes (overworld summary)

Technical biomes for vanilla interface; feature placement is script-driven:

Beach, Cherry Forest/Plains, Cold/Temperate Dense/Light Forest, Cold/Temperate Plains/Wasteland, Deep Dark, Deep/Shallow Ocean, Glacier, Ocean, Overgrown Beach, River, Swamp Forest/Plains/Wasteland, The Core (deep molten).

Nether: Ashen Wastes, Crimson Forest, Inferno, Nether Wastes, Valley of Souls, Warped Forest, Pale Garden.

End: Chorus Forest, End Barrens/Mountain/Plains, Overgrown End, The Void.

## Structures (gen features, not hotbar blocks)

Mega dungeons, geodes (amethyst/prismarine), mega trees, underground pockets, bigger desert pyramid, campfires, houses, log cabins, lakes, surface mineshafts, wells, windmills, abandoned cities, obelisks, nether pillars, portal temples, end fractals, endelisks, etc.

## License caution

Big Globe is **All Rights Reserved**. This Godot project:

- May study algorithms and scripting semantics for interoperability.
- Must **not** redistribute mod JARs, textures, or block models without permission.
- Should use **original Godot materials/meshes** inspired by block behavior, not copied Minecraft assets.

## Phase 2 integration options (smart AI chooses)

| Approach | Pros | Cons |
|----------|------|------|
| **A. Script VM port** | Runs BG scripts directly; best fidelity | Large effort; must implement full language + builtins |
| **B. Algorithm reimplementation** | Native GDScript; optimized for Godot | May drift from BG; maintenance burden |
| **C. Offline bake pipeline** | Run MC+BG externally, import chunks | Requires Minecraft runtime; not live gen |
| **D. Hybrid** | Port critical noise/height scripts; hand-code structures | Pragmatic; partial fidelity first |
| **E. JNI/subprocess Java** | Reuse compiled mod | Heavy deps; not Godot-native |

No approach is mandated. User wants **Big Globe terrain intent**, not necessarily byte-identical chunks.

## LOD system (BG reference)

Big Globe renders far terrain preview without full chunk gen. Consider similar LOD for 2048-tall Godot worlds if performance requires it.

## Dimension mapping suggestion

| Big Globe | Godot voxel world |
|-----------|-------------------|
| Overworld | Primary playable dimension |
| Nether | Optional sub-dimension or deep underground biome |
| End | Optional sky island / end zone |

Smart AI decides whether to use separate scenes, Y-offset regions, or dimension portals.

## Refresh vendored refs

```bash
./voxel-platform-handoff/scripts/fetch_big_globe_refs.sh   # docs from scriptable-generators
./voxel-platform-handoff/scripts/fetch_mod.sh            # release JAR + unpack
```

See [08-DOWNLOAD-MANIFEST.md](08-DOWNLOAD-MANIFEST.md) for all URLs.
