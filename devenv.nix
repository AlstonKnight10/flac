{ pkgs, ... }:

{
  # https://devenv.sh/packages/
  packages = with pkgs; [ git ];

  # https://devenv.sh/languages/
  languages = {
    c.enable = true;
    cplusplus.enable = true;
  };

  enterShell = ''
    export PATH="$PWD/cluster_build/src/flac:$PATH"
  '';

  scripts.build.exec = ''
    set -e

    if [ $# -ne 1 ]; then
      echo "Usage $0 <folder-name>"
      exit 1
    fi

    FOLDER_NAME="$1"
    TARGET_DIR="$PWD/build/$FOLDER_NAME"

    mkdir -p "$TARGET_DIR"
    echo "Created directory: $TARGET_DIR"

    cd "$TARGET_DIR"
    echo "Changed to: $TARGET_DIR"

    echo "Running cmake..."
    cmake ../.. -DINSTALL_MANPAGES=OFF -DWITH_OGG=OFF
    make

    cd ../..
  '';

  # See full reference at https://devenv.sh/reference/options/
}
