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
        imports = [
            nixos.system
            nixos.hardware
            nixos.base
            nixos.desktopEnvironment
            nixos.displayManager
        ];
        
        config = {
            internal.system.debugging.enable = true;
            internal.desktop.environment.enable = true;
        
            profile.system = {
                hostname = hostname;
                # "home-manager" | "secrets"
                flakeModules = [ "home-manager" "secrets" ];
                timeZone = "America/New_York";
                locale.default = "en_US.UTF-8";
                locale.extra = "en_US.UTF-8";
                
                dualBoot = false;
                
                # "nvidia" | "amd" | "intel"
                gpu = "nvidia";
                nvidia.powerManagement = true;
                nvidia.finegrained = false;
                nvidia.dynamicBoost = true;
                
                
                # "systemd-boot" | "grub" | "limine"
                bootloader.type = "systemd-boot";
                bootloader.settings = { };
                bootloader.extras = { };
                
                plymouth.enable = true;
                plymouth.settings = {
                    theme = "loader_2";
                    themePackages = [
                        (pkgs.adi1090x-plymouth-themes.override {
                            selected_themes = [ "loader_2" ];
                        })
                    ];
                };
            };
              
            profile.user = {
                username = "user";
                # hashedPasswordFile = age.secrets.<ageFile>.path;
                shell = "zsh";  # "bash" | "zsh" | "fish"
                terminal = "kitty";
                keyboard.layout = "us";
                keyboard.variant = "";
                
                fonts = {
                    size = 14;
                    packages = [ pkgs.noto-fonts pkgs.noto-fonts-cjk-sans pkgs.noto-fonts-color-emoji pkgs.nerd-fonts.jetbrains-mono ];
                    defaults.serif = [ "Noto Serif" ];
                    defaults.sans  = [ "Noto Sans" ];
                    defaults.mono  = [ "JetBrains Mono" ];
                };
            };
                
            profile.desktop = {
                # "experimental" and/or "optionals"
                modules = [ ];

                displayManager = {
                    # "gdm" | "regreet" | "lemurs" | "ly" | "sddm"
                    # type = "gdm";
                    settings = { };
                    extraPackages = [ ];
                };
                
                # "waybar" | "dms" | "noctalia" | "caelestia"
                shell = "waybar";
            };
        };
    };                                
}
