{
  kontfix = {
    defaults = {
      storage.hcv = {
        address = "https://vault.example.com";
        auth_method = "token";
      };
      pki.hcv = {
        address = "https://vault.example.com";
        auth_method = "token";
      };
    };
    controlPlanes = {
      us = {
        test-config-hcv = {
          store_cluster_config = true;
          storage_backend = [ "hcv" ];
        };
        test-config-aws = {
          store_cluster_config = true;
          storage_backend = [ "aws" ];
          aws = {
            enable = true;
            tags = {
              Environment = "test";
            };
          };
        };
        test-config-local = {
          store_cluster_config = true;
          storage_backend = [ "local" ];
        };
      };
    };
  };
}
