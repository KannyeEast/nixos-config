{ config, ... }:
let
    # https://gist.github.com/mawkler/195def384fd3f73aeb9a965c82781483
    mkSymlinks = configsAbsolutePath: configsNixPath:
    let
        inherit (config.lib.file) mkOutOfStoreSymlink;
        
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
                relativePath' = if relativePath == ""
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
    xdg.configFile = mkSymlinks ../config "~/nixos-config/config";
}