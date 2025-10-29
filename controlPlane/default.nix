{
  lib,
  utils,
  controlPlaneDefaults ? { },
}:

with lib;

let
  controlPlaneSubmodule = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Name of the control plane";
      };

      output = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to output the control plane details";
      };

      cluster_type = mkOption {
        type = types.str;
        default = "CLUSTER_TYPE_CONTROL_PLANE";
        description = "Type of the control plane";
      };

      auth_type = mkOption {
        type = types.str;
        default = controlPlaneDefaults.auth_type;
        description = "Authentication type for the control plane";
      };

      description = mkOption {
        type = types.str;
        default = "";
        description = "Description of the control plane";
      };

      labels = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Labels for the control plane";
      };

      members = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of member control plane names";
      };

      create_certificate = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to create and manage certificates";
      };

      upload_ca_certificate = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to upload CA certificate to the control plane";
      };

      ca_certificate = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Custom CA certificate for this control plane (overrides defaults.pki_ca_certificate)";
      };

      system_account = mkOption {
        type = types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = "Whether to create an individual system account for this control plane";
            };
            generate_token = mkOption {
              type = types.bool;
              default = false;
              description = "Whether to generate an access token for the system account (stored in storage backend)";
            };
          };
        };
        default = { };
        description = "System account configuration";
      };

      custom_plugins = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of custom plugins to enable";
      };

      enable_custom_plugins = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable custom plugins";
      };

      storage_backend = mkOption {
        type = types.listOf types.str;
        default = controlPlaneDefaults.storage_backend;
        description = "Storage backend options";
      };

      aws = mkOption {
        type = types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = "Whether to enable AWS provider (required for AWS resources even when not using AWS storage)";
            };
            profile = mkOption {
              type = types.str;
              default = "";
              description = "AWS profile name to use (default: empty string, will use default AWS credentials chain)";
            };
            region = mkOption {
              type = types.str;
              default = "";
              description = "AWS region for resources (default: empty string, will use environment or AWS config)";
            };
            tags = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = "AWS tags to apply when using AWS storage backend";
            };
          };
        };
        default = { };
        description = "AWS provider configuration";
      };

    };
  };

in
controlPlaneSubmodule
