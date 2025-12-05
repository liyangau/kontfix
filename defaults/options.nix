{ lib, ... }:
with lib;
{
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
        description = "Default PKI CA certificate used for pki_client_certs authentication. Can be provided as string content or read from a file (e.g., 'builtins.readFile ./pki-ca/ca.pem;').";
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
          default = 604800; # 7 days
          description = "Minimum seconds remaining before renewal";
        };
      };
      self_signed_cert = {
        validity_period = mkOption {
          type = types.int;
          default = 90;
          description = "The validity period of self-signed certificates in days. Default is 90 days (3 months).";
        };
        renewal_before_expiry = mkOption {
          type = types.int;
          default = 15;
          description = "Number of days before certificate expiry to trigger renewal. Default is 15 days before expiry.";
        };
      };
      system_account_tokens = {
        validity_period = mkOption {
          type = types.int;
          default = 30;
          description = "The validity period of system account access tokens in days. Default is 30 days.";
        };
        renewal_before_expiry = mkOption {
          type = types.int;
          default = 7;
          description = "Number of days before token expiry to trigger renewal. Default is 7 days before expiry.";
        };
      };
    };
  };
}
