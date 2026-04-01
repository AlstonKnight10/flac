#!/bin/bash
set -e

mkdir -p cluster_build
cd cluster_build
cmake .. -DINSTALL_MANPAGES=OFF -DWITH_OGG=OFF
make -j"$(nproc)"

source ../env.sh
echo "Run 'source env.sh' to use 'flac' from the command line."
