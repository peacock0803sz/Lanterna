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
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      perSystem = { config, self', inputs', pkgs, system, ... }: {
        # Per-system attributes can be defined here. The self' and inputs'
        # module parameters provide easy access to attributes of the same
        # system.

        pre-commit.check.enable = false;
        pre-commit.settings.hooks = {
          swiftformat = {
            enable = true;
            entry = "${pkgs.swiftformat}/bin/swiftformat";
            types = [ "swift" ];
          };
          swiftlint = {
            enable = true;
            entry = "${pkgs.writeShellScript "swiftlint-hook" ''
              export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
              exec ${pkgs.swiftlint}/bin/swiftlint lint --strict "$@"
            ''}";
            types = [ "swift" ];
          };
        };

        # Equivalent to  inputs'.nixpkgs.legacyPackages.hello;
        devShells.default = pkgs.mkShell {
          inputsFrom = [ config.pre-commit.devShell ];
          packages = with pkgs; [
            swift
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
