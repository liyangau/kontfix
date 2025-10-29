{ config, lib, ... }:

with lib;

{
  imports = [
    ./hcv.nix
    ./pinned.nix
  ];
}
