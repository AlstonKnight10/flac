#!/bin/bash
set -e
mkdir -p cluster_build
cd cluster_build
cmake .. -DINSTALL_MANPAGES=OFF -DWITH_OGG=OFF \
         -DCMAKE_C_FLAGS="-pg" \
         -DCMAKE_CXX_FLAGS="-pg" \
         -DCMAKE_EXE_LINKER_FLAGS="-pg"
make -j"$(nproc)"
source ../env.sh
echo "Run 'source env.sh' to use 'flac' from the command line."
