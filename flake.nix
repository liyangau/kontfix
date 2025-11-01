{
  description = "Kontfix - A Nix library for managing Kong Konnect infrastructure with Terranix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    terranix.url = "github:terranix/terranix";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    {
      self,
      nixpkgs,
      terranix,
      systems,
    }:
    let
      forEachSystem =
        f:
        nixpkgs.lib.genAttrs (import systems) (
          system:
          f {
            inherit system;
            pkgs = nixpkgs.legacyPackages.${system};
          }
        );

      eval = nixpkgs.lib.evalModules {
        modules = [
          ./docs
        ];
      };
    in
    {
      lib = {
        kontfixConfiguration =
          {
            system,
            modules ? [ ],
            ...
          }:
          terranix.lib.terranixConfiguration {
            inherit system;
            modules = [
              ./default.nix
            ]
            ++ modules;
          };
      };

      nixosModules.default = ./default.nix;

      kontfixModule = ./default.nix;

      templates = {
        basic = {
          path = ./templates/basic;
          description = "Basic Kontfix setup for Kong Konnect infrastructure";
        };

        cpg = {
          path = ./templates/cpg;
          description = "Kontfix to set up Konnect Control Plane Group (CPGs)";
        };

        multi-region = {
          path = ./templates/multi-region;
          description = "Multi-region Kong Konnect setup";
        };
      };

      defaultTemplate = self.templates.basic;

      packages = forEachSystem (
        { system, pkgs }:
        let
          docsBuild = import ./docs/build.nix { inherit pkgs self eval; };
        in
        {
          inherit (docsBuild)
            docs-md
            docs
            docs-deploy
            defaults-docs-md
            controlplanes-docs-md
            groups-docs-md;
        }
      );
    };
}
