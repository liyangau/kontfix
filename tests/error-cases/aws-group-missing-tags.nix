{
  kontfix = {
    controlPlanes.us = {
      app = { };
    };
    groups.us.dev = {
      members = [ "app" ];
      generate_token = true;
      storage_backend = [ "aws" ];
      aws = {
        enable = true;
        region = "us-east-1";
        # tags intentionally omitted
      };
    };
  };
}
