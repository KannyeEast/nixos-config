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
            fileSystems."/persistent".neededForBoot = true;

            environment.persistence."/persistent" = {
                hideMounts = true;
                directories = [
                    # "/home/${user.name}"
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