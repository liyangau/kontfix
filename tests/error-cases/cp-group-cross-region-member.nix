{
  kontfix.controlPlanes = {
    # Member control plane defined in the au region
    au = {
      test = { };
    };
    # Group defined in the us region trying to reference the au member (should fail)
    us = {
      my-group = {
        cluster_type = "CLUSTER_TYPE_CONTROL_PLANE_GROUP";
        members = [ "test" ];
      };
    };
  };
}
