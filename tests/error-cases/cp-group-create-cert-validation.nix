{
  kontfix.controlPlanes.us = {
    cp1.create_certificate = true;
    groupA = {
      cluster_type = "CLUSTER_TYPE_CONTROL_PLANE_GROUP";
      members = [
        "cp1" # This member has create_certificate = true, should cause validation error
      ];
    };
  };
}
