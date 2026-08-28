{
  flake.modules.nixos.bluetooth =
    { pkgs, ... }:
    {
      config = {
        environment.persistence."/persist".directories = [ "/var/lib/bluetooth" ];

        hardware.bluetooth = {
          enable = true;
          powerOnBoot = true;
          settings.General.FastConnectable = true;
          settings.Policy.AutoEnable = true;
        };

        environment.systemPackages = [
          pkgs.bluez-tools
        ];
      };
    };
}
