{
  config,
  lib,
  utils,
  sharedContext,
  storageDefaults,
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
          (mapAttrs'
            (
              name: group:
              lib.nameValuePair "konnect_${group.groupName}_readonly" {
                provider = "vault.storage";
                name = "konnect_${group.groupName}_readonly";
                policy = "\${data.vault_policy_document.${group.groupName}_readonly.hcl}";
              }
            )
            (
              listToAttrs (
                map (group: {
                  name = group.groupName;
                  value = group;
                }) hcvStorageGroups
              )
            )
          )
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
        groupPolicies =
          mapAttrs'
            (
              name: group:
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
            )
            (
              listToAttrs (
                map (group: {
                  name = group.groupName;
                  value = group;
                }) hcvStorageGroups
              )
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
            data = konnect_system_account_access_token.${name}.token
            expires_at = konnect_system_account_access_token.${name}.expires_at
            created_at = konnect_system_account_access_token.${name}.created_at
          })}";
          custom_metadata = {
            max_versions = 1;
          };
        }
      ) hcvStorageSysAccountControlPlanes)

      # Group system account tokens
      (mapAttrs'
        (
          name: group:
          nameValuePair "${group.groupName}_group_system_token" {
            provider = "vault.storage";
            mount = storageDefaults.hcv.group_prefix;
            name = "${group.regionName}/${group.groupName}/system-token";
            data_json = "\${jsonencode({
            data = konnect_system_account_access_token.${group.groupName}.token
            expires_at = konnect_system_account_access_token.${group.groupName}.expires_at
            created_at = konnect_system_account_access_token.${group.groupName}.created_at
            members = ${builtins.toJSON group.groupConfig.members}
          })}";
            custom_metadata = {
              max_versions = 1;
            };
          }
        )
        (
          listToAttrs (
            map (group: {
              name = group.groupName;
              value = group;
            }) hcvStorageGroups
          )
        )
      )

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
          cluster_prefix = regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]
          cluster_control_plane = \"\${regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}.${cp.region}.cp.konghq.com:443\"
          cluster_server_name = \"\${regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}.${cp.region}.cp.konghq.com\"
          cluster_telemetry_endpoint = \"\${regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}.${cp.region}.tp.konghq.com:443\"
          cluster_telemetry_server_name = \"\${regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}.${cp.region}.tp.konghq.com\"
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
          cluster_prefix = regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]
          cluster_control_plane = \"\${regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}.${cp.region}.cp.konghq.com:443\"
          cluster_server_name = \"\${regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}.${cp.region}.cp.konghq.com\"
          cluster_telemetry_endpoint = \"\${regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}.${cp.region}.tp.konghq.com:443\"
          cluster_telemetry_server_name = \"\${regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}.${cp.region}.tp.konghq.com\"
          })}";
          custom_metadata = {
            max_versions = 1;
          };
        }
      ) hcvStoragePkiCertControlPlanes)
    ];
  };
}
