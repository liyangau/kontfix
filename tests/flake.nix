{
  inputs = {
    nixpkgs-terraform.url = "github:stackbuilders/nixpkgs-terraform";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    kontfix.url = "path:../modules/kontfix";
  };
  outputs =
    {
      self,
      nixpkgs-terraform,
      nixpkgs,
      systems,
      kontfix,
    }:
    let
      forEachSystem =
        f:
        nixpkgs.lib.genAttrs (import systems) (
          system:
          f {
            inherit system;
            pkgs = nixpkgs.legacyPackages.${system};
          }
        );
      tf_version = "1.13.3";

      testConfigurations =
        let
          caseFiles = builtins.filter (file: nixpkgs.lib.hasSuffix ".nix" file) (
            builtins.attrNames (builtins.readDir ./cases)
          );
        in
        map (file: nixpkgs.lib.removeSuffix ".nix" file) caseFiles;

      # Error test configurations (configs that should fail to build)
      errorTestConfigurations =
        let
          errorCasePath = ./error-cases;
          errorCaseFiles =
            if builtins.pathExists errorCasePath then
              builtins.filter (file: nixpkgs.lib.hasSuffix ".nix" file) (
                builtins.attrNames (builtins.readDir errorCasePath)
              )
            else
              [ ];
        in
        map (file: nixpkgs.lib.removeSuffix ".nix" file) errorCaseFiles;

      # Generic function to create a test configuration
      createTestConfiguration =
        {
          system,
          configName,
          isErrorCase ? false,
        }:
        kontfix.lib.kontfixConfiguration {
          inherit system;
          modules = [
            (if isErrorCase then ./error-cases/${configName}.nix else ./cases/${configName}.nix)
          ];
        };

      # Generic function to create a build app for a test configuration
      createBuildApp =
        {
          pkgs,
          system,
          configName,
        }:
        let
          config = createTestConfiguration { inherit system configName; };
          outputFile = "${configName}.tf.json";
        in
        {
          type = "app";
          program = toString (
            pkgs.writers.writeBash "build-${configName}" ''
              echo "🧪 Building ${configName} configuration..."
              if [[ -e ${outputFile} ]]; then rm -f ${outputFile}; fi
              cp ${config} ${outputFile}
              echo "✅ Generated ${outputFile}"
            ''
          );
        };

      # Create an error test app (expects build to fail with specific message)
      createErrorTestApp =
        {
          pkgs,
          system,
          configName,
        }:
        {
          type = "app";
          program = toString (
            pkgs.writers.writeBash "test-error-${configName}" ''
              echo "🧪 Testing error case: ${configName}"

              # Check if expected error file exists
              if [[ ! -f "./expected-errors/${configName}.txt" ]]; then
                echo "❌ ./expected-errors/${configName}.txt not found."
                exit 1
              fi

              expected_error=$(cat "./expected-errors/${configName}.txt")

              # Try to build (should fail)
              echo "🔨 Attempting to build ${configName} (expecting failure)..."
              build_output=$(nix run .#build-error-${configName} 2>&1 || true)

              # Check if build actually failed
              if nix run .#build-error-${configName} 2>/dev/null; then
                echo "❌ Build succeeded but should have failed!"
                exit 1
              fi

              # Check if error message contains expected text
              if echo "$build_output" | grep -qF "$expected_error"; then
                echo "✅ Build failed with expected error message"
                echo "   Expected: $expected_error"
                exit 0
              else
                echo "❌ Build failed but with unexpected error message"
                echo "   Expected: $expected_error"
                echo "   Actual output:"
                echo "$build_output"
                exit 1
              fi
            ''
          );
        };

      # Create build apps for error cases (these should fail)
      createErrorBuildApp =
        {
          pkgs,
          system,
          configName,
        }:
        let
          config = createTestConfiguration {
            inherit system configName;
            isErrorCase = true;
          };
          outputFile = "error-${configName}.tf.json";
        in
        {
          type = "app";
          program = toString (
            pkgs.writers.writeBash "build-error-${configName}" ''
              echo "🧪 Building error case ${configName} (should fail)..."
              if [[ -e ${outputFile} ]]; then rm -f ${outputFile}; fi
              cp ${config} ${outputFile}
              echo "✅ Generated ${outputFile}"
            ''
          );
        };

      # Create a test validation app for a specific configuration using Python
      createTestApp =
        {
          pkgs,
          system,
          configName,
        }:
        let
          # Python validator script with enhanced dependencies (no linting)
          pythonWithDeps = pkgs.python3.withPackages (
            ps: with ps; [
              deepdiff
              colorama
            ]
          );
          validator = pkgs.writeScriptBin "validator" ''
            #!${pythonWithDeps}/bin/python3
            ${builtins.readFile ./validators/main.py}
          '';
        in
        {
          type = "app";
          program = toString (
            pkgs.writers.writeBash "test-${configName}" ''
              echo "🧪 Testing ${configName} configuration..."

              # Build first
              echo "🔨 Building ${configName} first..."
              if ! nix run .#build-${configName}; then
                echo "❌ Build failed for ${configName}"
                exit 1
              fi

              # Check if required files exist
              if [[ ! -f "${configName}.tf.json" ]]; then
                echo "❌ ${configName}.tf.json not found after build."
                exit 1
              fi

              if [[ ! -f "./expected-results/${configName}.json" ]]; then
                echo "❌ ./expected-results/${configName}.json not found."
                exit 1
              fi

              # Run the Python validator
              ${validator}/bin/validator "${configName}" --test-dir .
            ''
          );
        };

      # Create a test-all app that builds all, then tests all sequentially
      createTestAllApp =
        { pkgs, system }:
        let
          # Python validator script with enhanced dependencies (no linting)
          pythonWithDeps = pkgs.python3.withPackages (
            ps: with ps; [
              deepdiff
              colorama
            ]
          );
          validator = pkgs.writeScriptBin "validator" ''
            #!${pythonWithDeps}/bin/python3
            ${builtins.readFile ./validators/main.py}
          '';
        in
        {
          type = "app";
          program = toString (
            pkgs.writers.writeBash "test-all" ''
              echo "🚀 Building all test configurations..."

              # Build all configurations sequentially
              for config in ${nixpkgs.lib.concatStringsSep " " testConfigurations}; do
                echo "🔨 Building $config..."
                if ! nix run .#build-$config; then
                  echo "❌ Build failed for $config"
                  exit 1
                fi
              done

              echo ""
              echo "✅ All builds completed"
              echo ""
              echo "🧪 Running all tests..."

              # Run all tests sequentially
              TEST_FAILED=0
              for config in ${nixpkgs.lib.concatStringsSep " " testConfigurations}; do
                echo ""
                echo "🧪 Testing $config..."
                
                # Check if required files exist
                if [[ ! -f "$config.tf.json" ]]; then
                  echo "❌ $config.tf.json not found."
                  TEST_FAILED=1
                  continue
                fi

                if [[ ! -f "./expected-results/$config.json" ]]; then
                  echo "❌ ./expected-results/$config.json not found."
                  TEST_FAILED=1
                  continue
                fi

                # Run the Python validator
                if ${validator}/bin/validator "$config" --test-dir .; then
                  echo "✅ $config test passed"
                else
                  echo "❌ $config test failed"
                  TEST_FAILED=1
                fi
              done

              echo ""
              if [[ $TEST_FAILED -eq 0 ]]; then
                echo "🎉 All builds and tests passed!"
                exit 0
              else
                echo "💥 Some tests failed!"
                exit 1
              fi
            ''
          );
        };

      # Create a build-all app that builds all configurations sequentially
      createBuildAllApp =
        { pkgs, system }:
        {
          type = "app";
          program = toString (
            pkgs.writers.writeBash "build-all" ''
              echo "🚀 Building all test configurations sequentially..."

              # Build configurations sequentially
              for config in ${nixpkgs.lib.concatStringsSep " " testConfigurations}; do
                echo "🧪 Building $config..."
                if ! nix run .#build-$config; then
                  echo "❌ Build failed for $config"
                  exit 1
                fi
              done

              echo "🎉 All configurations built successfully!"
            ''
          );
        };

      # Generate all build apps from the test configurations list
      generateBuildApps =
        { pkgs, system }:
        let
          individualApps = nixpkgs.lib.listToAttrs (
            map (configName: {
              name = "build-${configName}";
              value = createBuildApp { inherit pkgs system configName; };
            }) testConfigurations
          );
          buildAllApp = {
            build-all = createBuildAllApp { inherit pkgs system; };
          };
          testApps = nixpkgs.lib.listToAttrs (
            map (configName: {
              name = "test-${configName}";
              value = createTestApp { inherit pkgs system configName; };
            }) testConfigurations
          );
          testAllApp = {
            test-all = createTestAllApp { inherit pkgs system; };
          };

          # Error test apps
          errorBuildApps = nixpkgs.lib.listToAttrs (
            map (configName: {
              name = "build-error-${configName}";
              value = createErrorBuildApp { inherit pkgs system configName; };
            }) errorTestConfigurations
          );
          errorTestApps = nixpkgs.lib.listToAttrs (
            map (configName: {
              name = "test-error-${configName}";
              value = createErrorTestApp { inherit pkgs system configName; };
            }) errorTestConfigurations
          );
        in
        individualApps // buildAllApp // testApps // testAllApp // errorBuildApps // errorTestApps;
    in
    {
      apps = forEachSystem ({ system, pkgs }: generateBuildApps { inherit pkgs system; });

      devShells = forEachSystem (
        { system, pkgs }:
        let
          terraform = nixpkgs-terraform.packages.${system}.${tf_version};
        in
        {
          default = pkgs.mkShell {
            buildInputs = [
              terraform
              pkgs.python3
            ];
          };
        }
      );
    };
}
