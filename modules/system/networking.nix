{ lib, ... }:
let
    inherit (lib) mkMerge mkIf mapAttrs mapAttrsToList listToAttrs nameValuePair
    flatten toUpper concatMapStrings concatStringsSep stringToCharacters;
in
{
    flake.modules.nixos.networking = { config, host, ... }:
    let
        inherit (host) hostname;
        inherit (config) sops;
        
        # Read the structure of the wifi section of the encrypted file   
        networkAttributes = 
             (builtins.fromJSON (builtins.readFile sops.defaultSopsFile)).wifi or { };
        
        # Transforms the sops value path to a valid env variable 
        # "wifi/cafe/wifi-security/psk" -> "WIFI_CAFE_WIFI_SECURITY_PSK"
        sopsToEnv = s: toUpper (concatMapStrings
            (c: if builtins.match "[A-Za-z0-9]" c != null then c else "_")
            (stringToCharacters s)
        );
        
        # Do this 3 times as networking.networkmanager.ensureProfiles.profiles is 3 levels deep  
        # <wifi_name>.connection.id
        # before flatten:
        # [ [ [ {net="cafe"; section="wifi"; key="ssid";} 
        #       {net="cafe"; section="wifi"; key="hidden";} ]
        #     [ {net="cafe"; section="wifi-security"; key="key-mgmt";}
        #       {net="cafe"; section="wifi-security"; key="psk";} ] ] ]
        # 
        # after flatten:
        # [ {net="cafe"; section="wifi"; key="ssid";}
        #   {net="cafe"; section="wifi"; key="hidden";}
        #   {net="cafe"; section="wifi-security"; key="key-mgmt";}
        #   {net="cafe"; section="wifi-security"; key="psk";} ]
        networkEntries = flatten (mapAttrsToList (net: sections:
            mapAttrsToList (section: keys:
                mapAttrsToList (key: _: { inherit net section key; }) keys
            ) sections
        ) networkAttributes);
        
        # Where is the file
        sopsKey = f: "wifi/${f.net}/${f.section}/${f.key}"; 
        # What is the name of it
        envVar = f: "WIFI_${sopsToEnv f.net}_${sopsToEnv f.section}_${sopsToEnv f.key}";
    in
    {
        config = mkMerge [
            {
                networking.hostName = hostname;
                networking.networkmanager.enable = true;
            }
            
            (mkIf (networkAttributes != { }) {
                sops.secrets = listToAttrs
                    (map (f: nameValuePair (sopsKey f) { }) networkEntries);
                    
                sops.templates."wifi.env" = {
                    content = concatStringsSep "\n" (map (f:
                        "${envVar f}='${sops.placeholder.${sopsKey f}}'"
                    ) networkEntries);
                    format = "json";
                    restartUnits = [ "NetworkManager-ensure-profiles.service" ];
                };
                
                networking.networkmanager.ensureProfiles = {
                    environmentFiles = [ sops.templates."wifi.env".path ];
                    
                    profiles = mapAttrs (net: sections:
                        {
                            connection = {
                                id = net;
                                type = "wifi";
                            };
                        } // mapAttrs (section: keys:
                            mapAttrs (key: _:
                                "$" + envVar { inherit net section key; }
                            ) keys
                        ) sections
                    ) networkAttributes;
                };
            })
        ];
    };
}