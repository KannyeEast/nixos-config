{ ... }:
{
  flake.modules.homeManager.directories =
    { config, ... }:
    let
      inherit (config) home;
    in
    {
      xdg.userDirs = {
        enable = true;
        createDirectories = true;

        desktop = "${home.homeDirectory}/Desktop";
        documents = "${home.homeDirectory}/Documents";
        download = "${home.homeDirectory}/Downloads";
        music = "${home.homeDirectory}/Music";
        pictures = "${home.homeDirectory}/Pictures";
        publicShare = "${home.homeDirectory}/Public";
        templates = "${home.homeDirectory}/Templates";
        videos = "${home.homeDirectory}/Videos";

        extraConfig = {
          # games = "${home.homeDirectory}/Games";
          # misc = "${home}/Misc";
          # projects = "${home}/Projects";
          screencasts = "${home.homeDirectory}/Videos/screencasts";
          screenshots = "${home.homeDirectory}/Pictures/screenshots";
          wallpapers = "${home.homeDirectory}/Pictures/wallpapers";
        };
      };
    };
}
