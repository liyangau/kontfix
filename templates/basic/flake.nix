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
      tf_version = "1.13.4";

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
                      upload_ca_certificate = true;
                      system_account = {
                        enable = true;
                        generate_token = true;
                      };

                      labels = {
                        environment = "dev";
                        team = "platform";
                      };
                    };
                    stg = {
                      name = "staging";
                      description = "staging control plane";
                      system_account = {
                        enable = true;
                        generate_token = true;
                      };
                      labels = {
                        environment = "stg";
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
            program = toString (
              pkgs.writers.writeBash "build" ''
                if [[ -e config.tf.json ]]; then rm -f config.tf.json; fi
                  cp ${config} config.tf.json
              ''
            );
          };
          init = {
            type = "app";
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
