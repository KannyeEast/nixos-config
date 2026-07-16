{ lib, ... }:
let
    inherit (lib) mkMerge mkIf;
in
{
    flake.modules.nixos.networking = { config, host, ... }:
    let
        inherit (host) hostname user;
        
        # JSON to nix the wifi section of the encrypted secrets.json or nothing if it doesnt exist
        wifiSecrets = (builtins.fromJSON (builtins.readFile config.sops.defaultSopsFile)).wifi or { };
        
        # Flatten a nested attrset into a list of "/"-joined paths
        # FROM: cafe = { wifi = { ssid=[ENC]; }; wifi-security = { psk=[ENC]; }; };
        # TO: [ "cafe/wifi/ssid" "cafe/wifi-security/psk" ]
        flattenPaths = prefix: attrs: lib.flatten (
            lib.mapAttrsToList (name: value:
                let path = "${prefix}/${name}";
                in if lib.isAttrs value then flattenPaths path value else [ path ]
            ) attrs
        );
        
        wifiPaths = flattenPaths "wifi" wifiSecrets;
        
        # Turn a path string into an env var name
        # FROM: "wifi/cafe/wifi-security/psk"
        # TO: "WIFI_CAFE_WIFI_SECURITY_PSK"
        pathToEnv = string:
            toUpper (lib.stringAsChars (c:
                if builtins.match "[A-Za-z0-9]" c != null
                then c
                else "_"
            ) string);

    in
    {
        config = mkMerge [
            {
                networking.hostName = hostname;
                networking.networkmanager.enable = true;
            }
            
            (mkIf (wifiSecrets != { }) {
                # Initialize secret for each entry
                sops.secrets =
                    wifiPaths
                    |> map (p: lib.nameValuePair p { })
                    |> lib.listToAttrs;
                
                sops.templates."wifi.env" = {
                    # WIFI_CAFE_WIFI_SECURITY_PSK = "${sops.placeholder."wifi/cafe/wifi-security/psk"}"
                    content =
                        wifiPaths
                        |> map (p: "${pathToEnv p}='${config.sops.placeholder.${p}}'")
                        |> lib.concatStringsSep "\n";
                    owner = user.name;
                    restartUnits = [ "NetworkManager-ensure-profiles.service" ];
                };
                
                networking.networkmanager.ensureProfiles = {
                    environmentFiles = [ config.sops.templates."wifi.env".path ];
                    
                    profiles = lib.mapAttrs (name: sections:
                        { connection = { id = name; type = "wifi"; }; }
                        // lib.mapAttrs (section: keys:
                            lib.mapAttrs (key: _:
                                "$" + pathToEnv "wifi/${name}/${section}/${key}"
                            ) keys
                        ) sections
                    ) wifiSecrets;
                };
            })
        ];
    };
}