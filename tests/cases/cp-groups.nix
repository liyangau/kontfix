{
  kontfix = {
    controlPlanes = {
      au = {
        test = {
          system_account = {
            enable = true;
            generate_token = true;
          };
        };
        demo = {
          system_account = {
            enable = true;
            generate_token = true;
          };
        };
        dev-cpg = {
          create_certificate = true;
          upload_ca_certificate = true;
          cluster_type = "CLUSTER_TYPE_CONTROL_PLANE_GROUP";
          members = [
            "test"
            "demo"
          ];
        };
      };
    };
  };
}
