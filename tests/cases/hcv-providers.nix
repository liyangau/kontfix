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
          auth_type = "pki_client_certs";
          create_certificate = true;
          ca_certificate = ca;
          storage_backend = [ "hcv" ];
        };
      };
    };
  };
}
