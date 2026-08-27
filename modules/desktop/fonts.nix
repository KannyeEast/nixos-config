{
  flake.modules.nixos.fonts =
    { pkgs, ... }:
    {
      config = {
        environment.persistence."/persist".directories = [ "/var/cache/fontconfig" ];
      
        fonts = {
          fontDir.enable = true;
          enableDefaultPackages = true;

          packages = [
            pkgs.barlow
            pkgs.inter
            pkgs.noto-fonts
            pkgs.noto-fonts-cjk-sans
            pkgs.noto-fonts-color-emoji
            pkgs.nerd-fonts.jetbrains-mono
          ];

          fontconfig = {
            defaultFonts.serif = [ "Noto Serif" ];
            defaultFonts.sansSerif = [ "Noto Sans" ];
            defaultFonts.monospace = [ "JetBrains Mono" ];
          };
        };
      };
    };
}
