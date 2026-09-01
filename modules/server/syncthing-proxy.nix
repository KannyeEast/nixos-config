{
  flake.modules.nixos.syncthingProxy =
    { ... }:
    {
      config.internal.server.proxy.services.syncthing = {
        port = 8384;
      };
    };
}
