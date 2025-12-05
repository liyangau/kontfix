{ lib, ... }:
{
  kontfix.controlPlanes = {
    us = {
      # Individual control planes
      cp1 = {
        cluster_type = "CLUSTER_TYPE_CONTROL_PLANE";
        auth_type = "pinned_client_certs";
        create_certificate = false; # Members of groups shouldn't create certificates
        system_account.enable = false;
        storage_backend = [ "local" ];
      };

      cp2 = {
        cluster_type = "CLUSTER_TYPE_CONTROL_PLANE";
        auth_type = "pinned_client_certs";
        create_certificate = false; # Members of groups shouldn't create certificates
        system_account.enable = false;
        storage_backend = [ "local" ];
      };

      # Groups that reference each other creating a cycle
      groupA = {
        cluster_type = "CLUSTER_TYPE_CONTROL_PLANE_GROUP";
        auth_type = "pinned_client_certs";
        create_certificate = false;
        system_account.enable = false;
        storage_backend = [ "local" ];
        members = [
          "cp1"
          "groupB"
        ];
      };

      groupB = {
        cluster_type = "CLUSTER_TYPE_CONTROL_PLANE_GROUP";
        auth_type = "pinned_client_certs";
        create_certificate = false;
        system_account.enable = false;
        storage_backend = [ "local" ];
        members = [
          "cp2"
          "groupA"
        ];
      };
    };
  };
}
