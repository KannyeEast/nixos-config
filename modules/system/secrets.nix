{ inputs, ... }: 
{
    flake.modules.nixos.secrets = { host, ... }:
    let
        inherit (host) hostname username;
    in
    {
        imports = [
            inputs.sops-nix.nixosModules.sops
        ];
    
        config = {
            sops.defaultSopsFile = ../../secrets/${hostname}.yaml;
            sops.age.keyFile = "/home/${username}/.config/sops/age/keys.txt";
        };
    };
    
    # @TODO: Do we create this file on rebuild in a loop (for each host this is his key and this his path), or just manually append it for each new host
    perSystem = _: {
        files.file.".sops.yaml".text = ''
            keys:
                - &${hostname} ${key}
            creation_rules:
                - path_regex: secrets/${hostname}\.(yaml|json|env|ini)$
                  key_groups:
                    - age:
                        - *${hostname}
        '';
    };
}