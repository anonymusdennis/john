# Download Manifest

URLs for materials a **smart AI cannot fetch**. A human with network access should run:

```bash
./voxel-platform-handoff/scripts/fetch_big_globe_refs.sh
./voxel-platform-handoff/scripts/fetch_mod.sh
```

Or download items manually below.

---

## Big Globe repository

| Resource | URL |
|----------|-----|
| Repo (browse) | https://github.com/Builderb0y/BigGlobe |
| Branch | `scriptable-generators` |
| ZIP archive | https://github.com/Builderb0y/BigGlobe/archive/refs/heads/scriptable-generators.zip |
| Feature list | https://raw.githubusercontent.com/Builderb0y/BigGlobe/scriptable-generators/List%20of%20features.md |
| LICENSE | https://raw.githubusercontent.com/Builderb0y/BigGlobe/scriptable-generators/LICENSE.txt |
| GUIDELINES | https://raw.githubusercontent.com/Builderb0y/BigGlobe/scriptable-generators/GUIDELINES.md |

## Big Globe scripting docs (phase 2)

| Doc | URL |
|-----|-----|
| Docs readme | https://raw.githubusercontent.com/Builderb0y/BigGlobe/scriptable-generators/docs/readme.md |
| 0 - Low level text format | https://raw.githubusercontent.com/Builderb0y/BigGlobe/scriptable-generators/docs/scripting/0%20-%20Low%20level%20text%20format.md |
| 1 - Basic syntax | https://raw.githubusercontent.com/Builderb0y/BigGlobe/scriptable-generators/docs/scripting/1%20-%20Basic%20syntax.md |
| 2 - Builtin environment | https://raw.githubusercontent.com/Builderb0y/BigGlobe/scriptable-generators/docs/scripting/2%20-%20Builtin%20environment.md |
| 3 - Quirks | https://raw.githubusercontent.com/Builderb0y/BigGlobe/scriptable-generators/docs/scripting/3%20-%20Quirks.md |
| 4 - Optimizations | https://raw.githubusercontent.com/Builderb0y/BigGlobe/scriptable-generators/docs/scripting/4%20-%20Optimizations.md |
| 5 - Templates | https://raw.githubusercontent.com/Builderb0y/BigGlobe/scriptable-generators/docs/scripting/5%20-%20Templates.md |
| Scripting environments folder | https://github.com/Builderb0y/BigGlobe/tree/scriptable-generators/docs/scripting/environments |
| JSON schemas (files/) | https://github.com/Builderb0y/BigGlobe/tree/scriptable-generators/docs/files |
| Common schemas | https://github.com/Builderb0y/BigGlobe/tree/scriptable-generators/docs/common |
| Tutorials | https://github.com/Builderb0y/BigGlobe/tree/scriptable-generators/docs/tutorials |

## Big Globe releases (optional)

| Resource | URL |
|----------|-----|
| All releases | https://github.com/Builderb0y/BigGlobe/releases |
| Modrinth | https://modrinth.com/mod/big-globe |

Use JAR only for reference/decompilation study — **do not redistribute** (ARR license).

## Minecraft block reference (IDs only — no assets)

| Resource | URL |
|----------|-----|
| Block list wiki | https://minecraft.wiki/w/Block |
| Java Edition data values | https://minecraft.wiki/w/Java_Edition_data_values |

Use for validating block IDs in `04-block-catalog.json`. **Do not copy textures.**

## Space Engineers aesthetic reference (optional)

| Resource | Notes |
|----------|-------|
| https://www.spaceengineersgame.com/ | Official site — screenshots for scale/material feel |
| Steam store page | User may capture reference images locally |

No assets to download — visual inspiration only.

## Godot documentation (online)

| Topic | URL |
|-------|-----|
| ArrayMesh | https://docs.godotengine.org/en/stable/classes/class_arraymesh.html |
| ConcavePolygonShape3D | https://docs.godotengine.org/en/stable/classes/class_concavepolygonshape3d.html |
| Threading | https://docs.godotengine.org/en/stable/tutorials/performance/threads/index.html |

## After fetch

Vendored files land in:

```
voxel-platform-handoff/vendor/big-globe/
```

See `vendor/big-globe/MANIFEST.json` for what was copied.

## License reminder

- Big Globe: **All Rights Reserved** — study only; create original Godot assets.
- Minecraft: **Mojang/Microsoft** — block names are reference; no texture rip.
