{ inputs, ... }:
{
    flake.modules.nixos.ide = { pkgs, ... }:
    let
        inherit (inputs.nix-jetbrains-plugins.lib) buildIdeWithPlugins;
        
        sharedPlugins = [
            "com.chrisrm.idea.MaterialThemeUI"
            "com.mallowigi"
        ];
    in
    { 
        config = {
            environment.systemPackages = [
                pkgs.jetbrains-toolbox
                (buildIdeWithPlugins pkgs "clion" ([ ] ++ sharedPlugins))
                (buildIdeWithPlugins pkgs "pycharm" ([ ] ++ sharedPlugins))
                (buildIdeWithPlugins pkgs "rider" ([ ] ++ sharedPlugins))
                (buildIdeWithPlugins pkgs "webstorm" ([ ] ++ sharedPlugins))
            ];
        };
    };
}