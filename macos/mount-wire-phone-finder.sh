#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PY_SCRIPT="$SCRIPT_DIR/adb_webdav_finder.py"

/usr/bin/python3 "$PY_SCRIPT" restart

echo "Mounted at ~/WirePhone"
echo "If Finder does not open, run: open ~/WirePhone"
