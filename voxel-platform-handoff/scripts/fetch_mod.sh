#!/usr/bin/env bash
# Download and unpack the latest Big Globe mod JAR into vendor/big-globe/
# Run from repo root: ./voxel-platform-handoff/scripts/fetch_mod.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VENDOR="$ROOT/voxel-platform-handoff/vendor/big-globe"
RELEASE_TAG="${BIGGLOBE_RELEASE:-V6.1.2}"
JAR_NAME="${BIGGLOBE_JAR:-Big.Globe-6.1.2-MC26.1.2.jar}"
URL="https://github.com/Builderb0y/BigGlobe/releases/download/${RELEASE_TAG}/${JAR_NAME}"

mkdir -p "$VENDOR/release" "$VENDOR/mod-unpacked"

echo "==> Downloading $JAR_NAME ..."
curl -fsSL -o "$VENDOR/release/$JAR_NAME" "$URL"

echo "==> Unpacking to mod-unpacked/ ..."
rm -rf "$VENDOR/mod-unpacked"
mkdir -p "$VENDOR/mod-unpacked"
unzip -q "$VENDOR/release/$JAR_NAME" -d "$VENDOR/mod-unpacked"

GS_COUNT=$(find "$VENDOR/mod-unpacked" -name '*.gs' | wc -l)
echo "==> Done. $GS_COUNT GlobeScript (.gs) files found."
echo "    JAR: $VENDOR/release/$JAR_NAME"
echo "    Unpacked: $VENDOR/mod-unpacked/"
