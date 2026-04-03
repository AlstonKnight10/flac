#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/cluster_build.sh"
source "$SCRIPT_DIR/env.sh"
"$SCRIPT_DIR/test_flac_prelim.sh"
