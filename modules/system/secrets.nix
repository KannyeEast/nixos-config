{ inputs, ... }:
{
    flake.modules.nixos.secrets = { pkgs, host, ... }:
    let
        inherit (host) hostname user;
    in
    {
        imports = [
            inputs.sops-nix.nixosModules.sops
        ];
    
        config = {
            environment.systemPackages = [
                pkgs.sops
                pkgs.ssh-to-age
            ];

            environment.sessionVariables.SOPS_AGE_SSH_PRIVATE_KEY_FILE = "/home/${user.name}/.ssh/id_${user.name}";
        
            sops = {
                defaultSopsFile = ../../hosts/${hostname}/secrets.json;
                defaultSopsFormat = "json";
                validateSopsFiles = false;
                
                age = {
                    # @TODO: This location changes with impermanence setup
                    sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
                    keyFile = "/var/lib/sops-nix/key.txt";
                    generateKey = true;
                };
                
                secrets = {
                    userPrivateKey = {
                        path = "/home/${user.name}/.ssh/id_${user.name}";
                        owner = user.name;
                        mode = "0600";
                    };
                };
            };
        };
    };
}