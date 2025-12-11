{
  kontfix = {
    defaults = {
      storage = {
        aws = {
          region = "us-east-1";
          profile = "default";
        };
      };
    };
    controlPlanes = {
      us = {
        # This CP doesn't define region/profile, should use defaults from kontfix.defaults
        kfc = {
          create_certificate = true;
          storage_backend = [ "aws" ];
          aws = {
            enable = true;
            tags = {
              env = "staging";
            };
          };
        };
      };
    };
  };
}
