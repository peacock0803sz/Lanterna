{
  description = "Lanterna";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        # To import an internal flake module: ./other.nix
        # To import an external flake module:
        #   1. Add foo to inputs
        #   2. Add foo as a parameter to the outputs function
        #   3. Add here: foo.flakeModule

        inputs.git-hooks.flakeModule
      ];
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      perSystem = { config, self', inputs', pkgs, system, ... }: {
        # Per-system attributes can be defined here. The self' and inputs'
        # module parameters provide easy access to attributes of the same
        # system.

        pre-commit.check.enable = false;
        pre-commit.settings.hooks = {
          actionlint = {
            enable = true;
            entry = "${pkgs.actionlint}/bin/actionlint";
            files = "\\.github/workflows/.*\\.ya?ml$";
          };
          pinact = {
            enable = true;
            entry = "${pkgs.pinact}/bin/pinact";
            args = [ "run" "-fix=false" "-no-api" ];
            files = "\\.github/workflows/.*\\.ya?ml$";
            pass_filenames = false;
          };
          shellcheck = {
            enable = true;
            entry = "${pkgs.shellcheck}/bin/shellcheck";
            files = "\\.sh$";
          };
          swiftformat = {
            enable = true;
            entry = "${pkgs.swiftformat}/bin/swiftformat";
            types = [ "swift" ];
          };
          swiftlint = {
            enable = true;
            entry = "${pkgs.writeShellScript "swiftlint-hook" ''
              # Nix sets DEVELOPER_DIR to its Apple SDK, which lacks SourceKit.
              # Reset to the real system path so SwiftLint can load sourcekitd.
              if [ -n "''${XCODE_DEVELOPER_DIR:-}" ] && [ -d "''${XCODE_DEVELOPER_DIR}" ]; then
                export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"
              else
                unset DEVELOPER_DIR
                if [ -x /usr/bin/xcode-select ]; then
                  export DEVELOPER_DIR=$(/usr/bin/xcode-select -p 2>/dev/null)
                fi
              fi

              if [ -z "''${DEVELOPER_DIR:-}" ] || [ ! -d "$DEVELOPER_DIR" ]; then
                echo "swiftlint: skipped (Xcode/CLI tools not found; set XCODE_DEVELOPER_DIR)" >&2
                exit 0
              fi
              # Nix sandbox hides system framework paths; point dyld to SourceKit
              export DYLD_FRAMEWORK_PATH="$DEVELOPER_DIR/usr/lib"
              exec ${pkgs.swiftlint}/bin/swiftlint lint --strict "$@"
            ''}";
            types = [ "swift" ];
          };
          # The docs site's own tools, run from docs/node_modules so the hooks
          # use the versions pinned in docs/pnpm-lock.yaml; `pnpm install` in
          # docs/ is required first. Node comes from nixpkgs because the dev
          # shell does not provide one.
          docs-prettier = {
            enable = true;
            entry = "${pkgs.writeShellScript "docs-prettier" ''
              export PATH="${pkgs.nodejs_24}/bin:$PATH"
              cd docs || exit 1
              exec ./node_modules/.bin/prettier --check --ignore-unknown "''${@#docs/}"
            ''}";
            files = "^docs/";
          };
          docs-textlint-ja = {
            enable = true;
            entry = "${pkgs.writeShellScript "docs-textlint-ja" ''
              export PATH="${pkgs.nodejs_24}/bin:$PATH"
              cd docs || exit 1
              exec ./node_modules/.bin/textlint --config .textlintrc.ja.json "''${@#docs/}"
            ''}";
            files = "^docs/src/content/docs/ja/.*\\.mdx?$";
          };
          docs-textlint-en = {
            enable = true;
            entry = "${pkgs.writeShellScript "docs-textlint-en" ''
              export PATH="${pkgs.nodejs_24}/bin:$PATH"
              cd docs || exit 1
              exec ./node_modules/.bin/textlint --config .textlintrc.en.json "''${@#docs/}"
            ''}";
            files = "^docs/src/content/docs/en/.*\\.mdx?$";
          };
          # Type checks the whole site, so it takes no file names and runs
          # once whenever a file it reads changes.
          docs-astro-check = {
            enable = true;
            entry = "${pkgs.writeShellScript "docs-astro-check" ''
              export PATH="${pkgs.nodejs_24}/bin:$PATH"
              cd docs || exit 1
              exec ./node_modules/.bin/astro check
            ''}";
            files = "^docs/(astro\\.config\\.mjs|src/.*\\.(astro|ts|mdx?))$";
            pass_filenames = false;
          };
        };

        # Equivalent to  inputs'.nixpkgs.legacyPackages.hello;
        # The Swift toolchain (swift, swiftc, SwiftPM) comes from Xcode or the
        # Command Line Tools, not from nixpkgs: the nixpkgs `swift` package on
        # Darwin ships only the compiler (no swift-build), and its stdenv exports
        # DEVELOPER_DIR/SDKROOT pointing at the Nix Apple SDK, which hides the
        # system toolchain. mkShellNoCC keeps the Nix C toolchain and Apple SDK
        # out of the shell so /usr/bin/swift resolves to the real toolchain.
        devShells.default = pkgs.mkShellNoCC {
          inputsFrom = [ config.pre-commit.devShell ];
          packages = with pkgs; [
            actionlint
            pinact
            shellcheck
            swiftformat
            swiftlint
          ];
          shellHook = ''
            if ! xcode-select -p &>/dev/null; then
              echo "WARNING: Xcode CLI tools not found."
              echo "  Install with: xcode-select --install"
              echo "  Or install Xcode from the App Store."
            fi
            echo "swiftformat $(swiftformat --version)"
            echo "swiftlint $(swiftlint version)"
            echo "swift $(swift --version 2>&1 | head -1)"
          '';
        };

      };
      flake = {
        # The usual flake attributes can be defined here, including system-
        # agnostic ones like nixosModule and system-enumerating ones, although
        # those are more easily expressed in perSystem.
      };
    };
}
