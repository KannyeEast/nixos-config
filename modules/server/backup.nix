{ lib, ... }:
let
  inherit (lib)
    attrValues
    concatMap
    concatMapAttrs
    concatStringsSep
    filter
    filterAttrs
    hasPrefix
    hasSuffix
    mapAttrs
    mapAttrs'
    mapAttrsToList
    nameValuePair
    optionalAttrs
    removeSuffix
    unique
    ;
in
{
  flake.modules.nixos.server =
    { config, pkgs, ... }:
    let
      # same principle as networking.nix; read and store plain key values 
      targets = (builtins.fromJSON (builtins.readFile config.sops.defaultSopsFile)).backup or { };

      # sops-nix can also leave values unencrypted with this suffix; useful when values need to be read at eval 
      rmSuffix = mapAttrs' (name: value: nameValuePair (removeSuffix "_unencrypted" name) value);

      # check if key has env associated with it
      envOf = data: data.env or { };
      secretEnv = filterAttrs (key: _: !hasSuffix "_unencrypted" key);

      mkEnv =
        name: env:
        concatStringsSep "\n" (
          mapAttrsToList (
            key: value:
            if hasSuffix "_unencrypted" key then
              "${removeSuffix "_unencrypted" key}='${value}'"
            else
              "${key}='${config.sops.placeholder."backup/${name}/env/${key}"}'"
          ) env
        );
        
        # grab all populated entries for the services.backup option
        backups = filter (service: service.backup.paths != [ ]) (attrValues config.internal.services);

        # map it all into 1 list
        paths = unique (concatMap (service: service.backup.paths) backups); 
        exclude = unique (concatMap (service: service.backup.exclude) backups);
    in
    {
      config = {
        # a server requires an outside connection
        assertions = [
          {
            assertion = targets == { } || paths != [ ];
            message = "backup: targets configured but no service declares backup.paths";
          }
        ];
      
        sops.secrets = concatMapAttrs (
          name: data:
          {
            "backup/${name}/password" = { };
          }
          // concatMapAttrs (key: _: { "backup/${name}/env/${key}" = { }; }) (secretEnv (envOf data))
        ) targets;

        sops.templates = mapAttrs' (
          name: data: nameValuePair "restic-${name}.env" { content = mkEnv name (envOf data); }
        ) (filterAttrs (_: data: envOf data != { }) targets);

        internal.system.impermanence.directories = [
          "/root/.cache/restic"
        ];

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

            inherit paths;
            inherit exclude;
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
            
            # backupCleanupCommand = ''
            #   ${pkgs.coreutils}/bin/cat > ${dir}/restic-${name}.prom.tmp <<EOF
            #   # HELP restic_last_success_timestamp_seconds When this target last completed.
            #   # TYPE restic_last_success_timestamp_seconds gauge
            #   restic_last_success_timestamp_seconds{target="${name}"} $(${pkgs.coreutils}/bin/date +%s)
            #   EOF
            #   ${pkgs.coreutils}/bin/mv ${dir}/restic-${name}.prom.tmp ${dir}/restic-${name}.prom
            # '';
          }
          // optionalAttrs (hasPrefix "/" target.repository) {
            checkOpts = [ "--read-data-subset=5%" ];
          }
          // optionalAttrs (envOf data != { }) {
            environmentFile = config.sops.templates."restic-${name}.env".path;
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
