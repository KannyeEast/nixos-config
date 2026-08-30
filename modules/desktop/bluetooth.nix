{
  flake.modules.nixos.bluetooth =
    { pkgs, ... }:
    {
      config = {
        internal.system.impermanence.directories = [
          "/var/lib/bluetooth"
        ];

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
