{ inputs, ... }:
{
  flake.modules.nixos.system =
    {
      config,
      flake,
      host,
      user,
      cluster,
      ...
    }:
    let
      inherit (config.internal)
        system
        ;
    in
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      config = {
        home-manager = {
          useUserPackages = true;
          useGlobalPkgs = true;
          backupFileExtension = "backup";
          extraSpecialArgs = {
            inherit
              inputs
              flake
              host
              user
              cluster
              ;
          };
          users.${user.name} = {
            home = {
              username = user.name;
              homeDirectory = config.users.users.${user.name}.home;

              stateVersion = system.version;
            };
          };
        };
      };
    };
}
