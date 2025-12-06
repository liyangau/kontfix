{
  kontfix.controlPlanes.us = {
    # Individual control planes
    cp1 = { };

    # First control plane group
    groupA = {
      cluster_type = "CLUSTER_TYPE_CONTROL_PLANE_GROUP";
      members = [
        "cp1"
      ];
    };

    # Second control plane group that tries to include the first group as a member (should fail)
    groupB = {
      cluster_type = "CLUSTER_TYPE_CONTROL_PLANE_GROUP";
      members = [
        "groupA" # This should cause validation error - groups cannot be members of other groups
      ];
    };
  };
}
