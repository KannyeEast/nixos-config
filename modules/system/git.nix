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
                        "ssh://git@github.com/".insteadOf = "https://github.com/";
                        "https://gitlab.com/".insteadOf = "gitlab:";
                        "https://codeberg.org/".insteadOf = "codeberg:";
                    };
                };
            };
            
            programs.ssh = {
                enable = true;
                enableDefaultConfig = false;
                settings."github.com" = {
                    # @TODO: Dedicated forge key (id_git) shared across hosts via a
                    # shared sops file (secrets/shared.json) instead of registering
                    # every per-host key on GitHub. Auth only - signing stays on the
                    # per-host user key
                    IdentityFile = [
                        "${config.home.homeDirectory}/.ssh/id_${user.name}"
                        "${config.home.homeDirectory}/.config/sops/age/id_admin" # @TODO@TEMP: Temporary admin key for ssh auth >> Remove when system stable
                    ];
                    IdentitiesOnly = true;
                };
            };
            
            # For now also GitHub
            programs.gh.enable = true;
        };
    };
}