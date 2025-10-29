{ config, lib, ... }:
with lib;
let
  utils = import ./lib/utils.nix { inherit lib config; };
  cfg = config.kontfix;

  # Process everything once - control planes AND groups
  processed = utils.createSharedContext {
    cps = cfg.controlPlanes;
    groups = cfg.groups;
    defaultLabels = cfg.defaults.controlPlanes.labels;
    defaults = cfg.defaults;
  };

  allControlPlaneNames = processed.allControlPlaneNames;
  controlPlanesWithLabels = processed.validatedControlPlanes;
  outputEnabledControlPlanes = processed.outputEnabledControlPlanes;
  storageRequiredControlPlanes = processed.storageRequiredControlPlanes;
  storageRequiredGroups = processed.storageRequiredGroups;

  # Check if AWS storage is used anywhere
  usesAWSStorageBackend =
    (any (cp: elem "aws" cp.storage_backend) (attrValues storageRequiredControlPlanes))
    || (any (group: elem "aws" group.groupConfig.storage_backend) storageRequiredGroups);
in
{
  imports = [
    ./certificates
    ./storage
    ./providers.nix
    ./groups
    ./controlPlanes
  ];

  options.kontfix = {
    defaults = {
      storage = {
        aws = {
          cp_prefix = mkOption {
            type = types.str;
            default = "konnect";
            description = "Default prefix for AWS Secrets Manager paths for individual control planes";
          };
          group_prefix = mkOption {
            type = types.str;
            default = "konnect";
            description = "Default prefix for AWS Secrets Manager paths for group system accounts";
          };
          region = mkOption {
            type = types.str;
            default = "";
            description = "Default AWS region (creates aws_region variable with this default if provided)";
          };
          profile = mkOption {
            type = types.str;
            default = "";
            description = "Default AWS profile (creates aws_profile variable with this default if provided)";
          };
        };
        hcv = {
          cp_prefix = mkOption {
            type = types.str;
            default = "konnect";
            description = "Default mount and path prefix for HashiCorp Vault storage for individual control planes";
          };
          group_prefix = mkOption {
            type = types.str;
            default = "konnect";
            description = "Default mount and path prefix for HashiCorp Vault storage for group system accounts";
          };
          address = mkOption {
            type = types.str;
            default = "";
            description = "HashiCorp Vault address (required if using HCV storage backend)";
          };
          auth_method = mkOption {
            type = types.enum [
              "token"
              "approle"
            ];
            default = "token";
            description = "Vault authentication method";
          };
          auth_path = mkOption {
            type = types.str;
            default = "auth/approle/login";
            description = "Vault authentication path (only used for approle auth)";
          };
        };
      };
      pki = {
        hcv = {
          address = mkOption {
            type = types.str;
            default = "";
            description = "HashiCorp Vault address (required if using HCV storage backend)";
          };
          auth_method = mkOption {
            type = types.enum [
              "token"
              "approle"
            ];
            default = "token";
            description = "Vault authentication method";
          };
          auth_path = mkOption {
            type = types.str;
            default = "auth/approle/login";
            description = "Vault authentication path (only used for approle auth)";
          };
        };
      };
      controlPlanes = {
        auth_type = mkOption {
          type = types.str;
          default = "pinned_client_certs";
          description = "Default authentication type for control planes";
        };
        storage_backend = mkOption {
          type = types.listOf types.str;
          default = [ "local" ];
          description = "Default storage backend options for control planes";
        };
        labels = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = "Default labels applied to all control planes";
        };
        pki_backend = mkOption {
          type = types.str;
          default = "hcv";
          description = "Default pki backend to generate certificate for control planes using pki_client_certs auth type";
        };
      };
      pki_ca_certificate = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Default PKI CA certificate used for pki_client_certs authentication. Can be provided as string content or read from a file in the consumer's project directory (e.g., 'builtins.readFile ./pki-ca/ca.pem;').";
      };
      vault_pki = {
        backend = mkOption {
          type = types.str;
          default = "rsa";
          description = "Vault PKI backend name";
        };
        role_name = mkOption {
          type = types.str;
          default = "client-cert";
          description = "Vault PKI role name";
        };
        ttl = mkOption {
          type = types.str;
          default = "2160h";
          description = "Certificate TTL (90 days default)";
        };
        auto_renew = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to auto-renew certificates";
        };
        min_seconds_remaining = mkOption {
          type = types.int;
          default = 604800;
          description = "Minimum seconds remaining before renewal";
        };
      };
      self_signed_cert = {
        validity_period_days = mkOption {
          type = types.int;
          default = 90;
          description = "The validity period of self-signed certificates in days. Default is 90 days (3 months).";
        };
        renewal_days_before_expiry = mkOption {
          type = types.int;
          default = 15;
          description = "Number of days before certificate expiry to trigger renewal. Default is 15 days before expiry.";
        };
      };
    };
  };

  config = mkMerge [
    {
      variable =
        let
          # Always required variables
          requiredVars = {
            cp_admin_token = {
              type = "string";
              description = "Kong control plane admin token";
              sensitive = true;
            };
            id_admin_token = mkIf (processed.individualSystemAccountPlanes != { } || cfg.groups != { }) {
              type = "string";
              description = "Kong identity admin token";
              sensitive = true;
            };
          };

          # AWS variables
          awsStoragePlanes = processed.awsStorageControlPlanes;
          awsVars = mkMerge [
            (mkIf (cfg.defaults.storage.aws.region != "" && cfg.defaults.storage.aws.profile != "") {
              aws_region = {
                type = "string";
                description = "AWS default region";
                default = cfg.defaults.storage.aws.region;
              };
              aws_profile = {
                type = "string";
                description = "AWS default profile";
                default = cfg.defaults.storage.aws.profile;
              };
            })
            (mkIf
              (
                usesAWSStorageBackend
                && (cfg.defaults.storage.aws.region == "" || cfg.defaults.storage.aws.profile == "")
              )
              {
                aws_region = {
                  type = "string";
                  description = "AWS default region";
                };
                aws_profile = {
                  type = "string";
                  description = "AWS default profile";
                };
              }
            )
          ];

          # HCV storage variables
          hcvStoragePlanes = processed.hcvStorageControlPlanes;
          # HCV PKI control planes
          hcvPkiPlanes = filterAttrs (
            name: cp: cp.create_certificate or false && cp.pki_backend == "hcv"
          ) processed.pkiCertControlPlanes;

          hcvVars = mkIf (hcvStoragePlanes != { } && cfg.defaults.storage.hcv.address != "") {
            vault_token = mkIf (cfg.defaults.storage.hcv.auth_method == "token") {
              type = "string";
              description = "HashiCorp Vault token";
              sensitive = true;
            };
            vault_role_id = mkIf (cfg.defaults.storage.hcv.auth_method == "approle") {
              type = "string";
              description = "HashiCorp Vault role ID for AppRole authentication";
              sensitive = true;
            };
            vault_secret_id = mkIf (cfg.defaults.storage.hcv.auth_method == "approle") {
              type = "string";
              description = "HashiCorp Vault secret ID for AppRole authentication";
              sensitive = true;
            };
          };

          hcvPkiVars = mkIf (hcvPkiPlanes != { } && cfg.defaults.pki.hcv.address != "") {
            vault_pki_token = mkIf (cfg.defaults.pki.hcv.auth_method == "token") {
              type = "string";
              description = "HashiCorp Vault token for PKI certificate generation";
              sensitive = true;
            };
            vault_pki_role_id = mkIf (cfg.defaults.pki.hcv.auth_method == "approle") {
              type = "string";
              description = "HashiCorp Vault role ID for PKI AppRole authentication";
              sensitive = true;
            };
            vault_pki_secret_id = mkIf (cfg.defaults.pki.hcv.auth_method == "approle") {
              type = "string";
              description = "HashiCorp Vault secret ID for PKI AppRole authentication";
              sensitive = true;
            };
          };
        in
        mkMerge [
          requiredVars
          awsVars
          hcvVars
          hcvPkiVars
        ];
    }

    (mkIf (cfg.controlPlanes != { }) {
      # Make storage defaults, utils, and processed context available to all submodules
      _module.args = {
        storageDefaults = cfg.defaults.storage;
        inherit utils;
        # Pass the processed context so submodules can use it too
        sharedContext = processed;
      };

      # Control plane resources
      resource.konnect_gateway_control_plane = mapAttrs (
        name: cp:
        let
          providerAlias = "konnect.${cp.region}";
        in
        {
          provider = providerAlias;
          name = cp.originalName;
          description = cp.description;
          labels = cp.labels;
          cluster_type = cp.cluster_type;
          auth_type = cp.auth_type;
        }
      ) controlPlanesWithLabels;

      # Individual system accounts
      resource.konnect_system_account = mapAttrs (name: cp: {
        provider = "konnect.id_admin";
        name = "${name}-system-account";
        description = "System Account for ${cp.originalName} Control Plane in ${cp.region} region";
        konnect_managed = false;
      }) processed.individualSystemAccountPlanes;

      # Individual system account role assignments
      resource.konnect_system_account_role = mapAttrs (name: cp: {
        provider = "konnect.id_admin";
        entity_id = "\${konnect_gateway_control_plane.${name}.id}";
        entity_region = cp.region;
        entity_type_name = "Control Planes";
        role_name = "Admin";
        account_id = "\${konnect_system_account.${name}.id}";
      }) processed.individualSystemAccountPlanes;

      # Individual system account token rotation
      resource.time_rotating =
        let
          planesWithTokens = filterAttrs (
            name: cp: cp.system_account.generate_token or false
          ) processed.individualSystemAccountPlanes;
        in
        mapAttrs (name: cp: {
          rotation_days = 23;
        }) (mapAttrs' (name: cp: nameValuePair "${name}_individual_token" cp) planesWithTokens);

      # Individual system account access tokens
      resource.konnect_system_account_access_token =
        let
          planesWithTokens = filterAttrs (
            name: cp: cp.system_account.generate_token or false
          ) processed.individualSystemAccountPlanes;
        in
        mapAttrs (name: cp: {
          provider = "konnect.id_admin";
          name = "TF Managed Token for CP ${cp.originalName} in ${cp.region} region";
          expires_at = "\${timeadd(time_rotating.${name}_individual_token.rotation_rfc3339, \"168h\")}";
          account_id = "\${konnect_system_account.${name}.id}";
          lifecycle = [
            {
              replace_triggered_by = [
                "time_rotating.${name}_individual_token"
              ];
            }
          ];
        }) planesWithTokens;

      # Control plane memberships
      resource.konnect_gateway_control_plane_membership = mapAttrs (name: cp: {
        provider = "konnect.${cp.region}";
        id = "\${konnect_gateway_control_plane.${name}.id}";
        members = map (member: {
          id = "\${konnect_gateway_control_plane.${cp.region}-${member}.id}";
        }) cp.members;
      }) (filterAttrs (name: cp: cp.members != [ ]) controlPlanesWithLabels);

      # Custom plugin schemas
      resource.konnect_gateway_custom_plugin_schema =
        let
          pluginMappings = flatten (
            mapAttrsToList (
              name: cp:
              map (plugin: {
                cp_name = name;
                cp_region = cp.region;
                plugin_name = plugin;
              }) cp.custom_plugins
            ) (filterAttrs (name: cp: cp.custom_plugins != [ ]) controlPlanesWithLabels)
          );
          pluginSchemas = listToAttrs (
            map (mapping: {
              name = "${mapping.cp_name}_${mapping.plugin_name}";
              value = {
                provider = "konnect.${mapping.cp_region}";
                control_plane_id = "\${konnect_gateway_control_plane.${mapping.cp_name}.id}";
                lua_schema = "\${file(\"\${path.module}/custom-plugin-schemas/${mapping.plugin_name}.lua\")}";
              };
            }) pluginMappings
          );
        in
        pluginSchemas;

      output = mkIf (outputEnabledControlPlanes != { }) {
        control_plane = {
          value = mapAttrs (name: cp: "\${konnect_gateway_control_plane.${name}}") outputEnabledControlPlanes;
          description = "Control planes details output";
        };
      };
    })
  ];
}
