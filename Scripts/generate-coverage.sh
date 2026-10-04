#!/bin/bash
# Run the full suite with coverage; SwiftPM refreshes the raw profiles.
set -euo pipefail
cd "$(dirname "$0")/.."
exec swift test --enable-code-coverage "$@"
