{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      config = {
        environment.systemPackages = [
          pkgs.flavours
        ];
      };
    };
}
