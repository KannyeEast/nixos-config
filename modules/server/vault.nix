{
  flake.modules.nixos.vault =
    { config, lib, pkgs, ... }:
    let
      svc = config.internal.services;
      cfg = svc.vault;
    in
    {
      options.internal.services.vault = {
        enable = lib.mkEnableOption "WebDAV vault";
        user = lib.mkOption {
          type = lib.types.str;
          default = "vault";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 8080;
        };
        path = lib.mkOption {
          type = lib.types.str;
          default = "/vault";
        };
        dir = lib.mkOption {
          type = lib.types.path;
          default = "${svc.dataDir}/data/vault";
        };
      };

      config = lib.mkIf cfg.enable {
        users.users.vault = {
          isSystemUser = true;
          group = "vault";
        };
        users.groups.vault = { };

        systemd.tmpfiles.rules = [ "d ${cfg.dir} 0700 vault vault -" ];

        sops.secrets.vaultPassword = { };
        sops.templates."vault.env" = {
          content = ''
            RCLONE_USER=${cfg.user}
            RCLONE_PASS=${config.sops.placeholder.vaultPassword}
          '';
          owner = "vault";
          restartUnits = [ "vault.service" ];
        };

        systemd.services.vault = {
          description = "WebDAV server for the password database";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            User = "vault";
            Group = "vault";
            EnvironmentFile = config.sops.templates."vault.env".path;
            ExecStart = lib.concatStringsSep " " [
              "${pkgs.rclone}/bin/rclone serve webdav ${cfg.dir}"
              "--addr 127.0.0.1:${toString cfg.port}"
              "--baseurl ${cfg.path}"
            ];
            Restart = "on-failure";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            ReadWritePaths = [ cfg.dir ];
          };
        };

        services.caddy.virtualHosts.${svc.domain}.extraConfig = ''
          handle ${cfg.path}* {
            reverse_proxy 127.0.0.1:${toString cfg.port}
          }
        '';
      };
    };
}