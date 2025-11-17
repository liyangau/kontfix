{ lib, ... }:
with lib;
let
  groupSubmodule = types.submodule {
    options = {
      members = mkOption {
        type = types.listOf types.str;
        description = "List of control plane names to include in this group";
      };

      generate_token = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to generate and store a system account token for this group";
      };

      storage_backend = mkOption {
        type = types.listOf (
          types.enum [
            "local"
            "hcv"
            "aws"
          ]
        );
        default = [ "hcv" ];
        description = "Storage backend(s) for group system account token";
      };

      aws = mkOption {
        type = types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = "Whether to enable AWS provider";
            };
            profile = mkOption {
              type = types.str;
              default = "";
              description = "AWS profile name to use";
            };
            region = mkOption {
              type = types.str;
              default = "";
              description = "AWS region for resources";
            };
            tags = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = "AWS tags to apply when using AWS storage backend";
            };
          };
        };
        default = { };
        description = "AWS provider configuration for group system account token storage";
      };
    };
  };
in
{
  options.kontfix = {
    groups = mkOption {
      type = types.attrsOf (types.attrsOf groupSubmodule);
      default = { };
      description = "System account groups organized by region (groups.region.groupName)";
      example = {
        us = {
          dev = {
            members = [
              "dev-app"
              "dev-db"
            ];
            generate_token = true;
            storage_backend = [ "hcv" ];
          };
        };
        au = {
          staging = {
            members = [
              "staging-web"
              "staging-api"
            ];
            generate_token = true;
            storage_backend = [ "aws" ];
            aws = {
              enable = true;
              profile = "default";
              region = "ap-southeast-2";
              tags = {
                environment = "staging";
                team = "platform";
              };
            };
          };
        };
      };
    };
  };
}
