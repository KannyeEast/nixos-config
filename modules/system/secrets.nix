{ inputs, ... }:
{
    flake.modules.nixos.secrets = { host, ... }:
    let
        inherit (host) hostname user;
    in
    {
        imports = [
            inputs.sops-nix.nixosModules.sops
        ];
    
        config = {
            sops = {
                defaultSopsFile = ../../hosts/${hostname}/secrets.yaml;
                validateSopsFiles = false;
                
                age = {
                    sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
                    keyFile = "/var/lib/sops-nix/key.txt";
                    generateKey = true;
                };
                
                secrets = {
                    privateKey = {
                        path = "/home/${user.name}/.ssh/id_${user.name}";
                        owner = user.name;
                        mode = "0600";
                    };
                };
            };
        };
    };
}