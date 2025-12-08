let
  ca = ''
    -----BEGIN CERTIFICATE-----
    ...
    -----END CERTIFICATE-----    
  '';
in
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
          ca_certificate = ca;
          auth_type = "pki_client_certs";
          storage_backend = [ "hcv" ];
        };
      };
    };
  };
}
