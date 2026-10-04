#!/bin/bash
# Export LCOV, per-target summaries, and optional HTML.
set -euo pipefail
exec python3 "$(dirname "$0")/coverage.py" "$@"
