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
                
                hostKeys = [{
                    path = "/persistent/etc/ssh/ssh_host_ed25519_key";
                    type = "ed25519";
                }];
            };
            
            programs.ssh.knownHosts = {
                "github.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
                "codeberg.org".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIVIC02vnjFyL+I4RHfvIGNtOgJMe769VTF1VR4EB3ZB";
                "gitlab.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf";
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