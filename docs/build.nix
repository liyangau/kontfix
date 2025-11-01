{ pkgs, self, eval }:

let
  repoUrl = "https://github.com/liyangau/kontfix";

  # Helper function to create options documentation for a specific section
  createOptionsDoc = options: pkgs.nixosOptionsDoc {
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
  defaultsOptions = eval.options.kontfix.defaults or {};
  controlPlanesOptions = eval.options.kontfix.controlPlanes or {};
  groupsOptions = eval.options.kontfix.groups or {};

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
  docs-md = pkgs.runCommand "my-module-options.md" { } ''
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
      name = "my-module-doc-html";

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

        # Helper function to process markdown files
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
        cat <<EOF > docs/index.md
        # Kontfix Documentation

        ![Kontfix](kontfix.png)

        Welcome to the Kontfix documentation. Kontfix is a Nix-based framework for managing Kong Konnect control planes and system accounts.

        ## Sections

        - **[Defaults](defaults-options.md)** - Default configuration options for storage, PKI, certificates, and system account tokens
        - **[Control Planes](controlplanes-options.md)** - Individual control plane configuration options
        - **[Groups](groups-options.md)** - System account group configuration options

        EOF

        # Create section introduction pages
        cat <<EOF > docs/defaults.md
        # Defaults Configuration

        This section contains all the default configuration options that apply globally to your Kontfix setup.

        [📖 View all defaults options](defaults-options.md)

        ## Configuration Areas

        - **Storage** - AWS and HashiCorp Vault storage configurations
        - **PKI** - PKI backend for generating client certificates for CP-DP communications. Curently supports HashiCorp Vault only.
        - **Control Planes** - Default settings for individual control planes
        - **Certificates** - Certificate validity and renewal settings
        - **System Account Tokens** - Token validity and renewal settings

        EOF

        cat <<EOF > docs/controlplanes.md
        # Control Planes Configuration

        This section contains configuration options for individual Kong Konnect control planes.

        [📖 View all control planes options](controlplanes-options.md)

        ## Key Features

        - Authentication type configuration
        - Certificate management
        - System account creation
        - Storage backend selection
        - AWS provider configuration
        - Custom plugins support

        EOF

        cat <<EOF > docs/groups.md
        # Groups Configuration

        This section contains configuration options for system account groups, which allow you to manage multiple control planes together.

        [📖 View all groups options](groups-options.md)

        ## Key Features

        - Group member management
        - Token generation and storage
        - Multi-region support
        - AWS integration for group storage

        EOF

        # Create mkdocs.yml configuration
        cat <<EOF > mkdocs.yml
          site_name: Kontfix
          site_dir: $out
          repo_url: https://github.com/liyangau/kontfix
          repo_name: liyangau/kontfix

          theme:
            name: material
            palette:
            - media: "(prefers-color-scheme: light)"
              scheme: default
              primary: deep purple
              toggle:
                icon: material/brightness-7
                name: Switch to dark mode
            - media: "(prefers-color-scheme: dark)"
              scheme: slate
              primary: blue grey
              toggle:
                icon: material/brightness-4
                name: Switch to light mode

            features:
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
    runtimeInputs = with pkgs; [ rsync git ];
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