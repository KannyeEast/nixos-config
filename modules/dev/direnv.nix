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
        
        # https://stackoverflow.com/questions/79371917/direnv-printing-environment-diff-even-with-hide-env-diff-true
        environment.etc."direnv/direnv.toml".text = ''
          [global]
          hide_env_diff = true
        '';
      };
    };
}
