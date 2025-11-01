{
  kontfix = {
    controlPlanes = {
      au = {
        test = {
          create_certificate = true;
          upload_ca_certificate = true;
        };
        demo = {
          create_certificate = true;
          upload_ca_certificate = true;
        };
      };
    };
    groups = {
      au = {
        dev_team = {
          members = [
            "test"
            "demo"
          ];
          generate_token = true;
          storage_backend = [ "aws" ];
          aws = {
            enable = true;
            tags = {
              owner = "liyang";
            };
          };
        };
      };
    };
  };
}
