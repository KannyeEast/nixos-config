{ lib, ... }:
let
    inherit (lib) concatMapStringsSep;
in
{
    flake.modules.homeManager.git = { config, host, ... }:
    let
        inherit (host) user;
    in
    {
        config = {
            home.file.".ssh/allowed_signers".text =
                concatMapStringsSep "\n" (key: "${user.email} ${key}") user.sshKeys + "\n";
        
            programs.git = {
                enable = true;
                
                signing = {
                    format = "ssh";
                    signByDefault = true;
                    key = "${config.home.homeDirectory}/.ssh";
                };
                
                settings = {
                    user.name = user.name;
                    user.email = user.email;
                    init.defaultBranch = "main";
                    gpg.ssh.allowedSignersFile = "${config.home.homeDirectory}/.ssh/allowed_signers";

                    url = {
                        "ssh://git@github.com/".insteadOf = "https://github.com/:";
                        "https://gitlab.com/".insteadOf = "gitlab:";
                        "https://codeberg.org/".insteadOf = "codeberg:";
                    };
                };
            };
            
            programs.shh = {
                enable = true;
                matchBlocks."github.com" = {
                    identityFile = [
                        "${config.home.homeDirectory}/.ssh/id_${user.name}"
                        "${config.home.homeDirectory}/.config/sops/age/id_admin" # @TODO@TEMP: Temporary admin key for ssh auth >> Remove when system stable
                    ];
                    identitiesOnly = true;
                };
            };
            
            # For now also GitHub
            programs.gh.enable = true;
        };
    };
}