#!/bin/bash
export FLAC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$FLAC_ROOT/cluster_build/src/flac:$PATH"
