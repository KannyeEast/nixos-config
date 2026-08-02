{ lib, ... }:
{
  flake.modules.homeManager.dotfiles =
    { config, host, ... }:
    let
      inherit (host) hostname repoPath;
      inherit (config.lib.file) mkOutOfStoreSymlink;

      # hosts/<host>/home mirrors $HOME itself:
      #   home/.zshrc              -> ~/.zshrc
      #   home/.config/niri/...    -> ~/.config/niri/...
      #   home/some/custom/dir/... -> ~/some/custom/dir/...
      dotfilesDir = ../../hosts/${hostname}/home;

      # https://gist.github.com/mawkler/195def384fd3f73aeb9a965c82781483
      mkSymlinks =
        storePath: realPath:
        let
          readDirRecursive =
            relativePath: nixPath:
            let
              entries = builtins.readDir nixPath;
              names = builtins.attrNames entries;
            in
            builtins.concatLists (
              map (
                name:
                let
                  relativePath' = if relativePath == "" then name else "${relativePath}/${name}";
                  nixPath' = "${nixPath}/${name}";
                in
                if entries.${name} == "directory" then
                  readDirRecursive relativePath' nixPath'
                else
                  [ relativePath' ]
              ) names
            );

          mkSymLink =
            nixPath:
            lib.nameValuePair nixPath {
              source = mkOutOfStoreSymlink "${realPath}/${nixPath}";
            };
        in
        builtins.listToAttrs (map mkSymLink (readDirRecursive "" storePath));
    in
    {
      # home.file is $HOME-relative (xdg.configFile would nest everything
      # under ~/.config). pathExists guards fresh hosts - git does not
      # track empty directories, so home/ may not exist after a clone
      home.file = lib.optionalAttrs (builtins.pathExists dotfilesDir) (
        mkSymlinks dotfilesDir "${repoPath}/hosts/${hostname}/home"
      );
    };
}
