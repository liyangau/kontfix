{ terranix }:

{
  # Main kontfix configuration function that wraps terranix
  kontfixConfiguration =
    {
      system,
      modules ? [ ],
      ...
    }:
    terranix.lib.terranixConfiguration {
      inherit system;
      modules = [
        # Always include the base kontfix module
        ../. # Reference the parent kontfix module directory
      ]
      ++ modules;
    };
}
