{ config, lib, ... }:
{
  imports = [
    ./defaults/options.nix
    ./defaults/config.nix
    ./certificates
    ./storage
    ./providers.nix
    ./groups
    ./controlPlanes
  ];
}
