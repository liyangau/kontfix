{
  kontfix = {
    controlPlanes = {
      au = {
        test = {
          storage_backend = [ "aws" ];
          system_account = {
            enable = true;
            generate_token = true;
          };
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
