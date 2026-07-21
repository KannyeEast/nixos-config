{ inputs, ... }:
{
    flake.modules.nixos.impermanence = { host, ... }:
    let
        inherit (host) user;
    in  
    {
        imports = [
            inputs.impermanence.nixosModules.impermanence
        ];
        
        config = {
            environment.persistence."/persist" = {
                hideMounts = true;
                directories = [
                    "/var/lib/bluetooth"
                    "/var/lib/NetworkManager"
                    "/var/lib/nixos"
                    "/var/lib/systemd"
                    "/var/log"
                ];
                files = [
                    "/etc/machine-id"
                ];
            };
        };
    };
}