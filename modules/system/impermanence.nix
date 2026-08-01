{ inputs, ... }:
{
    flake.modules.nixos.impermanence = { ... }:
    {
        imports = [
            inputs.impermanence.nixosModules.impermanence
        ];
        
        config = {
            fileSystems."/persistent".neededForBoot = true;

            environment.persistence."/persistent" = {
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