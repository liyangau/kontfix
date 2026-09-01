{
  description = "Kontfix test suite";

  inputs = {
    kontfix.url = "path:../";
    # Follow the library flake's pins so the harness evaluates against
    # exactly the nixpkgs the library uses.
    nixpkgs.follows = "kontfix/nixpkgs";
    systems.follows = "kontfix/systems";
    # Only the harness runs terraform (validate apps), so the provider is
    # pinned here rather than in the library flake.
    nixpkgs-terraform.url = "github:stackbuilders/nixpkgs-terraform";
  };

  outputs =
    {
      self,
      kontfix,
      nixpkgs,
      systems,
      nixpkgs-terraform,
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

      tf_version = "terraform-1.14.0";

      testsFor =
        { system, pkgs }:
        import ./default.nix {
          inherit pkgs system;
          kontfixLib = kontfix.lib;
          terraform = nixpkgs-terraform.packages.${system}.${tf_version};
        };
    in
    {
      apps = forEachSystem (
        { system, pkgs }:
        (testsFor { inherit system pkgs; }).apps
      );

      devShells = forEachSystem (
        { system, pkgs }:
        {
          default = (testsFor { inherit system pkgs; }).devShell;
        }
      );
    };
}
