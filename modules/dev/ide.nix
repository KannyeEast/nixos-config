{ inputs, lib, ... }:
let
  inherit (lib)
    mkIf
    ;
in
{
  flake.modules.nixos.dev =
    { host, pkgs, ... }:
    let
      inherit (inputs.nix-jetbrains-plugins.lib)
        buildIdeWithPlugins
        ;

      sharedPlugins = [
        "com.chrisrm.idea.MaterialThemeUI"
        "com.mallowigi"
        "com.fapiko.jetbrains.plugins.better_direnv"
      ];
    in
    {
      config = mkIf (host.class == "desktop") {
        environment.systemPackages = [
          pkgs.jetbrains-toolbox
          # (buildIdeWithPlugins pkgs "clion" sharedPlugins)
          # (buildIdeWithPlugins pkgs "pycharm" sharedPlugins)
          (buildIdeWithPlugins pkgs "rider" (
            [
              "nix-idea"
              "com.intellij.lang.qml"
            ]
            ++ sharedPlugins
          ))
          (buildIdeWithPlugins pkgs "webstorm" sharedPlugins)
        ];
      };
    };
}
