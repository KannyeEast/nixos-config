{ lib, ... }:
let
    inherit (lib) mkOption mkIf types;
in
{
    flake.modules.nixos.user = { config, pkgs, host, ... }:
    let
        inherit (config.profile) user;
        inherit (host) username;
    in
    {
        options = {
            profile.user = {
                hashedPasswordFile = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = ''
                    -- If left at default the system will fallback to the initial password --
                    Set the path to of your passwords file
                    '';
                };
            };
        };
        
        config = {
            users.mutableUsers = false;
            
            # Create user profile
            users.users.${username} = {
                isNormalUser = true;
                home = "/home/${username}";
                extraGroups = [
                    "wheel"             # sudo/root privileges
                    "networkmanager"    # network configuration
                ];
                
                # @TODO: Need a better approach to this
                hashedPasswordFile = mkIf (user.hashedPasswordFile != null) user.hashedPasswordFile;
                initialPassword = mkIf (user.hashedPasswordFile == null) "nixos";
                
                shell = pkgs.zsh;
            };
            
            services.openssh = {
                enable = true;
                openFirewall = true;
            };
            
            programs.zsh.enable = true;
            
            nix.settings.trusted-users = [
                "root"
                "@wheel"
            ];
        };
    };
}

