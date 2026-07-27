{ lib, ... }:
let
    inherit (lib) concatMapStringsSep genAttrs;
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
                    key = "${config.home.homeDirectory}/.ssh/id_${user.name}";
                };
                
                settings = {
                    user.name = user.name;
                    user.email = user.email;
                    init.defaultBranch = "main";
                    gpg.ssh.allowedSignersFile = "${config.home.homeDirectory}/.ssh/allowed_signers";

                    alias = {
                        # @TODO: Make git aliases
                    };

                    url = {
                        "ssh://git@github.com/".pushInsteadOf = "https://github.com/";
                        "ssh://git@codeberg.org/".pushInsteadOf = "https://codeberg.org/";
                        "ssh://git@gitlab.com/".pushInsteadOf = "https://gitlab.com/";
                    };
                };
            };
            
            programs.ssh = {
                enable = true;
                enableDefaultConfig = false;
                settings = genAttrs [ "github.com" "gitlab.com" "codeberg.org" ] (_: {
                    IdentityFile = [ "${config.home.homeDirectory}/.ssh/id_${user.name}" ];
                    IdentitiesOnly = true;
                });
            };
            
            # For now also GitHub
            programs.gh.enable = true;
        };
    };
}