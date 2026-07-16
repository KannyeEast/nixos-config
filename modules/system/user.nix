{ ... }:
{
    flake.modules.nixos.user = { config, pkgs, host, ... }:
    let
        inherit (host) user;
        inherit (config) sops;
        inherit (config.profile) user;
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
            users.users.${user.name} = {
                isNormalUser = true;
                uid = 1000;
                home = "/home/${user.name}";
                extraGroups = [
                    "wheel"             # sudo/root privileges
                    "networkmanager"    # network configuration
                ];

                hashedPasswordFile = sops.secrets.userPassword.path;
                openssh.authorizedKeys.keys = user.sshKeys;
                
                shell = user.shell;
            };
            
            services.openssh = {
                enable = true;
                openFirewall = true;
            };
            
            programs.${user.shell}.enable = true;
            
            security.sudo.extraConfig = "Defaults lecture=never";
            
            nix.settings.trusted-users = [
                "root"
                "@wheel"
            ];
        };
    };
}