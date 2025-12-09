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

  # Get control planes that need PKI certificate generation and use HCV backend
  hcvPkiPlanes = sharedContext.hcvPkiCertControlPlanes;

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
      if (sharedContext.individualSystemAccountPlanes != { } || groups != { } || config.kontfix.defaults.enable_id_admin) then
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

  # Get control planes that use local storage AND need certificate generation
  localStorageCertPlanes = filterAttrs (name: cp: cp.create_certificate or false) localStoragePlanes;

  # Check if local storage backend is used by any storage-requiring control planes or groups
  usesLocalStorageBackend =
    (any (cp: elem "local" cp.storage_backend) (attrValues storageRequiredControlPlanes))
    || (any (group: elem "local" group.groupConfig.storage_backend) storageRequiredGroups);

  # TLS provider needed for certificate generation with local storage
  needsTlsProvider = localStorageCertPlanes != { };

  # null and time providers needed for any local storage usage (certificates or tokens)
  needsNullAndTimeProviders = usesLocalStorageBackend;

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

  # Get groups using AWS storage - use pre-computed!
  awsGroups = filterAttrs (
    regionName: regionGroups:
    filterAttrs (
      groupName: groupConfig: elem "aws" groupConfig.storage_backend && (groupConfig.aws.enable or false)
    ) regionGroups != { }
  ) groups;

  # Generate AWS provider configurations for each group using AWS storage
  awsGroupProviders = mkIf (awsGroups != { }) (
    flatten (
      attrValues (
        mapAttrs (
          regionName: regionGroups:
          attrValues (
            mapAttrs (
              groupName: groupConfig:
              mkIf (elem "aws" groupConfig.storage_backend && (groupConfig.aws.enable or false)) {
                alias = "${regionName}-group-${groupName}";
                profile = "\${var.aws_profile}";
                region = "\${var.aws_region}";
              }
            ) regionGroups
          )
        ) awsGroups
      )
    )
  );

  # Get groups using HCV storage
  hcvGroups = filterAttrs (
    regionName: regionGroups:
    filterAttrs (groupName: groupConfig: elem "hcv" groupConfig.storage_backend) regionGroups != { }
  ) groups;

  # Get groups using local storage
  localStorageGroups = sharedContext.localStorageGroups;

  # Generate Vault PKI provider if session is configured in defaults.pki.hcv
  vaultPkiProvider = mkIf (pkiConfig.hcv.address != "") (
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

  # Generate Vault storage provider if session is configured in defaults.storage.hcv
  vaultStorageProvider = mkIf (storageConfig.hcv.address != "") (
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
        (needsStorageResources && (awsStoragePlanes != { } || awsGroups != { } || awsProviderPlanes != { }))
        {
          aws = {
            source = "hashicorp/aws";
            version = providerVersions.aws;
          };
        }
      )
      # Vault providers are now based on defaults configuration, not usage
      (mkIf (storageConfig.hcv.address != "" || pkiConfig.hcv.address != "") {
        vault = {
          source = "hashicorp/vault";
          version = providerVersions.vault;
        };
      })
      (mkIf (needsStorageResources && (localStoragePlanes != { } || localStorageGroups != [ ])) {
        local = {
          source = "hashicorp/local";
          version = providerVersions.local;
        };
      })
      # null and time providers needed for any local storage usage
      (mkIf needsNullAndTimeProviders {
        null = {
          source = "hashicorp/null";
          version = providerVersions.null;
        };
        time = {
          source = "hashicorp/time";
          version = providerVersions.time;
        };
      })
      # TLS provider needed specifically for certificate generation with local storage
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
        # Collect all Vault providers that need to be configured based on defaults configuration
        vaultProviders =
          (if (storageConfig.hcv.address != "") then [ vaultStorageProvider ] else [ ])
          ++ (if (pkiConfig.hcv.address != "") then [ vaultPkiProvider ] else [ ]);
      in
      mkMerge [
        { konnect = konnectProviders; }
        (mkIf (needsStorageResources && awsProviderPlanes != { }) {
          aws = awsProviders;
        })
        (mkIf (needsStorageResources && awsGroups != { }) {
          aws = awsGroupProviders;
        })
        (mkIf (vaultProviders != [ ]) {
          vault = vaultProviders;
        })
      ];
  };
}
