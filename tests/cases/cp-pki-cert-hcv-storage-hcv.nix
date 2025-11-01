{
  kontfix = {
    defaults = {
      storage = {
        hcv = {
          address = "https://example.com";
          auth_method = "approle";
        };
      };
      pki = {
        hcv = {
          address = "https://example.com";
          auth_method = "token";
        };
      };
    };
    controlPlanes = {
      au = {
        test = {
          create_certificate = true;
          auth_type = "pki_client_certs";
          storage_backend = [ "hcv" ];
        };
      };
    };
  };
}
