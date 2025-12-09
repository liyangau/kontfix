{
  config,
  lib,
  sharedContext,
  ...
}:

with lib;

let
  cps = config.kontfix.controlPlanes;
  localStorageControlPlanes = sharedContext.localStorageControlPlanes;
  localStorageGroups = sharedContext.localStorageGroups;
  localStoragePkiCertControlPlanes = sharedContext.localStoragePkiCertControlPlanes;
  localStoragePinnedCertControlPlanes = sharedContext.localStoragePinnedCertControlPlanes;
  localStorageSysAccountControlPlanes = sharedContext.localStorageSysAccountControlPlanes;
  localStorageClusterConfigOnlyControlPlanes = sharedContext.localStorageClusterConfigOnlyControlPlanes;
in
{
  config = mkIf (cps != { }) {

    # Local File Storage Resources
    resource.null_resource = mkIf ((localStorageControlPlanes != { }) || (localStorageGroups != [ ])) {
      # Create directories
      create_cert_dir =
        mkIf (localStoragePinnedCertControlPlanes != { } || localStoragePkiCertControlPlanes != { })
          {
            provisioner = [
              {
                local-exec = {
                  command = "mkdir -p \${path.module}/certs && chmod 700 \${path.module}/certs";
                };
              }
            ];
          };

      create_token_dir =
        mkIf ((localStorageSysAccountControlPlanes != { }) || (localStorageGroups != [ ]))
          {
            provisioner = [
              {
                local-exec = {
                  command = "mkdir -p \${path.module}/tokens && chmod 700 \${path.module}/tokens";
                };
              }
            ];
          };

      create_clusters_dir =
        mkIf ((localStoragePinnedCertControlPlanes != { }) || (localStoragePkiCertControlPlanes != { }) || (localStorageClusterConfigOnlyControlPlanes != { }))
          {
            provisioner = [
              {
                local-exec = {
                  command = "mkdir -p \${path.module}/clusters && chmod 700 \${path.module}/clusters";
                };
              }
            ];
          };
    };

    resource.local_file = mkMerge [
      # Pinned certificate files
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_pinned_cert" {
          content = "\${tls_self_signed_cert.${name}.cert_pem}";
          filename = "\${path.module}/certs/${name}/cert.pem";
          file_permission = "0444";
          directory_permission = "0755";
          depends_on = [ "null_resource.create_cert_dir" ];
          lifecycle = [
            {
              replace_triggered_by = [
                "time_rotating.${name}_cert"
              ];
            }
          ];
        }
      ) localStoragePinnedCertControlPlanes)

      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_pinned_key" {
          content = "\${tls_private_key.${name}.private_key_pem}";
          filename = "\${path.module}/certs/${name}/key.pem";
          file_permission = "0444";
          directory_permission = "0755";
          depends_on = [ "null_resource.create_cert_dir" ];
        }
      ) localStoragePinnedCertControlPlanes)

      # PKI certificate files
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_pki_cert" {
          content = "\${vault_pki_secret_backend_cert.${name}.certificate}";
          filename = "\${path.module}/certs/${name}/cert.pem";
          file_permission = "0444";
          directory_permission = "0755";
          depends_on = [ "null_resource.create_cert_dir" ];
        }
      ) localStoragePkiCertControlPlanes)

      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_pki_key" {
          content = "\${vault_pki_secret_backend_cert.${name}.private_key}";
          filename = "\${path.module}/certs/${name}/key.pem";
          file_permission = "0444";
          directory_permission = "0755";
          depends_on = [ "null_resource.create_cert_dir" ];
        }
      ) localStoragePkiCertControlPlanes)

      # Individual system account token files
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_token" {
          content = "\${jsonencode({
            token = konnect_system_account_access_token.${name}.token
            api_addr = \"https://${cp.region}.api.konghq.com\"
            expires_at = konnect_system_account_access_token.${name}.expires_at
            created_at = konnect_system_account_access_token.${name}.created_at
          })}";
          filename = "\${path.module}/tokens/${cp.region}_cp_${cp.originalName}.json";
          file_permission = "0444";
          directory_permission = "0755";
          depends_on = [ "null_resource.create_token_dir" ];
        }
      ) localStorageSysAccountControlPlanes)

      # Group system account token files
      (mapAttrs'
        (
          name: group:
          nameValuePair "${group.groupName}_group_token" {
            content = "\${jsonencode({
            token = konnect_system_account_access_token.${group.groupName}.token
            api_addr = \"https://${group.regionName}.api.konghq.com\"
            expires_at = konnect_system_account_access_token.${group.groupName}.expires_at
            created_at = konnect_system_account_access_token.${group.groupName}.created_at
            members = ${builtins.toJSON group.groupConfig.members}
          })}";
            filename = "\${path.module}/tokens/${group.regionName}_group_${group.originalName}.json";
            file_permission = "0444";
            directory_permission = "0755";
            depends_on = [ "null_resource.create_token_dir" ];
          }
        )
        (
          listToAttrs (
            map (group: {
              name = group.groupName;
              value = group;
            }) localStorageGroups
          )
        )
      )

      # Cluster configuration files (consolidated key-value format without certificates)
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_cluster_config" {
          content = ''
            CLUSTER_URL=''${konnect_gateway_control_plane.${name}.config.control_plane_endpoint}
            TELEMETRY_URL=''${konnect_gateway_control_plane.${name}.config.telemetry_endpoint}
            CP_ID=''${konnect_gateway_control_plane.${name}.id}
            CP_CLUSTER_PREFIX=''${regex("^https://([^/.]+)", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}
            CLUSTER_SERVER_NAME=''${replace(konnect_gateway_control_plane.${name}.config.control_plane_endpoint, "https://", "")}
            CLUSTER_TELEMETRY_SERVER_NAME=''${replace(konnect_gateway_control_plane.${name}.config.telemetry_endpoint, "https://", "")}
            CP_REGION=${cp.region}
            CP_NAME=${cp.originalName}
          '';
          filename = "\${path.module}/clusters/${name}";
          file_permission = "0444";
          directory_permission = "0755";
          depends_on = [ "null_resource.create_clusters_dir" ];
          lifecycle = mkIf (localStoragePinnedCertControlPlanes ? name) [
            {
              replace_triggered_by = [
                "time_rotating.${name}_cert"
              ];
            }
          ];
        }
      ) (localStoragePinnedCertControlPlanes // localStoragePkiCertControlPlanes // localStorageClusterConfigOnlyControlPlanes))
    ];
  };
}
