{
  config,
  lib,
  sharedContext,
  storageDefaults,
  makeClusterConfigFields,
  ...
}:

with lib;

let
  cps = config.kontfix.controlPlanes;
  hcvStorageControlPlanes = sharedContext.hcvStorageControlPlanes;
  hcvStorageGroups = sharedContext.hcvStorageGroups;
  hcvStorageSysAccountControlPlanes = sharedContext.hcvStorageSysAccountControlPlanes;
  hcvStoragePinnedCertControlPlanes = sharedContext.hcvStoragePinnedCertControlPlanes;
  hcvStoragePkiCertControlPlanes = sharedContext.hcvStoragePkiCertControlPlanes;
  hcvStorageClusterConfigOnlyControlPlanes = sharedContext.hcvStorageClusterConfigOnlyControlPlanes;
in
{
  config = mkIf (cps != { }) {

    # Vault policies for HCV storage backend
    resource.vault_policy =
      mkIf ((hcvStorageControlPlanes != { }) || (hcvStorageGroups != [ ]))
        (mkMerge [
          # Individual control plane policies
          (mapAttrs' (
            name: cp:
            lib.nameValuePair "konnect_${name}_readonly" {
              provider = "vault.storage";
              name = "konnect_${name}_readonly";
              policy = "\${data.vault_policy_document.${name}_readonly.hcl}";
            }
          ) hcvStorageControlPlanes)

          # Group policies
          (listToAttrs (
            map (group:
              lib.nameValuePair "konnect_${group.groupName}_readonly" {
                provider = "vault.storage";
                name = "konnect_${group.groupName}_readonly";
                policy = "\${data.vault_policy_document.${group.groupName}_readonly.hcl}";
              }
            ) hcvStorageGroups
          ))
        ]);

    # Vault policy documents for HCV storage backend
    data.vault_policy_document = mkIf ((hcvStorageControlPlanes != { }) || (hcvStorageGroups != [ ])) (
      let
        # Individual control plane policies
        individualPolicies = mapAttrs' (
          name: cp:
          lib.nameValuePair "${name}_readonly" {
            provider = "vault.storage";
            rule = [
              {
                path = "${storageDefaults.hcv.cp_prefix}/data/${cp.region}/${cp.originalName}/*";
                capabilities = [ "read" ];
                description = "Allow reading secret contents for control plane ${cp.originalName}";
              }
              {
                path = "${storageDefaults.hcv.cp_prefix}/metadata/${cp.region}/${cp.originalName}/*";
                capabilities = [
                  "read"
                  "list"
                ];
                description = "Allow listing available secrets and viewing their metadata for control plane ${cp.originalName} in ${cp.region}";
              }
            ];
          }
        ) hcvStorageControlPlanes;

        # Group policies
        groupPolicies = listToAttrs (
          map (group:
            lib.nameValuePair "${group.groupName}_readonly" {
              provider = "vault.storage";
              rule = [
                {
                  path = "${storageDefaults.hcv.group_prefix}/data/${group.regionName}/${group.groupName}/*";
                  capabilities = [ "read" ];
                  description = "Allow reading secret contents for group ${group.groupName}";
                }
                {
                  path = "${storageDefaults.hcv.group_prefix}/metadata/${group.regionName}/${group.groupName}/*";
                  capabilities = [
                    "read"
                    "list"
                  ];
                  description = "Allow listing available secrets and viewing their metadata for group ${group.groupName} in ${group.regionName}";
                }
              ];
            }
          ) hcvStorageGroups
        );
      in
      mkMerge [
        individualPolicies
        groupPolicies
      ]
    );

    # HashiCorp Vault (HCV) Storage Resources
    resource.vault_kv_secret_v2 = mkMerge [
      # Individual system account tokens
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_system_token" {
          provider = "vault.storage";
          mount = storageDefaults.hcv.cp_prefix;
          name = "${cp.region}/${cp.originalName}/system-token";
          data_json = "\${jsonencode({
            token = konnect_system_account_access_token.${name}.token
            api_addr = \"https://${cp.region}.api.konghq.com\"
            expires_at = konnect_system_account_access_token.${name}.expires_at
            created_at = konnect_system_account_access_token.${name}.created_at
          })}";
          custom_metadata = {
            max_versions = 1;
          };
        }
      ) hcvStorageSysAccountControlPlanes)

      # Group system account tokens
      (listToAttrs (
        map (group:
          nameValuePair "${group.groupName}_group_system_token" {
            provider = "vault.storage";
            mount = storageDefaults.hcv.group_prefix;
            name = "${group.regionName}/${group.groupName}/system-token";
            data_json = "\${jsonencode({
            token = konnect_system_account_access_token.${group.groupName}.token
            api_addr = \"https://${group.regionName}.api.konghq.com\"
            expires_at = konnect_system_account_access_token.${group.groupName}.expires_at
            created_at = konnect_system_account_access_token.${group.groupName}.created_at
            members = ${builtins.toJSON group.groupConfig.members}
          })}";
            custom_metadata = {
              max_versions = 1;
            };
          }
        ) hcvStorageGroups
      ))

      # Pinned certificate cluster configurations
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_pinned_cluster_config" {
          provider = "vault.storage";
          mount = storageDefaults.hcv.cp_prefix;
          name = "${cp.region}/${cp.originalName}/cluster-config";
          data_json = "\${jsonencode({
          certificate = tls_self_signed_cert.${name}.cert_pem
          private_key = tls_private_key.${name}.private_key_pem
          issuing_ca = tls_self_signed_cert.${name}.cert_pem
          cluster_url = konnect_gateway_control_plane.${name}.config.control_plane_endpoint
          telemetry_url = konnect_gateway_control_plane.${name}.config.telemetry_endpoint
          cp_id = konnect_gateway_control_plane.${name}.id
          ${makeClusterConfigFields { inherit name; region = cp.region; }}
          })}";
          custom_metadata = {
            max_versions = 1;
          };
          lifecycle = [
            {
              replace_triggered_by = [
                "time_rotating.${name}_cert"
              ];
            }
          ];
        }
      ) hcvStoragePinnedCertControlPlanes)

      # PKI certificate cluster configurations
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_pki_cluster_config" {
          provider = "vault.storage";
          mount = storageDefaults.hcv.cp_prefix;
          name = "${cp.region}/${cp.originalName}/cluster-config";
          data_json = "\${jsonencode({
          certificate = \"\${vault_pki_secret_backend_cert.${name}.certificate}\\n\${vault_pki_secret_backend_cert.${name}.issuing_ca}\"
          private_key = vault_pki_secret_backend_cert.${name}.private_key
          issuing_ca = vault_pki_secret_backend_cert.${name}.issuing_ca
          cluster_url = konnect_gateway_control_plane.${name}.config.control_plane_endpoint
          telemetry_url = konnect_gateway_control_plane.${name}.config.telemetry_endpoint
          cp_id = konnect_gateway_control_plane.${name}.id
          ${makeClusterConfigFields { inherit name; region = cp.region; }}
          })}";
          custom_metadata = {
            max_versions = 1;
          };
        }
      ) hcvStoragePkiCertControlPlanes)

      # Cluster-config only resources (no certificates)
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_cluster_config_only" {
          provider = "vault.storage";
          mount = storageDefaults.hcv.cp_prefix;
          name = "${cp.region}/${cp.originalName}/cluster-config";
          data_json = "\${jsonencode({
          cluster_url = konnect_gateway_control_plane.${name}.config.control_plane_endpoint
          telemetry_url = konnect_gateway_control_plane.${name}.config.telemetry_endpoint
          cp_id = konnect_gateway_control_plane.${name}.id
          ${makeClusterConfigFields { inherit name; region = cp.region; }}
          })}";
          custom_metadata = {
            max_versions = 1;
          };
        }
      ) hcvStorageClusterConfigOnlyControlPlanes)
    ];
  };
}
