{ ... }:
{
  flake.modules.nixos.direnv =
    { ... }:
    {
      config = {
        programs.direnv = {
          enable = true;
          nix-direnv.enable = true;
        };
      };
    };
}
