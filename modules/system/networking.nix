{ lib, ... }:
let
  inherit (lib)
    concatStringsSep
    flatten
    isAttrs
    listToAttrs
    mapAttrs
    mapAttrsToList
    mkIf
    mkMerge
    nameValuePair
    stringAsChars
    toUpper
    ;
in
{
  flake.modules.nixos.system =
    {
      config,
      host,
      ...
    }:
    let
      # sops-nix only encrypts values and not the keys; parsing it at eval time allows one to mimic the shape
      # of the wifi section networkmanager expects, while keeping the values protected until they arrive during runtime
      # through the below created .env file
      # SSID's are used as unique key identifiers so they do end up in the nix store
      wifiSecrets = (builtins.fromJSON (builtins.readFile config.sops.defaultSopsFile)).wifi or { };

      # flatten a nested attribute set into a list of "/"-joined paths
      # which is what sops.secrets and sops.placeholder are keyed by
      # FROM: cafe = { wifi = { ssid = [ENC]; }; wifi-security = { psk = [ENC]; }; };
      # TO: [ "cafe/wifi/ssid" "cafe/wifi-security/psk" ]
      flattenPaths =
        prefix: attrs:
        flatten (
          mapAttrsToList (
            name: value:
            let
              path = "${prefix}/${name}";
            in
            if isAttrs value then flattenPaths path value else [ path ]
          ) attrs
        );

      wifiPaths = flattenPaths "wifi" wifiSecrets;

      # turn a secret path into an env var name; spaces and other non-alphanumeric characters become _
      # FROM: "wifi/cafe/wifi-security/psk"
      # TO: "WIFI_CAFE_WIFI_SECURITY_PSK"
      pathToEnv =
        string:
        toUpper (
          stringAsChars (char: if builtins.match "[A-Za-z0-9]" char != null then char else "_") string
        );
    in
    {
      # https://networkmanager.dev/docs/api/latest/nm-settings-keyfile.html
      config = mkMerge [
        {
          networking.hostName = host.name;
          networking.networkmanager.enable = true;
        }

        (mkIf (wifiSecrets != { }) {
          # one secret per top leaf
          sops.secrets = listToAttrs (map (path: nameValuePair path { }) wifiPaths);

          # creates a single .env file networkmanager read at profile-apply time
          # WIFI_CAFE_WIFI_SECURITY_PSK = "${sops.placeholder."wifi/cafe/wifi-security/psk"}"
          sops.templates."wifi.env" = {
            content = concatStringsSep "\n" (
              map (path: "${pathToEnv path}='${config.sops.placeholder.${path}}'") wifiPaths
            );
            restartUnits = [ "NetworkManager-ensure-profiles.service" ];
          };

          networking.networkmanager.ensureProfiles = {
            environmentFiles = [ config.sops.templates."wifi.env".path ];

            # rebuild each profile from the secrets.json shape
            # each entry is replaced by the $VAR networkmanager will expand on
            profiles = mapAttrs (
              name: sections:
              {
                connection = {
                  id = name;
                  type = "wifi";
                };
              }
              // mapAttrs (
                section: keys: mapAttrs (key: _: "$" + pathToEnv "wifi/${name}/${section}/${key}") keys
              ) sections
            ) wifiSecrets;
          };
        })
      ];
    };
}
