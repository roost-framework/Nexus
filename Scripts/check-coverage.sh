#!/bin/bash
# Enforce 85% source line coverage across all test executables.
set -euo pipefail
exec python3 "$(dirname "$0")/coverage.py" --check "$@"
