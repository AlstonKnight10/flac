#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

mkdir -p "$PROJECT_ROOT/cluster_build"
mkdir -p "$PROJECT_ROOT/cluster_build/inputs"
mkdir -p "$PROJECT_ROOT/cluster_build/outputs"

cd "$PROJECT_ROOT/cluster_build"
cmake .. -DINSTALL_MANPAGES=OFF -DWITH_OGG=OFF
make -j"$(nproc)"

source "$SCRIPT_DIR/env.sh"
echo "Run 'source scripts/env.sh' to use 'flac' from the command line."
