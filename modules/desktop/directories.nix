{ ... }:
{
    flake.modules.homeManager.directories = { host, ... }:
    let 
        inherit (host) user;
    in
    {
        xdg.userDirs = {
            enable = true;
            createDirectories = true;
            
            desktop = "home/${user.name}/Desktop";
            documents = "home/${user.name}/Documents";
            download = "home/${user.name}/Downloads";
            music = "home/${user.name}/Music";
            pictures = "home/${user.name}/Pictures";
            publicShare = "home/${user.name}/Public";
            templates = "home/${user.name}/Templates";
            videos = "home/${user.name}/Videos";
            
            extraConfig = {
                games = "home/${user.name}/Games";
                # misc = "${home}/Misc";
                # projects = "${home}/Projects";
                screencasts = "home/${user.name}/Videos/screencasts";
                screenshots = "home/${user.name}/Pictures/screenshots";
                wallpapers = "home/${user.name}/Pictures/wallpapers";
            };
        };
    };
}