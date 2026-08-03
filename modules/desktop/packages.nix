{ ... }:
{
  flake.modules.nixos.packages =
    { pkgs, ... }:
    {
      config = {
        environment.systemPackages = [
          pkgs.flavours
          pkgs.keepassxc
        ];
      };
    };
}
