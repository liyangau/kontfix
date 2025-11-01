{
  kontfix = {
    defaults = {
      storage = {
        aws = {
          cp_prefix = "test";
          group_prefix = "test-group";
          region = "us-west-1";
          profile = "test";
        };
        hcv = {
          address = "https://example.com";
          auth_method = "approle";
          auth_path = "auth/kong-approle/login";
          cp_prefix = "test";
          group_prefix = "test-group";
        };
      };
      pki = {
        hcv = {
          address = "https://example.com";
          auth_method = "token";
        };
      };
      controlPlanes = {
        auth_type = "pki_client_certs";
        storage_backend = [ "hcv" ];
        labels = {
          provisioner = "terraform";
          generator = "terranix";
        };
      };
      vault_pki = {
        backend = "kong-pki";
        role_name = "kong-role";
        ttl = "168h";
        auto_renew = true;
        min_seconds_remaining = 3600;
      };
      self_signed_cert = {
        validity_period = 7;
        renewal_before_expiry = 3;
      };
      system_account_tokens = {
        validity_period = 15;
        renewal_before_expiry = 5;
      };
    };
    controlPlanes = {
      au = {
        test-aws = {
          create_certificate = true;
          storage_backend = [ "aws" ];
          aws = {
            enable = true;
            tags = {
              owner = "fomm";
            };
          };
        };
        test-hcv = {
          create_certificate = true;
          storage_backend = [ "hcv" ];
        };
        test-self-signed = {
          auth_type = "pinned_client_certs";
          create_certificate = true;
          storage_backend = [ "local" ];
        };
      };
    };
    groups = {
      au = {
        dev_team = {
          members = [
            "test-hcv"
            "test-self-signed"
          ];
          generate_token = true;
          storage_backend = [
            "local"
            "aws"
            "hcv"
          ];
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
