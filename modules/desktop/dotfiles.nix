{ ... }:
{
    flake.modules.homeManager.dotfiles = { config, host, ... }:
    let
        inherit (host) hostname;
        inherit (config.lib.file) mkOutOfStoreSymlink;
        inherit (config.home) homeDirectory;
        
        # https://gist.github.com/mawkler/195def384fd3f73aeb9a965c82781483
        mkSymlinks = configsAbsolutePath: configsNixPath:
        let
            mkSymLink = nixPath: {
                name = nixPath;
                value.source = mkOutOfStoreSymlink "${configsNixPath}/${nixPath}";
            };
            
            readDirRecursive = relativePath: nixPath:
            let 
                entries = builtins.readDir nixPath;
                names = builtins.attrNames entries;
            in
                builtins.concatLists (map (name:
                let
                    entryType = entries.${name};
                    relativePath' =
                        if relativePath == ""
                        then name
                        else "${relativePath}/${name}";
                    nixPath' = "${nixPath}/${name}";
                in
                    if entryType == "directory"
                    then readDirRecursive relativePath' nixPath'
                    else [ relativePath' ]
                ) names);
        in
            builtins.listToAttrs (map mkSymLink (readDirRecursive "" configsAbsolutePath));
    in
    {
        xdg.configFile = mkSymlinks
            ../../hosts/${hostname}/dotfiles
            "${homeDirectory}/nixos-config/hosts/${hostname}/dotfiles";
    };
}