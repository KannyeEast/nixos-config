{ lib, ... }:
let
  inherit (lib)
    getExe
    mkForce
    mkIf
    optional
    optionals
    ;
in
{
  flake.modules.nixos.virt =
    {
      config,
      pkgs,
      utils,
      host,
      ...
    }:
    let
      docker = config.virtualisation.docker;
    in
    {
      config = mkIf (host.class == "desktop") {
        virtualisation.docker = {
          enable = mkForce false;
          rootless = {
            enable = true;
            setSocketVariable = true; 
          };

          # these only drive the unit below
          autoPrune = {
            enable = true;
            dates = "weekly";
          };
        };

        environment.systemPackages = [
          pkgs.docker-compose
        ];
        
        # docker.autoPrune by default only works when run with the rootful daemon
        # this mirrors the rootful daemon's autoprune service; tweaked for the rootless daemon
        systemd.user.services.docker-prune = {
          description = "Prune docker resources";
          
          restartIfChanged = false;
          unitConfig.X-StopOnRemoval = false;
          
          startAt = optional docker.autoPrune.enable docker.autoPrune.dates;
          after = [ "docker.service" ];
          requires = [ "docker.service" ];
          
          serviceConfig = {
            Type = "oneshot";

            Environment = "DOCKER_HOST=unix://%t/docker.sock";
            ExecStart = [
              (utils.escapeSystemdExecArgs (
                [
                  (getExe docker.rootless.package)
                  "system"
                  "prune"
                  "-f"
                ]
                ++ docker.autoPrune.flags
              ))
            ]
            ++ (optionals docker.autoPrune.allVolumes.enable [
              (utils.escapeSystemdExecArgs (
                [
                  (getExe docker.rootless.package)
                  "volume"
                  "prune"
                  "--force"
                  "--all"
                ]
                ++ docker.autoPrune.allVolumes.flags
              ))
            ]);
          };
        };

        systemd.user.timers.docker-prune = mkIf docker.autoPrune.enable {
          timerConfig = {
            Persistent = docker.autoPrune.persistent;
            RandomizedDelaySec = docker.autoPrune.randomizedDelaySec;
          };
        };
      };
    };
}
