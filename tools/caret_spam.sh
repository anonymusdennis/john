#!/usr/bin/env bash
# Run the hold-^ (German grave) Space + right-click spam macro.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
export PYTHONUNBUFFERED=1
exec "$ROOT/.venv/bin/python" "$ROOT/caret_spam.py"
