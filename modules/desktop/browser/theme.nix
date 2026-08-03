{ ... }:
{
  # Zen's accent is a pref rather than a config file, so flavours cannot write
  # it. Instead flavours mirrors the scheme to palette.json and Nix reads that,
  # keeping the yaml scheme the single source.
  flake.modules.homeManager.browserTheme =
    { host, ... }:
    let
      palette = builtins.fromJSON (
        builtins.readFile ../../../hosts/${host.hostname}/home/.config/nix/zen.json
      );
    in
    {
      config = {
        programs.zen-browser.profiles.default.settings = {
          # base0C is the cyan accent slot.
          # @TODO: verify this is what Zen actually reads. Per-space `theme`
          # in tabs.nix may override it entirely, in which case this is dead.
          "zen.theme.accent-color" = palette.hex.base0C;

          # gradient is on by default; show-custom-colors is what makes it
          # honour a flat hex instead of generating its own
          "zen.theme.gradient" = true;
          "zen.theme.gradient.show-custom-colors" = true;
        };
      };
    };
}
