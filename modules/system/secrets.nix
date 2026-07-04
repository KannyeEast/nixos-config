{ inputs, lib, ... }: 
let
    inherit (lib) mkEnableOption mkIf listToAttrs removeSuffix nameValuePair;
in
{
    flake.modules.nixos.secrets = { config, host, ... }:
    let
        inherit (config.internal.user) secrets;
        inherit (host) ageFiles;
    in
    {
        imports = [
            inputs.agenix.nixosModules.default
        ];
        
        options = {
            internal.user.secrets.enable = mkEnableOption "Secrets" // { internal = true; };
        };
    
        config = mkIf secrets.enable {
            age.secrets = listToAttrs (map
            (name: nameValuePair (removeSuffix ".age" name) {
                file = ../../secrets + "/${name}";
            }) ageFiles);
        };
    };
}

# @TODO: Redo this