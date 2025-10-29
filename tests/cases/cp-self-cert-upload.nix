{
  kontfix = {
    controlPlanes = {
      au = {
        test = {
          create_certificate = true;
          storage_backend = [ "local" ];
          auth_type = "pinned_client_certs";
          upload_ca_certificate = true;
        };
      };
    };
  };
}
