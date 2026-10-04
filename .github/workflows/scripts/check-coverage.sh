#!/bin/bash
set -euo pipefail
exec "$(dirname "$0")/../../../Scripts/check-coverage.sh" "$@"
