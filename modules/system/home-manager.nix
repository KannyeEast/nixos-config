{ inputs, ... }:
{
  flake.modules.nixos.homeManager =
    {
      config,
      flake,
      host,
      user,
      hardware,
      locale,
      network,
      ...
    }:
    let
      inherit (config.internal)
        system
        ;
    in
    {
      imports = [
        inputs.home-manager.nixosModules.home-manager
      ];

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
              hardware
              locale
              network
              ;
          };
          users.${user.name} = {
            home = {
              username = user.name;
              homeDirectory = "/home/${user.name}";

              # Home-manager version
              stateVersion = system.version;
            };
          };
        };
      };
    };
}
