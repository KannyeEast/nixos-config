{ lib, ... }:
let
    inherit (lib) mkOption mkIf types;
in
{
    flake.modules.nixos.user = { config, pkgs, ... }:
    let
        inherit (config.profile) user;
    in
    {
        options = {
            profile.user = {
                username = mkOption {
                    type = types.str;
                    default = "user";
                    description = "Sets your username";
                };
                hashedPasswordFile = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = ''
                    -- If left at default the system will fallback to the initial password --
                    Set the path to of your passwords file
                    '';
                };
                shell = mkOption {
                    type = types.enum [ "bash" "zsh" "fish" ];
                    default = "zsh";
                    description = "Select your TUI shell: bash | zsh | fish ";
                };
                fonts = {
                    size = mkOption {
                        type = types.int;
                        default = 14;
                        description = "Set your font size";
                    };
                    packages = mkOption {
                        type = types.listOf types.package;
                        default = [ pkgs.noto-fonts pkgs.noto-fonts-cjk-sans pkgs.noto-fonts-color-emoji pkgs.nerd-fonts.jetbrains-mono];
                        description = "Import any font package you want";
                    };
                    defaults = {
                        serif = mkOption {
                            type = types.listOf types.str;
                            default = [ "Noto Serif" ];
                            description = "Default Serif font";
                        };
                        sans = mkOption {
                            type = types.listOf types.str;
                            default = [ "Noto Sans" ];
                            description = "Default Sans font";
                        };
                        mono = mkOption {
                            type = types.listOf types.str;
                            default = [ "JetBrains Mono" ];
                            description = "Default Mono font";
                        };
                    };
                };
            };
        };
        
        config = {
            
            #
            # User
            #
        
            users.mutableUsers = false;
            
            # Create user profile
            users.users.${user.username} = {
                isNormalUser = true;
                home = "/home/${user.username}";
                extraGroups = [
                    "wheel"             # sudo/root privileges
                    "networkmanager"    # network configuration
                ];
                
                hashedPasswordFile = mkIf (user.hashedPasswordFile != null) user.hashedPasswordFile;
                initialPassword = mkIf (user.hashedPasswordFile == null) "nixos";
                
                shell = pkgs.${user.shell};
            };
            
            services.openssh = {
                enable = true;
                openFirewall = true;
            };
            
            programs.${user.shell}.enable = true;
            
            nix.settings.trusted-users = [
                "root"
                "@wheel"
            ];
            
            #
            # Fonts
            #
            
            fonts = {
                fontDir.enable = true;
                enableDefaultPackages = true;
                
                packages = [
                ] ++ user.fonts.packages;
                
                fontconfig = {
                    defaultFonts.serif = user.fonts.defaults.serif;
                    defaultFonts.sansSerif = user.fonts.defaults.sans;
                    defaultFonts.monospace = user.fonts.defaults.mono;
                };
            };
        };
    };
}

