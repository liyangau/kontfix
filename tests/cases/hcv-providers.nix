{
  kontfix = {
    defaults = {
      storage = {
        hcv = {
          address = "https://vault.example.com";
          auth_method = "token";
        };
      };
      pki = {
        hcv = {
          address = "https://vault.example.com";
          auth_method = "approle";
          auth_path = "auth/pki/login";
        };
      };
    };
    controlPlanes = {
      au = {
        test = {
          storage_backend = [ "local" ];
        };
      };
    };
  };
}
