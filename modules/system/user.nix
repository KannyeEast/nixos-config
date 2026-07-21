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
                uid = 1000;
                home = "/home/${user.name}";
                extraGroups = [
                    "wheel"             # sudo/root privileges
                    "networkmanager"    # network configuration
                ];

                hashedPasswordFile = sops.secrets.userPassword.path;
                openssh.authorizedKeys.keys = user.sshKeys;
                
                shell = pkgs.zsh;
            };
            
            environment.shells = [ pkgs.zsh ]; 
            
            services.openssh = {
                enable = true;
                openFirewall = true;
                
                hostKeys = {                
                    path = "/persist/etc/ssh/ssh_host_ed25519_key";
                    type = "ed25519";
                };
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