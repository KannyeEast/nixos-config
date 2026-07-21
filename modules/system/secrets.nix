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
    
        # @TODO: Shared sops file (secrets/shared.json) encrypted to admin + all
        config = {
            environment.systemPackages = [
                pkgs.sops
                pkgs.ssh-to-age
            ];

            environment.sessionVariables.SOPS_AGE_KEY_CMD = "ssh-to-age -private-key -i /home/${user.name}/.ssh/id_${user.name}";
        
            sops = {
                defaultSopsFile = ../../hosts/${hostname}/secrets.json;

                defaultSopsFormat = "yaml";
                validateSopsFiles = false;
                
                age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
                
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