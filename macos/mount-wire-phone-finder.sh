#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VIRTUAL_ENV="$PROJECT_ROOT/.venv"

if [ -d "$VIRTUAL_ENV" ]; then
    PYTHON_EXE="$VIRTUAL_ENV/bin/python3"
else
    PYTHON_EXE="/usr/bin/python3"
fi

"$PYTHON_EXE" "$SCRIPT_DIR/adb_webdav_finder.py" restart

echo "Mounted at ~/WirePhone"
