{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  flake.modules.nixos.system =
    { config, host, ... }:
    let
      inherit (host) configPath locale;
      inherit (config.internal) system;

      ref = "git+file://${configPath}?submodules=1";
    in
    {
      options = {
        internal.system = {
          name = mkOption {
            type = types.str;
            default = "nixos-config";
            internal = true;
            description = "Reference point for the name of the config";
          };
          repo = mkOption {
            type = types.str;
            default = "git+ssh://git@codeberg.org/KanyeSouth/nixos-config.git";
            internal = true;
            description = "The main git repo the config is associated with";
          };
          version = mkOption {
            type = types.str;
            default = "26.05";
            internal = true;
            description = "Change the NixOS and Home-manager version";
          };
          autoUpgrade = mkOption {
            type = types.bool;
            default = false;
            internal = true;
            description = "Automatically upgrades NixOS to the newest version";
          };
        };
      };

      config = {
        #
        # Nix system settings
        #

        environment.sessionVariables = {
          NH_FLAKE = ref;
        };

        programs.nh = {
          enable = true;
          clean.enable = true;
          clean.extraArgs = "--keep-since 4d --keep 5";
          flake = ref;
        };

        nix = {
          # General settings
          settings = {
            # Auto-optimize store daily (deduplicates files)
            auto-optimise-store = true;

            # Increase Buffer size for downloads
            download-buffer-size = 500000000;

            # Core features
            experimental-features = [
              "nix-command"
              "flakes"
              "pipe-operators"
            ];

            # Substituters for faster downloads
            substituters = [
              "https://cache.nixos.org"
              "https://nix-community.cachix.org"
            ];

            trusted-public-keys = [
              "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            ];
          };

          # Optimize
          optimise = {
            automatic = true;
            dates = [ "04:00" ];
          };

          # Extras
          extraOptions = ''
            warn-dirty = false 
          '';
        };

        system = {
          # Auto upgrade
          autoUpgrade = {
            enable = system.autoUpgrade;
            dates = "Sat *-*-* 01:00:00 ${locale.timeZone}";
            operation = "boot";
            flake = system.repo;
            flags = [
              "--print-build-logs"
            ];
          };
          
          # NixOS Version
          stateVersion = system.version;
        };

        # Allow unfree packages
        nixpkgs.config.allowUnfree = true;
      };
    };
}
