{
  kontfix = {
    defaults = {
      pki = {
        hcv = {
          address = "https://vault.example.com";
        };
      };
      storage = {
        hcv = {
          address = "https://vault.example.com";
        };
      };
    };
    controlPlanes = {
      au = {
        test = {
          create_certificate = true;
          storage_backend = [ "hcv" ];
        };
      };
    };
  };
}
