{
  kontfix = {
    controlPlanes = {
      us = {
        # Control plane with custom AWS region
        prod = {
          create_certificate = true;
          storage_backend = [ "aws" ];
          aws = {
            enable = true;
            profile = "production";
            region = "us-east-1";
            tags = {
              env = "production";
            };
          };
        };
        
        # Control plane without custom region (uses var.aws_region)
        dev = {
          create_certificate = true;
          storage_backend = [ "aws" ];
          aws = {
            enable = true;
            tags = {
              env = "development";
            };
          };
        };
      };
      
      eu = {
        # Control plane with different custom AWS region
        staging = {
          create_certificate = true;
          storage_backend = [ "aws" ];
          aws = {
            enable = true;
            profile = "staging";
            region = "eu-west-1";
            tags = {
              env = "staging";
            };
          };
        };
      };
    };
  };
}
