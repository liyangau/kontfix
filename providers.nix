{
  config,
  lib,
  sharedContext,
  ...
}:
with lib;
let
  cps = config.kontfix.controlPlanes;
  groups = config.kontfix.groups;
  storageConfig = config.kontfix.defaults.storage;

  # Use configurable provider versions from defaults
  providerVersions = config.kontfix.defaults.provider_versions;

  storageRequiredControlPlanes = sharedContext.storageRequiredControlPlanes;
  storageRequiredGroups = sharedContext.storageRequiredGroups;
  needsStorageResources = storageRequiredControlPlanes != { } || storageRequiredGroups != [ ];

  # PKI configuration (for certificate generation)
  pkiConfig = config.kontfix.defaults.pki;

  # Generate dynamic provider configurations for each region
  konnectProviders =
    (map (region: {
      alias = region;
      personal_access_token = "\${var.cp_admin_token}";
      server_url = "https://${region}.api.konghq.com";
    }) (attrNames cps))
    ++ (
      if
        (
          sharedContext.individualSystemAccountPlanes != { }
          || groups != { }
          || config.kontfix.defaults.enable_id_admin
        )
      then
        [
          {
            alias = "id_admin";
            personal_access_token = "\${var.id_admin_token}";
            server_url = "https://global.api.konghq.com";
          }
        ]
      else
        [ ]
    );

  # Get control planes using specific storage backends
  awsStoragePlanes = sharedContext.awsStorageControlPlanes;
  awsProviderPlanes = sharedContext.awsProviderRequiredControlPlanes;
  hcvStoragePlanes = sharedContext.hcvStorageControlPlanes;
  localStoragePlanes = sharedContext.localStorageControlPlanes;

  # Check if local storage backend is used by any storage-requiring control planes or groups
  usesLocalStorageBackend =
    (any (cp: elem "local" cp.storage_backend) (attrValues storageRequiredControlPlanes))
    || (any (group: elem "local" group.groupConfig.storage_backend) storageRequiredGroups);

  # TLS provider is needed for any pinned-cert control plane that creates a self-signed
  # certificate, regardless of storage backend (certificates/pinned.nix emits tls_private_key
  # and tls_self_signed_cert for every such control plane).
  needsTlsProvider = sharedContext.pinnedCertControlPlanes != { };

  # null provider is only needed for the null_resource directory creation in
  # storage/local.nix, so it stays gated on local storage usage.
  needsNullProvider = usesLocalStorageBackend;

  # time provider is needed for time_rotating resources, which are created for
  # certificate lifecycle (certificates/pinned.nix), individual system account
  # tokens (defaults/config.nix), and group tokens (groups/config.nix) — all of
  # which are subsets of needsStorageResources, regardless of storage backend.
  needsTimeProvider = needsStorageResources;

  # Generate AWS provider configurations for each control plane that needs AWS providers
  awsProviders = mkIf (awsProviderPlanes != { }) (
    attrValues (
      mapAttrs (name: cp: {
        alias = "${cp.region}-${cp.originalName}";
        profile = if cp.aws.profile != "" then cp.aws.profile else "\${var.aws_profile}";
        region = if cp.aws.region != "" then cp.aws.region else "\${var.aws_region}";
      }) awsProviderPlanes
    )
  );

  # Generate AWS provider configurations for each group using AWS storage
  awsGroupProviders = mkIf (sharedContext.awsStorageGroups != [ ]) (
    map (group: {
      alias = "${group.regionName}-group-${group.originalName}";
      profile =
        if group.computedAwsProfile != null then group.computedAwsProfile else "\${var.aws_profile}";
      region = if group.computedAwsRegion != null then group.computedAwsRegion else "\${var.aws_region}";
    }) sharedContext.awsStorageGroups
  );

  # Get groups using local storage
  localStorageGroups = sharedContext.localStorageGroups;

  # Generate Vault PKI provider only when a control plane actually uses HCV PKI
  # (pki auth + create_certificate). Gating on address alone emits a provider that
  # references vault_pki_* variables which are only declared for hcvPkiCertControlPlanes.
  vaultPkiProvider =
    mkIf (sharedContext.hcvPkiCertControlPlanes != { } && pkiConfig.hcv.address != "")
      (
        if pkiConfig.hcv.auth_method == "token" then
          {
            alias = "pki";
            address = pkiConfig.hcv.address;
            token = "\${var.vault_pki_token}";
          }
        else if pkiConfig.hcv.auth_method == "approle" then
          {
            alias = "pki";
            address = pkiConfig.hcv.address;
            auth_login = {
              path = pkiConfig.hcv.auth_path;
              parameters = {
                role_id = "\${var.vault_pki_role_id}";
                secret_id = "\${var.vault_pki_secret_id}";
              };
            };
          }
        else
          { }
      );

  # Generate Vault storage provider when a control plane actually uses HCV storage.
  # Gating on address alone emits a provider referencing vault_token / vault_role_id
  # which are only declared for hcvStorageControlPlanes (see defaults/config.nix).
  vaultStorageProvider =
    mkIf (sharedContext.hcvStorageControlPlanes != { } && storageConfig.hcv.address != "")
      (
        if storageConfig.hcv.auth_method == "token" then
          {
            alias = "storage";
            address = storageConfig.hcv.address;
            token = "\${var.vault_token}";
          }
        else if storageConfig.hcv.auth_method == "approle" then
          {
            alias = "storage";
            address = storageConfig.hcv.address;
            auth_login = {
              path = storageConfig.hcv.auth_path;
              parameters = {
                role_id = "\${var.vault_role_id}";
                secret_id = "\${var.vault_secret_id}";
              };
            };
          }
        else
          { }
      );
in
{
  config = mkIf (cps != { }) {
    # Required providers for control plane functionality
    terraform.required_providers = mkMerge [
      # Always required providers
      {
        konnect = {
          source = "Kong/konnect";
          version = providerVersions.konnect;
        };
      }
      # Conditional providers based on storage requirements or cleanup needs
      (mkIf
        (
          needsStorageResources
          && (awsStoragePlanes != { } || sharedContext.awsStorageGroups != [ ] || awsProviderPlanes != { })
        )
        {
          aws = {
            source = "hashicorp/aws";
            version = providerVersions.aws;
          };
        }
      )
      # Vault providers are gated on actual usage so they never reference
      # undeclared variables (vault_token / vault_pki_token).
      (mkIf (sharedContext.hcvStorageControlPlanes != { } || sharedContext.hcvPkiCertControlPlanes != { })
        {
          vault = {
            source = "hashicorp/vault";
            version = providerVersions.vault;
          };
        }
      )
      (mkIf (needsStorageResources && (localStoragePlanes != { } || localStorageGroups != [ ])) {
        local = {
          source = "hashicorp/local";
          version = providerVersions.local;
        };
      })
      # null provider only needed for local storage directory creation
      (mkIf needsNullProvider {
        null = {
          source = "hashicorp/null";
          version = providerVersions.null;
        };
      })
      # time provider needed for time_rotating (cert/token rotation, any backend)
      (mkIf needsTimeProvider {
        time = {
          source = "hashicorp/time";
          version = providerVersions.time;
        };
      })
      # TLS provider needed for any pinned-cert control plane that creates a
      # self-signed certificate (certificates/pinned.nix), regardless of backend
      (mkIf needsTlsProvider {
        tls = {
          source = "hashicorp/tls";
          version = providerVersions.tls;
        };
      })
    ];
    # Control plane-specific providers
    provider =
      let
        # Collect Vault providers that have actual consumers (matches the
        # required_providers gate and the variable declarations in defaults/config.nix).
        vaultProviders =
          (
            if (sharedContext.hcvStorageControlPlanes != { } && storageConfig.hcv.address != "") then
              [ vaultStorageProvider ]
            else
              [ ]
          )
          ++ (
            if (sharedContext.hcvPkiCertControlPlanes != { } && pkiConfig.hcv.address != "") then
              [ vaultPkiProvider ]
            else
              [ ]
          );
      in
      mkMerge [
        { konnect = konnectProviders; }
        (mkIf (needsStorageResources && awsProviderPlanes != { }) {
          aws = awsProviders;
        })
        (mkIf (needsStorageResources && sharedContext.awsStorageGroups != [ ]) {
          aws = awsGroupProviders;
        })
        (mkIf (vaultProviders != [ ]) {
          vault = vaultProviders;
        })
      ];
  };
}
