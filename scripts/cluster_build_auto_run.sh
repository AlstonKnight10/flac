#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/cluster_build.sh"

source "$SCRIPT_DIR/env.sh"

cd "$PROJECT_ROOT/cluster_build"
./tests/test_flac_prelim.sh
