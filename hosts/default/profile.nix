{ config, ... }:
let
    inherit (config.flake.modules) nixos; 
    inherit (import ./_host.nix) hostname;
in
{
    flake.modules.nixos."${hostname}Configuration" = { pkgs, ... }: 
    let 
    
    in
    {
        # @TODO: Imports shouldn't be visible to host. Role system handles who imports what automatically and enables it
        imports = [
            nixos.system
            nixos.hardware
            nixos.base
            nixos.direnv
            nixos.debug # @TODO: This needs a proper env
        ];
        
        config = {
            # Temp access >> Role system later
            internal.system.debug.enable = true;
            # internal.system.bootloader.enable = true;
        
            profile.system = {
                hostname = hostname;
                timeZone = "America/New_York";
                locale.default = "en_US.UTF-8";
                locale.extra = "en_US.UTF-8";
                
                dualBoot = false;
                
                # "nvidia" | "amd" | "intel"
                hardware = [ "nvidia" "intel" ];
                nvidia.powerManagement = true;
                nvidia.finegrained = false;
                nvidia.dynamicBoost = true;
                
                bootloader.settings = { };
                bootloader.plymouth = {
                    theme = "loader_2";
                    themePackages = [
                        (pkgs.adi1090x-plymouth-themes.override {
                            selected_themes = [ "loader_2" ];
                        })
                    ];
                };
            };
              
            profile.user = {
                username = "user"; # The username will also be used as git name
                # hashedPasswordFile = age.secrets.<ageFile>.path;
                terminal = "kitty";
                keyboard.layout = "us";
                keyboard.variant = "";
                
                fonts = {
                    size = 14;
                    packages = [ ];
                    defaults.serif = [ "Noto Serif" ];
                    defaults.sans  = [ "Noto Sans" ];
                    defaults.mono  = [ "JetBrains Mono" ];
                };
            };
                
            profile.desktop = {
                experimental.enable = false;

                displayManager = {
                    settings = {
                        theme = "sddm-astronaut-theme";
                        extraPackages = [ 
                            # @TODO: These can probably be directly handled by the custom quickshell bar later
                            pkgs.kdePackages.qtsvg 
                            pkgs.kdePackages.qtmultimedia 
                            pkgs.kdePackages.qtvirtualkeyboard 
                            pkgs.kdePackages.qt5compat
                        ];
                    };
                    extraPackages = [
                        (pkgs.sddm-astronaut.override {
                            embeddedTheme = "astronaut";
                        })
                    ];
                };
            };
        };
    };                                
}
