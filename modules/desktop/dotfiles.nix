{ ... }:
{
    flake.modules.homeManager.dotfiles = { config, host, ... }:
    let
        inherit (host) hostname;
        inherit (config.lib.file) mkOutOfStoreSymlink;
        inherit (config.home) homeDirectory;
        
        # https://gist.github.com/mawkler/195def384fd3f73aeb9a965c82781483
        mkSymlinks = storePath: realPath:
        let 
            readDirRecursive = relativePath: nixPath:
            let 
                entries = builtins.readDir nixPath;
                names = builtins.attrNames entries;
            in
                builtins.concatLists (map (name:
                let
                    relativePath' =
                        if relativePath == ""
                        then name
                        else "${relativePath}/${name}";
                    nixPath' = "${nixPath}/${name}";
                in
                    if entries.${name} == "directory"
                    then readDirRecursive relativePath' nixPath'
                    else [ relativePath' ]
                ) names);
            
            mkSymLink = nixPath: lib.nameValuePair nixPath {
                source = mkOutOfStoreSymlink "${realPath}/${nixPath}";
            };
        in
            builtins.listToAttrs (map mkSymLink (readDirRecursive "" storePath));
    in
    {
        home.file = mkSymlinks
            ../../hosts/${hostname}/home
            "${homeDirectory}/nixos-config/hosts/${hostname}/home";
    };
}