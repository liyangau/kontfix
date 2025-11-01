{
  config,
  lib,
  sharedContext,
  ...
}:

with lib;

let
  cfg = config.kontfix;

  storageRequiredGroups = sharedContext.storageRequiredGroups;
  flattenedGroups = sharedContext.flattenedGroups;

  groupSubmodule = types.submodule {
    options = {
      members = mkOption {
        type = types.listOf types.str;
        description = "List of control plane names to include in this group";
      };

      generate_token = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to generate and store a system account token for this group";
      };

      storage_backend = mkOption {
        type = types.listOf (
          types.enum [
            "local"
            "hcv"
            "aws"
          ]
        );
        default = [ "hcv" ];
        description = "Storage backend(s) for group system account token";
      };

      aws = mkOption {
        type = types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = "Whether to enable AWS provider";
            };
            profile = mkOption {
              type = types.str;
              default = "";
              description = "AWS profile name to use";
            };
            region = mkOption {
              type = types.str;
              default = "";
              description = "AWS region for resources";
            };
            tags = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = "AWS tags to apply when using AWS storage backend";
            };
          };
        };
        default = { };
        description = "AWS provider configuration for group system account token storage";
      };
    };
  };

in
{
  options.kontfix = {
    groups = mkOption {
      type = types.attrsOf (types.attrsOf groupSubmodule);
      default = { };
      description = "System account groups organized by region (groups.region.groupName)";
      example = {
        us = {
          dev = {
            members = [
              "dev-app"
              "dev-db"
            ];
            generate_token = true;
            storage_backend = [ "hcv" ];
          };
        };
        au = {
          staging = {
            members = [
              "staging-web"
              "staging-api"
            ];
            generate_token = true;
            storage_backend = [ "aws" ];
            aws.tags = {
              environment = "staging";
              team = "platform";
            };
          };
        };
      };
    };
  };

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
    resource.time_rotating = listToAttrs (
      map (group: {
        name = "${group.groupName}_group_token";
        value = {
          rotation_days = 23; # Rotate after 23 days (7 days before 30-day expiry)
        };
      }) storageRequiredGroups
    );

    # Group system account access tokens
    resource.konnect_system_account_access_token = listToAttrs (
      map (group: {
        name = group.groupName;
        value = {
          provider = "konnect.id_admin";
          name = "${group.groupName} Group TF Managed Token";
          expires_at = "\${timeadd(time_rotating.${group.groupName}_group_token.rotation_rfc3339, \"168h\")}"; # add 7 days to rotation time
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
