# Big Globe Vendor Bundle

Local copy of Big Globe reference material for the smart AI implementation session.

## Contents

| Path | Description | Size (approx) |
|------|-------------|---------------|
| `docs/` | Scripting language spec + JSON schemas (from `scriptable-generators` branch) | 420 KB |
| `release/Big.Globe-6.1.2-MC26.1.2.jar` | Official mod JAR (V6.1.2, MC 26.1.2) | 7.1 MB |
| `mod-unpacked/` | JAR extracted — data packs, `.gs` scripts, assets, compiled Java classes | 29 MB |
| `List of features.md`, `LICENSE.txt`, etc. | Repo docs copied by fetch script | — |

## Key paths inside `mod-unpacked/`

```
mod-unpacked/
├── data/bigglobe/
│   ├── worldgen/              # Biomes, structures, features (JSON)
│   └── bigglobe/script_file/  # GlobeScript (.gs) worldgen sources
├── assets/                    # Block textures, models (ARR — reference only)
├── builderb0y/                # Compiled script VM / mod classes (.class)
└── fabric.mod.json
```

GlobeScript files use extension `.gs` — see `docs/scripting/` for language spec.

## License

Big Globe is **All Rights Reserved**. This vendor folder is for **local development reference only**. Do not redistribute the JAR or assets.

## Refresh

```bash
# Docs from scriptable-generators branch
./voxel-platform-handoff/scripts/fetch_big_globe_refs.sh

# Mod JAR (manual — or run fetch_mod.sh)
./voxel-platform-handoff/scripts/fetch_mod.sh
```

## Fetched

- Docs: `scriptable-generators` branch via git shallow clone
- Mod: GitHub release V6.1.2
