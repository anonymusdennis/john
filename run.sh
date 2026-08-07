#!/usr/bin/env bash
# Launch John with the Flatpak Godot build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec flatpak run org.godotengine.Godot --path "$ROOT" "$@"
