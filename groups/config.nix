{ config, lib, sharedContext, ... }:
with lib;
let
  cfg = config.kontfix;

  storageRequiredGroups = sharedContext.storageRequiredGroups;
  flattenedGroups = sharedContext.flattenedGroups;
in
{
  config = mkIf (cfg.groups != { }) {

    resource.konnect_system_account = listToAttrs (
      map (group: {
        name = group.groupName;
        value = {
          provider = "konnect.id_admin";
          name = group.groupName;
          description = "Group System Account for ${group.groupName} (manages: ${concatStringsSep ", " group.groupConfig.members})";
          konnect_managed = false;
        };
      }) flattenedGroups
    );

    resource.konnect_system_account_role = listToAttrs (
      flatten (
        map (
          group:
          map (memberName: {
            name = "${group.groupName}-${memberName}-group-role";
            value = {
              provider = "konnect.id_admin";
              entity_id = "\${konnect_gateway_control_plane.${group.regionName}-${memberName}.id}";
              entity_region = group.regionName;
              entity_type_name = "Control Planes";
              role_name = "Admin";
              account_id = "\${konnect_system_account.${group.groupName}.id}";
            };
          }) group.groupConfig.members
        ) flattenedGroups
      )
    );

    # Group token rotation
    resource.time_rotating =
      let
        rotationDays = cfg.defaults.system_account_tokens.validity_period - cfg.defaults.system_account_tokens.renewal_before_expiry;
      in
      listToAttrs (
        map (group: {
          name = "${group.groupName}_group_token";
          value = {
            rotation_days = rotationDays;
          };
        }) storageRequiredGroups
      );

    # Group system account access tokens
    resource.konnect_system_account_access_token =
      let
        renewalHours = cfg.defaults.system_account_tokens.renewal_before_expiry * 24;
      in
      listToAttrs (
        map (group: {
          name = group.groupName;
          value = {
            provider = "konnect.id_admin";
            name = "${group.groupName} Group TF Managed Token";
            expires_at = "\${timeadd(time_rotating.${group.groupName}_group_token.rotation_rfc3339, \"${toString renewalHours}h\")}"; # add renewal_before_expiry days to rotation time
            account_id = "\${konnect_system_account.${group.groupName}.id}";
            lifecycle = [
              {
                replace_triggered_by = [
                  "time_rotating.${group.groupName}_group_token"
                ];
              }
            ];
          };
        }) storageRequiredGroups
      );
  };
}