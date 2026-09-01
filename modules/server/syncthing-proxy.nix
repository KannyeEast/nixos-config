{
  flake.modules.nixos.syncthingProxy = 
  { config, ... }:
  {
    config.internal.server.proxy.services.syncthing = {
      port = 8384;
    };
  };
}