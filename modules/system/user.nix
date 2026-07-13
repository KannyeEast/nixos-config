{ ... }:
{
    flake.modules.nixos.user = { config, pkgs, host, ... }:
    let
        inherit (host) user;
        inherit (config) sops;
    in
    {
        config = {
            sops.secrets."userPassword".neededForUsers = true;
        
            users.mutableUsers = false;
            
            # Create user profile
            users.users.${user.name} = {
                isNormalUser = true;
                home = "/home/${user.name}";
                extraGroups = [
                    "wheel"             # sudo/root privileges
                    "networkmanager"    # network configuration
                ];

                hashedPasswordFile = sops.secrets.userPassword.path;
                openssh.authorizedKeys.keys = user.sshKeys;
                
                shell = pkgs.zsh;
            };
            
            services.openssh = {
                enable = true;
                openFirewall = true;
            };
            
            programs.zsh.enable = true;
            
            nix.settings.trusted-users = [
                "root"
                "@wheel"
            ];
        };
    };
}