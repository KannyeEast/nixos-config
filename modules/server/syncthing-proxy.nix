{
  flake.modules.nixos.syncthingProxy = {
    internal.server.proxy.services.syncthing = {
      port = 8384;
    };
  };
}
