{ config, lib, ... }:
let
    inherit (config.flake.modules) nixos; 
    inherit (lib) mkOption mkDefault types elem;
in
{
    flake.modules.nixos.system = { config, host, ... }:
    let
        inherit (host) hostname;
        
        profile = config.profile.system;
        internal = config.internal.system;
    in
    {
        imports = [
            nixos.boot
            nixos.debugging
            nixos.homeManager
            nixos.secrets
            nixos.user
        ];
        
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
                    default = "github:KannyeEast/nixos-config";
                    internal = true;
                    description = "The git repo this is associated with";
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
            profile.system = {
                hostname = mkOption {
                    type = types.str;
                    default = "default";
                    description = "Set the hostname for this machine";
                };
                flakeModules = mkOption {
                    type = types.listOf (types.enum [ "home-manager" "secrets" ]);
                    default = [ ];
                    description = "Which flake-module features to enable";
                };
                timeZone = mkOption {
                    type = types.str;
                    default = "America/New_York";
                    description = "Set to your local time zone";
                };
                locale = {
                    default = mkOption {
                        type = types.str;
                        default = "en_US.UTF-8";
                        description = "Set the language and characters for the system";
                    };
                    extra = mkOption {
                        type = types.str;
                        default = "en_US.UTF-8";
                        description = "Additional language support";
                    };
                };
            };
        };
        
        config = {
            internal.user.homeManager.enable = elem "home-manager" profile.flakeModules;
            internal.user.secrets.enable = elem "secrets" profile.flakeModules; 
        
            #
            # Timezone
            #
            
            time.timeZone = profile.timeZone;
            
            # Basic keymap
            console.keyMap = "us";
            
            #
            # Locale
            #
            
            i18n.defaultLocale = profile.locale.default;
            i18n.extraLocaleSettings = {
                LC_CTYPE = profile.locale.extra;
                LC_ADDRESS =  profile.locale.extra;
                LC_MEASUREMENT =  profile.locale.extra;
                LC_MESSAGES =  profile.locale.extra;
                LC_MONETARY =  profile.locale.extra;
                LC_NAME =  profile.locale.extra;
                LC_NUMERIC =  profile.locale.extra;
                LC_PAPER =  profile.locale.extra;
                LC_TELEPHONE =  profile.locale.extra;
                LC_TIME =  profile.locale.extra;
                LC_COLLATE =  profile.locale.extra;
            };
            
            #
            # Network
            #
            
            networking = {
                hostName = hostname;
                networkmanager.enable = true;
            };
            
            #
            # Nix system settings
            #
            
            # @TODO: point flake at git repo for nh and autoupgrade 
            programs.nh = {
                enable = true;
                clean.enable = true;
                clean.extraArgs = "--keep-since 4d --keep 5";
                flake = internal.repo;
            };
            
            #    programs.direnv = {
            #        package = pkgs.direnv;
            #        silent = false;
            #        loadInNixShell = true;
            #        direnvrcExtra = "";
            #        nix-direnv = {
            #            enable = true;
            #            package = pkgs.nix-direnv;
            #        };
            #    };
            
            #    environment.systemPackages = with pkgs; [
            #        nixfmt
            #        deadnix
            #    ];
            
            nix = {
                # General settings
                settings = {
                    # Auto-optimize store daily (deduplicates files)
                    auto-optimise-store = true;
                    
                    # Increase Buffer size for downloads
                    download-buffer-size = 500000000;  
                    
                    # Core features
                    experimental-features = [ "nix-command" "flakes" "pipe-operators" ];
                    
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
                    enable = internal.autoUpgrade;
                    dates = "03:00";
                    flake = internal.repo;
                    randomizedDelaySec = "45min";
                    flags = [
                        "--print-build-logs"
                    ];
                };
                
                # NixOS Version
                stateVersion = internal.version;   
            };
            
            # Allow unfree packages
            nixpkgs.config.allowUnfree = true;
        };
    };
}

