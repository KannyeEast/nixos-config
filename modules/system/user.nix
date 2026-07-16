{ lib, ... }:
let
    inherit (lib) mkOption types;
in
{
    flake.modules.nixos.user = { config, pkgs, host, ... }:
    let
        inherit (config.profile) user;
        inherit (config) sops;
    in
    {
        options = {
            profile.user = {
                shell = mkOption {
                    type = types.package;
                    default = pkgs.zsh;
                    description = "Preferred terminal shell";
                };
            };
        };
    
        config = {
            sops.secrets."userPassword".neededForUsers = true;
        
            users.mutableUsers = false;
            
            # Create user profile
            users.users.${host.user.name} = {
                isNormalUser = true;
                uid = 1000;
                home = "/home/${host.user.name}";
                extraGroups = [
                    "wheel"             # sudo/root privileges
                    "networkmanager"    # network configuration
                ];

                hashedPasswordFile = sops.secrets.userPassword.path;
                openssh.authorizedKeys.keys = host.user.sshKeys;
                
                shell = pkgs.zsh;
            };
            
            environment.shells = [ pkgs.zsh ]; 
            
            services.openssh = {
                enable = true;
                openFirewall = true;
            };
            
            programs.zsh.enable = true;
            
            security.sudo.extraConfig = "Defaults lecture=never";
            
            nix.settings.trusted-users = [
                "root"
                "@wheel"
            ];
        };
    };
}