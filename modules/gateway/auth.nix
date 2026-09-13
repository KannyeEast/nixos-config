{ lib, ... }:
let
  inherit (lib)
    filterAttrs
    mapAttrsToList
    ;
in
{
  flake.modules.nixos.gateway =
    {
      config,
      user,
      cluster,
      ...
    }:
    let
      domain = cluster.domain or (throw "gateway: cluster.json defines no domain");
          
      policyOf = {
        "open" = "bypass";
        "1fa" = "one_factor";
        "2fa" = "two_factor";
        "blocked" = "deny";
      };
      
      # same principle as proxy.nix; only services that arent defined as publicly available will be authenticated
      guarded = filterAttrs (
        _: service: service.route != null && !service.route.hasAuth && service.route.access != "open"
      ) config.internal.services;
    in
    {
      config = {
        sops.secrets = {
          "authelia/admin-hash" = { };
          "authelia/jwt" = { };
          "authelia/session" = { };
          "authelia/storage" = { };
        };

        sops.templates."authelia-seed.yml".content = ''
          users:
            ${user.name}:
              disabled: false
              displayname: "${user.name}"
              password: "${config.sops.placeholder."authelia/admin-hash"}"
              email: ${user.email}
              groups:
                - admin
        '';

        internal.system.impermanence.directories = [
          {
            directory = "/var/lib/authelia-main";
            user = "authelia-main";
            group = "authelia-main";
            mode = "0700";
          }
        ];

        # this is a one-time script to initialize users.yml with the hosts admin-hash; 
        # afterwards its managed by authelia and changes to the admin-hash wont apply
        systemd.services.authelia-main-seed = {
          description = "Seed the Authelia user database";
          wantedBy = [ "multi-user.target" ];
          before = [ "authelia-main.service" ];
          requiredBy = [ "authelia-main.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "authelia-main";
            Group = "authelia-main";
            StateDirectory = "authelia-main";
            StateDirectoryMode = "0700";
            LoadCredential = "seed:${config.sops.templates."authelia-seed.yml".path}";
          };
          script = ''
            if [ ! -e /var/lib/authelia-main/users.yml ]; then
              install -m 0600 "$CREDENTIALS_DIRECTORY/seed" /var/lib/authelia-main/users.yml
            fi
          '';
        };

        services.authelia.instances."main" = {
          enable = true;
          secrets = {
            jwtSecretFile = config.sops.secrets."authelia/jwt".path;
            sessionSecretFile = config.sops.secrets."authelia/session".path;
            storageEncryptionKeyFile = config.sops.secrets."authelia/storage".path;
          };

          settings = {
            theme = "auto";
            server.address = "tcp://127.0.0.1:9091";

            authentication_backend.file.path = "/var/lib/authelia-main/users.yml";

            session.cookies = [
              {
                inherit domain;
                authelia_url = "https://auth.${domain}";
                default_redirection_url = "https://${domain}";
              }
            ];

            storage.local.path = "/var/lib/authelia-main/db.sqlite3";
            notifier.filesystem.filename = "/var/lib/authelia-main/notifications.txt";

            access_control = {
              default_policy = "deny";
              rules = mapAttrsToList (_: service: {
                domain = "${service.route.subdomain}.${domain}";
                policy = policyOf.${service.route.access};
                subject = map (group: [ "group:${group}" ]) service.route.groups;
              }) guarded;
            };
          };
        };

        internal.services.auth = {
          route = {
            port = 9091;
            access = "open";
            hasAuth = true;
          };
        };
      };
    };
}
