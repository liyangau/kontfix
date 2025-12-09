{
  description = "Kong Konnect Infrastructure";

  inputs = {
    nixpkgs-terraform.url = "github:stackbuilders/nixpkgs-terraform";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    kontfix.url = "github:liyangau/kontfix";
  };

  outputs =
    {
      self,
      nixpkgs-terraform,
      nixpkgs,
      systems,
      kontfix,
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

      terraformConfiguration =
        system:
        kontfix.lib.kontfixConfiguration {
          inherit system;
          modules = [
            {
              kontfix = {
                defaults = {
                  controlPlanes = {
                    auth_type = "pinned_client_certs";
                    storage_backend = [ "local" ];
                  };
                };

                controlPlanes = {
                  us = {
                    dev = {
                      description = "dev control plane";
                      create_certificate = true;
                      system_account = {
                        enable = true;
                        generate_token = true;
                      };
                      labels = {
                        environment = "dev";
                        team = "platform";
                      };
                    };
                  };
                };
              };
            }
          ];
        };
    in
    {
      apps = forEachSystem (
        { system, pkgs }:
        let
          terraform = nixpkgs-terraform.packages.${system}.${tf_version};
          config = terraformConfiguration system;
        in
        {
          build = {
            type = "app";
            meta.description = "Build terraform configuration file";
            program = toString (
              pkgs.writers.writeBash "build" ''
                if [[ -e config.tf.json ]]; then rm -f config.tf.json; fi
                  cp ${config} config.tf.json
              ''
            );
          };
          init = {
            type = "app";
            meta.description = "Init terraform configuration file";
            program = toString (
              pkgs.writers.writeBash "init" ''
                if [[ -e config.tf.json ]]; then rm -f config.tf.json; fi
                cp ${config} config.tf.json \
                  && ${terraform}/bin/terraform init "$@"
              ''
            );
          };
          plan = {
            type = "app";
            meta.description = "Plan terraform changes";
            program = toString (
              pkgs.writers.writeBash "plan" ''
                if [[ -e config.tf.json ]]; then rm -f config.tf.json; fi
                cp ${config} config.tf.json \
                  && ${terraform}/bin/terraform plan "$@"
              ''
            );
          };
          apply = {
            type = "app";
            meta.description = "Apply terraform changes";
            program = toString (
              pkgs.writers.writeBash "apply" ''
                if [[ -e config.tf.json ]]; then rm -f config.tf.json; fi
                cp ${config} config.tf.json \
                  && ${terraform}/bin/terraform apply "$@"
              ''
            );
          };
          destroy = {
            type = "app";
            meta.description = "Destroy terraform managed infrastructure";
            program = toString (
              pkgs.writers.writeBash "destroy" ''
                if [[ -e config.tf.json ]]; then rm -f config.tf.json; fi
                cp ${config} config.tf.json \
                  && ${terraform}/bin/terraform destroy "$@"
              ''
            );
          };
        }
      );

      devShells = forEachSystem (
        { system, pkgs }:
        let
          terraform = nixpkgs-terraform.packages.${system}.${tf_version};
        in
        {
          default = pkgs.mkShell {
            buildInputs = [ terraform ];
          };
        }
      );
    };
}
