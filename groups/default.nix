{
  config,
  lib,
  sharedContext,
  ...
}:

{
  imports = [
    ./options.nix
    ./config.nix
  ];
}
