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

            # sops cannot use an ssh ed25519 key directly against age
            # recipients (getsops/sops#1999, fix unmerged) - derive the age
            # identity on the fly instead. Takes effect on (re)login
            environment.sessionVariables.SOPS_AGE_KEY_CMD =
                "ssh-to-age -private-key -i /home/${user.name}/.ssh/id_${user.name}";
        
            sops = {
                defaultSopsFile = ../../hosts/${hostname}/secrets.json;

                # "yaml" on purpose, even though the file is JSON: sops-nix's
                # nested-key lookup (wifi/<net>/...) only handles YAML-style
                # maps and aborts the ENTIRE secret installation on JSON
                # (recurseSecretKey in sops-install-secrets, broken upstream
                # as of 2026-07). JSON is valid YAML, so the yaml parser
                # reads the same file fine and networking.nix can keep using
                # builtins.fromJSON for eval-time enumeration
                defaultSopsFormat = "yaml";
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