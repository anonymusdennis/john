#!/usr/bin/env bash
# Fetch Big Globe reference docs into voxel-platform-handoff/vendor/big-globe/
# Run from repo root: ./voxel-platform-handoff/scripts/fetch_big_globe_refs.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VENDOR="$ROOT/voxel-platform-handoff/vendor/big-globe"
TMP="${TMPDIR:-/tmp}/bgglobe-fetch-$$"
BRANCH="scriptable-generators"
REPO="https://github.com/Builderb0y/BigGlobe"

mkdir -p "$VENDOR"
rm -rf "$TMP"
mkdir -p "$TMP"

echo "==> Cloning Big Globe ($BRANCH) shallow..."
git clone --depth 1 --branch "$BRANCH" "$REPO.git" "$TMP/repo"

echo "==> Copying reference files..."
copy() {
  local src="$1" dst="$2"
  if [[ -e "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
  fi
}

copy "$TMP/repo/List of features.md" "$VENDOR/List of features.md"
copy "$TMP/repo/LICENSE.txt" "$VENDOR/LICENSE.txt"
copy "$TMP/repo/GUIDELINES.md" "$VENDOR/GUIDELINES.md"
copy "$TMP/repo/README.md" "$VENDOR/README.md"
copy "$TMP/repo/docs" "$VENDOR/docs"

# Build MANIFEST.json listing vendored paths
python3 - <<'PY' "$VENDOR"
import json, os, sys
vendor = sys.argv[1]
paths = []
for dirpath, _, files in os.walk(vendor):
    for f in files:
        if f == "MANIFEST.json":
            continue
        full = os.path.join(dirpath, f)
        rel = os.path.relpath(full, vendor)
        paths.append(rel)
paths.sort()
manifest = {
    "source": "https://github.com/Builderb0y/BigGlobe",
    "branch": "scriptable-generators",
    "fetched_by": "fetch_big_globe_refs.sh",
    "files": paths,
}
with open(os.path.join(vendor, "MANIFEST.json"), "w") as out:
    json.dump(manifest, out, indent=2)
print(f"Wrote {len(paths)} files to {vendor}")
PY

rm -rf "$TMP"
echo "==> Done. See $VENDOR/MANIFEST.json"
