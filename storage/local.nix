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
    };

    resource.local_file = mkMerge [
      # Pinned certificate files
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_pinned_cert" {
          content = "\${tls_self_signed_cert.${name}.cert_pem}";
          filename = "\${path.module}/certs/${name}-cert.pem";
          file_permission = "0400";
          directory_permission = "0700";
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
          filename = "\${path.module}/certs/${name}-key.pem";
          file_permission = "0400";
          directory_permission = "0700";
          depends_on = [ "null_resource.create_cert_dir" ];
        }
      ) localStoragePinnedCertControlPlanes)

      # PKI certificate files
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_pki_cert" {
          content = "\${vault_pki_secret_backend_cert.${name}.certificate}";
          filename = "\${path.module}/certs/${name}-pki-cert.pem";
          file_permission = "0400";
          directory_permission = "0700";
          depends_on = [ "null_resource.create_cert_dir" ];
        }
      ) localStoragePkiCertControlPlanes)

      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_pki_key" {
          content = "\${vault_pki_secret_backend_cert.${name}.private_key}";
          filename = "\${path.module}/certs/${name}-pki-key.pem";
          file_permission = "0400";
          directory_permission = "0700";
          depends_on = [ "null_resource.create_cert_dir" ];
        }
      ) localStoragePkiCertControlPlanes)

      # Individual system account token files
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_token" {
          content = "\${jsonencode({
            token = konnect_system_account_access_token.${name}.token
            expires_at = konnect_system_account_access_token.${name}.expires_at
            created_at = konnect_system_account_access_token.${name}.created_at
          })}";
          filename = "\${path.module}/tokens/${cp.region}_cp_${cp.originalName}.json";
          file_permission = "0400";
          directory_permission = "0700";
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
            expires_at = konnect_system_account_access_token.${group.groupName}.expires_at
            created_at = konnect_system_account_access_token.${group.groupName}.created_at
            members = ${builtins.toJSON group.groupConfig.members}
          })}";
            filename = "\${path.module}/tokens/${group.regionName}_group_${group.originalName}.json";
            file_permission = "0400";
            directory_permission = "0700";
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

      # Cluster configuration files
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_pinned_config" {
          content = "\${jsonencode({
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
          filename = "\${path.module}/certs/${name}-cluster-config.json";
          file_permission = "0400";
          directory_permission = "0700";
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
        nameValuePair "${name}_pki_config" {
          content = "\${jsonencode({
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
          filename = "\${path.module}/certs/${name}-pki-cluster-config.json";
          file_permission = "0400";
          directory_permission = "0700";
          depends_on = [ "null_resource.create_cert_dir" ];
        }
      ) localStoragePkiCertControlPlanes)

      # Cluster-config only local file resources (no certificates)
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_cluster_config_only" {
          content = "\${jsonencode({
          cluster_url = konnect_gateway_control_plane.${name}.config.control_plane_endpoint
          telemetry_url = konnect_gateway_control_plane.${name}.config.telemetry_endpoint
          cp_id = konnect_gateway_control_plane.${name}.id
          cluster_prefix = regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]
          cluster_control_plane = \"\${regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}.${cp.region}.cp.konghq.com:443\"
          cluster_server_name = \"\${regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}.${cp.region}.cp.konghq.com\"
          cluster_telemetry_endpoint = \"\${regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}.${cp.region}.tp.konghq.com:443\"
          cluster_telemetry_server_name = \"\${regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}.${cp.region}.tp.konghq.com\"
          })}";
          filename = "\${path.module}/certs/${name}-cluster-config-only.json";
          file_permission = "0400";
          directory_permission = "0700";
          depends_on = [ "null_resource.create_cert_dir" ];
        }
      ) localStorageClusterConfigOnlyControlPlanes)
    ];
  };
}
