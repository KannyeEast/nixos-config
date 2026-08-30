{ lib, ... }:
let
  inherit (lib)
    concatMapAttrs
    concatStringsSep
    filterAttrs
    hasPrefix
    hasSuffix
    mapAttrs
    mapAttrs'
    mapAttrsToList
    mkOption
    nameValuePair
    optionalAttrs
    removeSuffix
    types
    ;
in
{
  flake.modules.nixos.backup =
    { config, pkgs, ... }:
    let
      inherit (config.internal)
        server
        ;

      targets = (builtins.fromJSON (builtins.readFile config.sops.defaultSopsFile)).backup or { };

      rmSuffix = mapAttrs' (name: value: nameValuePair (removeSuffix "_unencrypted" name) value);

      envOf = data: data.env or { };
      secretEnv = filterAttrs (k: _: !hasSuffix "_unencrypted" k);

      mkEnv =
        name: env:
        concatStringsSep "\n" (
          mapAttrsToList (
            k: value:
            if hasSuffix "_unencrypted" k then
              "${removeSuffix "_unencrypted" k}='${value}'"
            else
              "${k}='${config.sops.placeholder."backup/${name}/env/${k}"}'"
          ) env
        );
    in
    {
      options = {
        internal.server.backup = {
          paths = mkOption {
            type = types.listOf types.str;
            default = [ ];
            internal = true;
            description = "Paths included in every backup target";
          };
          exclude = mkOption {
            type = types.listOf types.str;
            default = [ ];
            internal = true;
            description = "Paths excluded from every backup target";
          };
        };
      };

      config = {
        sops.secrets = concatMapAttrs (
          name: data:
          {
            "backup/${name}/password" = { };
          }
          // optionalAttrs (data ? healthcheck) { "backup/${name}/healthcheck" = { }; }
          // concatMapAttrs (k: _: { "backup/${name}/env/${k}" = { }; }) (secretEnv (envOf data))
        ) targets;

        sops.templates = mapAttrs' (
          name: data: nameValuePair "restic-${name}.env" { content = mkEnv name (envOf data); }
        ) (filterAttrs (_: data: envOf data != { }) targets);

        internal.system.impermanence.directories = [
          "/root/.cache/restic"
        ];

        internal.server.backup = {
          paths = [
            "/persist"
          ];
          exclude = [
            "/persist/home/*/.cache"
            "/persist/var/cache"
          ];
        };

        environment.systemPackages = [
          pkgs.restic
          pkgs.rclone
        ];

        services.restic.backups = mapAttrs (
          name: data:
          let
            target = rmSuffix data;
          in
          {
            initialize = true;
            repository = target.repository;
            passwordFile = config.sops.secrets."backup/${name}/password".path;

            paths = server.backup.paths;
            exclude = server.backup.exclude;
            pruneOpts = [
              "--keep-daily 7"
              "--keep-weekly 5"
              "--keep-monthly 12"
              "--keep-yearly 75"
            ];

            timerConfig = {
              OnCalendar = target.schedule;
              RandomizedDelaySec = "20m";
              Persistent = true;
            };
          }
          // optionalAttrs (hasPrefix "/" target.repository) {
            checkOpts = [ "--read-data-subset=5%" ];
          }
          // optionalAttrs (envOf data != { }) {
            environmentFile = config.sops.templates."restic-${name}.env".path;
          }
          // optionalAttrs (data ? healthcheck) {
            backupCleanupCommand = ''
              ${pkgs.curl}/bin/curl -fsS -m 10 --retry 3 \
              "$(cat ${config.sops.secrets."backup/${name}/healthcheck".path})"
            '';
          }
        ) targets;

        systemd.services = concatMapAttrs (
          name: data:
          optionalAttrs (hasPrefix "/" (rmSuffix data).repository) {
            "restic-backups-${name}".unitConfig.RequiresMountsFor = (rmSuffix data).repository;
          }
        ) targets;
      };
    };
}
