{
  kontfix.controlPlanes.us = {
      # Individual control plane with store_cluster_config = true that is a member of a group (should fail)
      cp1.store_cluster_config = true;
      groupA = {
        cluster_type = "CLUSTER_TYPE_CONTROL_PLANE_GROUP";
        members = [
          "cp1"  # This member has store_cluster_config = true, should cause validation error
        ];
      };
    };
}