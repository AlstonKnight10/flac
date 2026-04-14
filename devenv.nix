{ pkgs, ... }:

{
  # https://devenv.sh/packages/
  packages = with pkgs; [ git ];

  # https://devenv.sh/languages/
  languages = {
    c.enable = true;
    cplusplus.enable = true;
  };

  # See full reference at https://devenv.sh/reference/options/
}
