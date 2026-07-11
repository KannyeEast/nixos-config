{ ... }:
{
    flake.modules.homeManager.git = { host, ... }:
    let
        inherit (host) user;
    in
    {
        config = {
            home.file.".ssh/allowed_signers".text =
                "* ${builtins.readFile /home/${user.name}/.ssh/id_${user.name}.pub}";
        
            programs.git = {
                enable = true;
                userName = user.name;
                userEmail = user.email;
                
                settings = {
                    init.defaultBranch = "main";
                    commit.gpgsign = true;
                    core.editor = "$EDITOR";
                    gpg.format = "ssh";
                    gpg.ssh.allowedSignersFile = "/home/${user.name}/.ssh/allowed_signers";
                    user.signingKey = builtins.elemAt user.sshKeys 1;
                    url = {
                        "https://github.com/".insteadOf = "github:";
                        "https://gitlab.com/".insteadOf = "gitlab:";
                        "https://codeberg.org/".insteadOf = "codeberg:";
                    };
                };
            };
            
            # For now also GitHub
            programs.gh = {
                enable = true;
                gitCredentialHelper.enable = true;
            };
        };
    };
}