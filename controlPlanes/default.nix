{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.kontfix;

  controlPlaneSubmodule = types.submodule {
    options = {
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Name of the control plane (if not provided, the key will be used)";
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
        default = cfg.defaults.controlPlanes.auth_type;
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
        default = false;
        description = "Whether to create and manage certificates";
      };

      pki_backend = mkOption {
        type = types.str;
        default = cfg.defaults.controlPlanes.pki_backend;
        description = "Default pki backend to generate certificate for control plane using pki_client_certs auth type";
      };

      upload_ca_certificate = mkOption {
        type = types.bool;
        default = false;
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

      storage_backend = mkOption {
        type = types.listOf types.str;
        default = cfg.defaults.controlPlanes.storage_backend;
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
{
  options.kontfix = {
    controlPlanes = mkOption {
      type = types.attrsOf (types.attrsOf controlPlaneSubmodule);
      default = { };
      description = "Control plane configurations organized by region";
      example = {
        us = {
          dev = {
            name = "dev-app";
            description = "Development control plane for applications";
            auth_type = "pinned_client_certs";
            create_certificate = true;
            upload_ca_certificate = true;
            system_account = {
              enable = true;
              generate_token = true;
            };
            storage_backend = [ "hcv" ];
            aws = {
              enable = true;
              region = "us-east-1";
              tags = {
                environment = "development";
                team = "platform";
              };
            };
          };
        };
      };
    };
  };
}
