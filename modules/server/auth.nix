{ lib, ... }:
let
  inherit (lib) 
    optionalAttrs
    mapAttrsToList
    ;
in
{
  flake.modules.nixos.auth = 
  { config, user, network, ... }:
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
          
          session.cookies = [{
            domain = network.domain;
            authelia_url = "https://auth.${network.domain}";
            default_redirection_url = "https://${network.domain}";
          }];
          
          storage.local.path = "/var/lib/authelia-main/db.sqlite3";
          notifier.filesystem.filename = "/var/lib/authelia-main/notifications.txt";
          
          access_control = {
            default_policy = "deny";
            rules = mapAttrsToList (
              name: service: {
              domain = "${service.subdomain}.${network.domain}";
              policy = service.policy;
            }
            // optionalAttrs (service.policy != "bypass" && service.groups != [ ]) {
              subject = map (group: [ "group:${group}" ]) service.groups;
            }) config.internal.server.proxy.services;
          }; 
        };
      };
      
      internal.server.proxy.services.auth = {
        port = 9091;
        policy = "bypass";
      };
    };
  };
}