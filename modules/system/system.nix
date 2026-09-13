{ lib, ... }:
let
  inherit (lib)
    mkOption
    types
    ;
in
{
  flake.modules.nixos.system =
    {
      config,
      flake,
      locale,
      ...
    }:
    let
      inherit (config.internal)
        system
        ;

      ref = "git+file://${flake}?submodules=1";
    in
    {
      options = {
        internal.system = {
          repo = mkOption {
            type = types.str;
            default = "git+ssh://git@codeberg.org/KanyeSouth/nixos-config.git";
            internal = true;
            description = "Remote the auto-upgrade pulls from";
          };
          version = mkOption {
            type = types.str;
            default = "26.05";
            internal = true;
            description = "NixOS and home-manager stateVersion";
          };
          autoUpgrade = mkOption {
            type = types.bool;
            default = false;
            internal = true;
            description = "Pull and build the newest config";
          };
        };
      };

      config = {
        programs.nh = {
          enable = true;
          clean.enable = true;
          clean.extraArgs = "--keep-since 4d --keep 5";
          flake = ref;
        };

        nix = {
          settings = {
            auto-optimise-store = true;

            # default buffer overflows fast with large configs; 
            download-buffer-size = 500000000;

            experimental-features = [
              "nix-command"
              "flakes"
            ];

            substituters = [
              "https://cache.nixos.org"
              "https://nix-community.cachix.org"
            ];

            trusted-public-keys = [
              "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            ];
          };

          # automatically optimise nix store 
          optimise = {
            automatic = true;
            dates = [ "04:00" ];
          };

          extraOptions = ''
            warn-dirty = false 
          '';
        };

        system = {
          autoUpgrade = {
            enable = system.autoUpgrade;
            dates = "Sat *-*-* 01:00:00 ${locale.timeZone}";
            operation = "boot";
            flake = system.repo;
            flags = [ "--print-build-logs" ];
          };

          stateVersion = system.version;
        };

        nixpkgs.config.allowUnfree = true;
      };
    };
}
