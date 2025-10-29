{
  description = "Kontfix - A Nix library for managing Kong Konnect infrastructure with Terranix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    terranix.url = "github:terranix/terranix";
  };

  outputs =
    {
      self,
      nixpkgs,
      terranix,
    }:
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
    };
}
