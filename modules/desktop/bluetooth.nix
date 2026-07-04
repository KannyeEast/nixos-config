{ ... }:
{
    flake.modules.nixos.bluetooth = { pkgs, ... }:
    {
        hardware.bluetooth = {
            enable = true;
            powerOnBoot = true;
            settings.General.FastConnectable = true;
            settings.Policy.AutoEnable = true;
        };
                    
        environment.systemPackages = [
           pkgs.bluez 
           pkgs.bluez-tools                             
        ];
    };
}