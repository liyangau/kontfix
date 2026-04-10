{
  pkgs,
  self,
  eval,
}:

let
  repoUrl = "https://github.com/liyangau/kontfix";

  # Helper function to create options documentation for a specific section
  createOptionsDoc =
    options:
    pkgs.nixosOptionsDoc {
      inherit options;
      transformOptions =
        opt:
        opt
        // {
          declarations = map (
            decl:
            let
              path = pkgs.lib.removePrefix (toString self + "/") (toString decl);
            in
            {
              url = "${repoUrl}/blob/main/${path}";
              name = path;
            }
          ) opt.declarations;
          name =
            let
              origName = opt.name;
            in
            if pkgs.lib.hasSuffix ".<name>.<name>" origName then
              pkgs.lib.replaceStrings [ ".<name>.<name>" ] [ ".<region>.<controlPlane>" ] origName
            else
              pkgs.lib.replaceStrings [ ".<name>.<name>." ] [ ".<region>.<controlPlane>." ] origName;
        };
    };

  # Extract options for each section
  defaultsOptions = eval.options.kontfix.defaults or { };
  controlPlanesOptions = eval.options.kontfix.controlPlanes or { };
  groupsOptions = eval.options.kontfix.groups or { };

  # Create documentation for each section
  defaultsDoc = createOptionsDoc defaultsOptions;
  controlPlanesDoc = createOptionsDoc controlPlanesOptions;
  groupsDoc = createOptionsDoc groupsOptions;

in
{
  # Individual markdown files for each section
  defaults-docs-md = pkgs.runCommand "defaults-options.md" { } ''
    cp ${defaultsDoc.optionsCommonMark} $out
  '';

  controlplanes-docs-md = pkgs.runCommand "controlplanes-options.md" { } ''
    cp ${controlPlanesDoc.optionsCommonMark} $out
  '';

  groups-docs-md = pkgs.runCommand "groups-options.md" { } ''
    cp ${groupsDoc.optionsCommonMark} $out
  '';

  # Legacy single file for backward compatibility
  docs-md = pkgs.runCommand "kontfix-options.md" { } ''
    cat ${defaultsDoc.optionsCommonMark} > $out
    echo "" >> $out
    cat ${controlPlanesDoc.optionsCommonMark} >> $out
    echo "" >> $out
    cat ${groupsDoc.optionsCommonMark} >> $out
  '';

  docs =
    let
      defaultsMd = pkgs.runCommand "defaults-options.md" { } ''
        cp ${defaultsDoc.optionsCommonMark} $out
      '';
      controlPlanesMd = pkgs.runCommand "controlplanes-options.md" { } ''
        cp ${controlPlanesDoc.optionsCommonMark} $out
      '';
      groupsMd = pkgs.runCommand "groups-options.md" { } ''
        cp ${groupsDoc.optionsCommonMark} $out
      '';
    in
    pkgs.stdenv.mkDerivation {
      name = "kontfix-docs";

      src = self;

      buildInputs = with pkgs.python3.pkgs; [
        mkdocs-material
        mkdocs-material-extensions
      ];

      phases = [
        "unpackPhase"
        "patchPhase"
        "buildPhase"
      ];

      patchPhase = ''
        mkdir -p docs

        # Helper function to process auto-generated option markdown files
        process_markdown() {
          local input=$1
          local output=$2
          cat $input | \
            ${pkgs.gnused}/bin/sed 's/\\\.\\\./\.\./g' | \
            ${pkgs.gnused}/bin/sed 's/\\\./\./g' | \
            ${pkgs.gnused}/bin/sed 's/\.\./\&lt;name\&gt;/g' | \
            ${pkgs.gnused}/bin/sed 's/\\</\&lt;/g' | \
            ${pkgs.gnused}/bin/sed 's/\\>/\&gt;/g' \
            > $output
        }

        # Process each section's markdown
        process_markdown ${defaultsMd} docs/defaults-options.md
        process_markdown ${controlPlanesMd} docs/controlplanes-options.md
        process_markdown ${groupsMd} docs/groups-options.md

        # Create combined options.md for backward compatibility
        cat docs/defaults-options.md > docs/options.md
        echo "" >> docs/options.md
        cat docs/controlplanes-options.md >> docs/options.md
        echo "" >> docs/options.md
        cat docs/groups-options.md >> docs/options.md

        cp ${self}/assets/kontfix.png docs/kontfix.png

        # Create index page
        cat <<'EOF' > docs/index.md
        # Kontfix Documentation

        Kontfix is a Nix-based framework for managing Kong Konnect control planes and related resources—system accounts and client certificates—via Terraform. Users declare their infrastructure in Nix modules; Kontfix converts them to `config.tf.json` consumed by Terraform.

        ![Kontfix](kontfix.png)

        ## How It Works

        1. Declare control planes, storage backends, and certificates in Nix modules
        2. Run `nix run .#build` to generate `config.tf.json`
        3. Run `nix run .#apply` to provision resources in Kong Konnect

        ## Sections

        - **[Defaults](defaults.md)** — Global defaults applied to all control planes and resources
        - **[Control Planes](controlplanes.md)** — Per-control-plane configuration: auth type, certificates, system accounts, storage backends
        - **[Groups](groups.md)** — System account groups that span multiple control planes
        EOF

        # Create section introduction pages
        cat <<'EOF' > docs/defaults.md
        # Defaults Configuration

        Global settings applied across all control planes. Per-control-plane values override these defaults where applicable.

        [View all defaults options](defaults-options.md)

        ## When to Configure Each Section

        Most options have sensible defaults. You only need to configure a section when you use the corresponding feature:

        | Section | Configure when |
        |---|---|
        | `defaults.storage.hcv` | Any control plane uses the HCV storage backend |
        | `defaults.storage.aws` | Any control plane uses the AWS storage backend |
        | `defaults.pki.hcv` | Any control plane uses `auth_type = "pki_client_certs"` with `create_certificate = true` |
        | `defaults.controlPlanes` | You want to change the default `auth_type` or `storage_backend` for all control planes |

        ## Example

        A setup using HashiCorp Vault for both storage and PKI:

        ```nix
        kontfix.defaults = {
          storage.hcv = {
            address = "https://vault.example.com";
            auth_method = "approle"; # uses vault_role_id / vault_secret_id Terraform variables
          };

          pki.hcv.address = "https://vault.example.com";

          controlPlanes = {
            auth_type = "pki_client_certs";
            storage_backend = [ "hcv" ];
            labels = {
              managed-by = "kontfix";
            };
          };

          system_account_tokens = {
            validity_period = 30;      # days
            renewal_before_expiry = 7; # days
          };
        };
        ```

        ## Configuration Areas

        - **Storage** — Connection details and path prefixes for each backend (AWS Secrets Manager, HashiCorp Vault, local filesystem)
        - **PKI** — Vault connection used to issue client certificates; required when `create_certificate = true`
        - **Control Planes** — Default `auth_type`, `storage_backend`, and `labels` applied to every control plane unless overridden
        - **Self-Signed Certificates** — Validity period and auto-renewal window for self-signed certificates
        - **System Account Tokens** — Token validity period and auto-renewal window
        - **Provider Versions** — Override pinned Terraform provider versions
        EOF

        cat <<'EOF' > docs/controlplanes.md
        # Control Planes Configuration

        Configuration for individual Kong Konnect control planes, declared under `kontfix.controlPlanes.<region>.<name>`.

        Supported regions: `us`, `eu`, `au`, `sg`, `in`, `me`

        [View all control plane options](controlplanes-options.md)

        ## Choosing an Auth Type

        Each control plane uses one of two authentication types for data plane connectivity:

        | Auth type | Use when |
        |---|---|
        | `pinned_client_certs` (default) | You manage certificates yourself, or use self-signed certificates generated by Kontfix |
        | `pki_client_certs` | You want Kontfix to issue certificates from a HashiCorp Vault PKI backend |

        !!! note
            `CLUSTER_TYPE_K8S_INGRESS_CONTROLLER` control planes must use `pinned_client_certs`.

        ## Examples

        ### Minimal control plane

        A basic control plane in the `au` region with all defaults:

        ```nix
        kontfix.controlPlanes.au.my-cp = { };
        ```

        ### Control plane with PKI certificates stored in Vault

        ```nix
        kontfix = {
          defaults = {
            pki.hcv.address = "https://vault.example.com";
            storage.hcv.address = "https://vault.example.com";
          };

          controlPlanes.au.my-cp = {
            auth_type = "pki_client_certs";
            create_certificate = true;
            store_cluster_config = true;
            storage_backend = [ "hcv" ];
          };
        };
        ```

        ### Control plane with a system account and AWS secret storage

        ```nix
        kontfix.controlPlanes.us.my-cp = {
          create_certificate = true;
          system_account = {
            enable = true;
            generate_token = true;
          };
          storage_backend = [ "aws" ];
          aws = {
            enable = true;
            region = "us-east-1";
            tags = {
              Environment = "production";
              ManagedBy = "kontfix";
            };
          };
        };
        ```

        ### Control plane group

        A control plane group allows multiple data planes to connect through a single group endpoint:

        ```nix
        kontfix.controlPlanes.au = {
          cp-a = { };
          cp-b = { };

          my-group = {
            cluster_type = "CLUSTER_TYPE_CONTROL_PLANE_GROUP";
            members = [ "cp-a" "cp-b" ];
          };
        };
        ```

        ## Key Constraints

        - Group members cannot have `create_certificate = true` or `store_cluster_config = true`
        - Control plane groups cannot have `system_account.enable = true`
        - `CLUSTER_TYPE_K8S_INGRESS_CONTROLLER` requires `auth_type = "pinned_client_certs"`
        - AWS storage requires `aws.enable = true` and non-empty `aws.tags`
        - HCV storage requires `defaults.storage.hcv.address` to be set
        - PKI certificate generation (`create_certificate = true`) only supports `pki_backend = "hcv"`
        EOF

        cat <<'EOF' > docs/groups.md
        # Groups Configuration

        Groups create a single system account whose access token grants access across multiple control planes. They are declared under `kontfix.groups.<region>.<name>`.

        !!! note
            A Kontfix group is not the same as `CLUSTER_TYPE_CONTROL_PLANE_GROUP`. A CP group is a Kong gateway-level construct for routing data planes. A Kontfix group is for system account management: one token, multiple control planes.

        [View all groups options](groups-options.md)

        ## Example

        A platform team group that manages two control planes and stores its token in AWS Secrets Manager:

        ```nix
        kontfix = {
          controlPlanes.au = {
            service-a = { };
            service-b = { };
          };

          groups.au.platform-team = {
            members = [ "service-a" "service-b" ];
            generate_token = true;
            storage_backend = [ "aws" ];
            aws = {
              enable = true;
              region = "ap-southeast-2";
              tags = {
                Team = "platform";
                ManagedBy = "kontfix";
              };
            };
          };
        };
        ```

        This creates:

        - A `konnect_system_account` for `platform-team`
        - A `konnect_system_account_access_token` scoped to both `service-a` and `service-b`
        - An AWS Secrets Manager secret containing the token and member metadata

        ## Key Constraints

        - Group members must be individual control planes — groups cannot be members of other groups
        - Group members cannot have `create_certificate = true` or `store_cluster_config = true`
        - Groups do not support `system_account.enable` (the group itself acts as the system account)
        - AWS storage requires `aws.enable = true` and non-empty `aws.tags`
        EOF

        # Create mkdocs.yml configuration
        cat <<EOF > mkdocs.yml
          site_name: Kontfix
          site_dir: $out
          repo_url: https://github.com/liyangau/kontfix
          repo_name: liyangau/kontfix

          theme:
            name: material
            font:
              text: Fira Sans
              code: JetBrains Mono
            palette:
              - media: "(prefers-color-scheme: light)"
                scheme: default
                primary: deep purple
                accent: teal
                toggle:
                  icon: material/brightness-7
                  name: Switch to dark mode
              - media: "(prefers-color-scheme: dark)"
                scheme: slate
                primary: blue grey
                accent: light blue
                toggle:
                  icon: material/brightness-4
                  name: Switch to light mode
            features:
              - search.suggest
              - navigation.footer
              - content.tabs.link
              - navigation.sections

          markdown_extensions:
          - def_list
          - toc:
              permalink: "#"
              toc_depth: 3
          - admonition
          - pymdownx.highlight
          - pymdownx.inlinehilite
          - pymdownx.superfences
          - pymdownx.details
          - pymdownx.tabbed:
              alternate_style: true

          nav:
          - Home: index.md
          - Configuration:
            - Defaults: defaults.md
            - Control Planes: controlplanes.md
            - Groups: groups.md
          - Reference:
            - Defaults Options: defaults-options.md
            - Control Planes Options: controlplanes-options.md
            - Groups Options: groups-options.md
        EOF
      '';

      buildPhase = ''
        python -m mkdocs build
      '';
    };

  # Package that creates a deployable docs directory
  docs-deploy = pkgs.writeShellApplication {
    name = "deploy-docs";
    runtimeInputs = with pkgs; [
      rsync
      git
    ];
    text = ''
      # Build the docs first
      nix build .#docs

      # Create deploy directory
      mkdir -p ./docs-deploy

      # Copy built docs to deploy directory
      rsync -av --delete ./result/ ./docs-deploy/

      # Add .nojekyll file for GitHub Pages
      touch ./docs-deploy/.nojekyll

      echo "Documentation ready for deployment in ./docs-deploy/"
      echo "You can now:"
      echo "  1. cd docs-deploy"
      echo "  2. git add ."
      echo "  3. git commit -m 'Update documentation'"
      echo "  4. git push origin main"
    '';
  };
}
