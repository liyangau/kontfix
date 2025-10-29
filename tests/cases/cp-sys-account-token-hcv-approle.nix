{
  kontfix = {
    defaults = {
      storage = {
        hcv = {
          address = "https://example.com";
          auth_method = "approle";
        };
      };
    };
    controlPlanes = {
      au = {
        test = {
          storage_backend = [ "hcv" ];
          system_account = {
            enable = true;
            generate_token = true;
          };
        };
      };
    };
  };
}
