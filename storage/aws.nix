{
  config,
  lib,
  sharedContext,
  storageDefaults,
  ...
}:

with lib;

let
  cps = config.kontfix.controlPlanes;
  awsStorageControlPlanes = sharedContext.awsStorageControlPlanes;
  awsStorageGroups = sharedContext.awsStorageGroups;
  awsStoragePkiCertControlPlanes = sharedContext.awsStoragePkiCertControlPlanes;
  awsStoragePinnedCertControlPlanes = sharedContext.awsStoragePinnedCertControlPlanes;
  awsStorageSysAccountControlPlanes = sharedContext.awsStorageSysAccountControlPlanes;
in
{
  config = mkIf (cps != { }) {

    # AWS Secrets Manager Storage Resources
    resource.aws_secretsmanager_secret = mkMerge [
      # PKI certificate cluster configurations in AWS
      (mapAttrs' (name: cp: nameValuePair "${name}_pki_cluster_config" {
        provider = "aws.${cp.region}-${cp.originalName}";
        name = "${storageDefaults.aws.cp_prefix}/${name}/cluster-config";
        recovery_window_in_days = 0;
        tags = cp.aws.tags;
      }) awsStoragePkiCertControlPlanes)

      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_pinned_cluster_config" {
          provider = "aws.${cp.region}-${cp.originalName}";
          name = "${storageDefaults.aws.cp_prefix}/${name}/cluster-config";
          recovery_window_in_days = 0;
          tags = cp.aws.tags;
        }
      ) awsStoragePinnedCertControlPlanes)

      # Individual system account tokens
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_system_token" {
          provider = "aws.${cp.region}-${cp.originalName}";
          name = "${storageDefaults.aws.cp_prefix}/${cp.region}/${cp.originalName}/system-token";
          recovery_window_in_days = 0;
          tags = cp.aws.tags;
        }
      ) awsStorageSysAccountControlPlanes)

      # Group system account tokens
      (mapAttrs'
        (
          name: group:
          nameValuePair "${group.groupName}_group_system_token" {
            provider = "aws.${group.regionName}-group-${group.groupName}";
            name = "${storageDefaults.aws.group_prefix}/${group.regionName}/groups/${group.groupName}/system-token";
            recovery_window_in_days = 0;
            tags = group.groupConfig.aws.tags;
          }
        )
        (
          listToAttrs (
            map (group: {
              name = group.groupName;
              value = group;
            }) awsStorageGroups
          )
        )
      )
    ];

    resource.aws_secretsmanager_secret_version = mkMerge [
      # PKI certificate versions
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_pki_cluster_version" {
          provider = "aws.${cp.region}-${cp.originalName}";
          secret_id = "\${aws_secretsmanager_secret.${name}_pki_cluster_config.id}";
          secret_string = "\${jsonencode({
          certificate = \"\${vault_pki_secret_backend_cert.${name}.certificate}\\n\${vault_pki_secret_backend_cert.${name}.issuing_ca}\"
          private_key = vault_pki_secret_backend_cert.${name}.private_key
          cp_id = konnect_gateway_control_plane.${name}.id
          issuing_ca = vault_pki_secret_backend_cert.${name}.issuing_ca
          cluster_url = konnect_gateway_control_plane.${name}.config.control_plane_endpoint
          telemetry_url = konnect_gateway_control_plane.${name}.config.telemetry_endpoint
          cluster_prefix = regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]
          private_cluster_url = \"\${substr(var.aws_region, 0, 2)}.svc.konghq.com/cp/\${regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}\"
          private_telemetry_url = \"\${substr(var.aws_region, 0, 2)}.svc.konghq.com:443/tp/\${regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}\"
          })}";
        }
      ) awsStoragePkiCertControlPlanes)

      # Pinned certificate versions
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_pinned_cluster_version" {
          provider = "aws.${cp.region}-${cp.originalName}";
          secret_id = "\${aws_secretsmanager_secret.${name}_pinned_cluster_config.id}";
          secret_string = "\${jsonencode({
          certificate = tls_self_signed_cert.${name}.cert_pem
          private_key = tls_private_key.${name}.private_key_pem
          cp_id = konnect_gateway_control_plane.${name}.id
          issuing_ca = tls_self_signed_cert.${name}.cert_pem
          cluster_url = konnect_gateway_control_plane.${name}.config.control_plane_endpoint
          telemetry_url = konnect_gateway_control_plane.${name}.config.telemetry_endpoint
          cluster_prefix = regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]
          private_cluster_url = \"\${substr(var.aws_region, 0, 2)}.svc.konghq.com/cp/\${regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}\"
          private_telemetry_url = \"\${substr(var.aws_region, 0, 2)}.svc.konghq.com:443/tp/\${regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]}\"
          })}";
          lifecycle = [
            {
              replace_triggered_by = [
                "time_rotating.${name}_cert"
              ];
            }
          ];
        }
      ) awsStoragePinnedCertControlPlanes)

      # Individual system account token versions
      (mapAttrs' (
        name: cp:
        nameValuePair "${name}_system_token_version" {
          provider = "aws.${cp.region}-${cp.originalName}";
          secret_id = "\${aws_secretsmanager_secret.${name}_system_token.id}";
          secret_string = "\${jsonencode({
          token = konnect_system_account_access_token.${name}.token
          expires_at = konnect_system_account_access_token.${name}.expires_at
          created_at = konnect_system_account_access_token.${name}.created_at
          })}";
        }
      ) awsStorageSysAccountControlPlanes)

      # Group system account token versions
      (mapAttrs'
        (
          name: group:
          nameValuePair "${group.groupName}_group_system_token_version" {
            provider = "aws.${group.regionName}-group-${group.groupName}";
            secret_id = "\${aws_secretsmanager_secret.${group.groupName}_group_system_token.id}";
            secret_string = "\${jsonencode({
            token = konnect_system_account_access_token.${group.groupName}.token
            expires_at = konnect_system_account_access_token.${group.groupName}.expires_at
            created_at = konnect_system_account_access_token.${group.groupName}.created_at
            members = ${builtins.toJSON group.groupConfig.members}
          })}";
          }
        )
        (
          listToAttrs (
            map (group: {
              name = group.groupName;
              value = group;
            }) awsStorageGroups
          )
        )
      )
    ];
  };
}
