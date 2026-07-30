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
            
            programs.delta.enable = true;
            programs.delta.enableGitIntegration = true;
            
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
                        # list commits in short form with branch/tag annotations
                        ls = "log --pretty=format:'%C(yellow)%h%Cred%d\\ %Creset%s%Cblue\\ [%cn]' --decorate";
                        # show changed files
                        ll = "log --pretty=format:'%C(yellow)%h%Cred%d\\ %Creset%s%Cblue\\ [%cn]' --decorate --numstat";
                        # list wihtout colors (unix piping)
                        lnc = "log --pretty=format:'%h\\ %s\\ [%cn]'";
                        # commits with dates
                        lds = "log --pretty=format:'%C(yellow)%h\\ %ad%Cred%d\\ %Creset%s%Cblue\\ [%cn]' --decorate --date=short";
                        # commits with relative dates
                        ld = "log --pretty=format:'%C(yellow)%h\\ %ad%Cred%d\\ %Creset%s%Cblue\\ [%cn]' --decorate --date=relative";
                        # git log
                        le = "log --oneline --decorate";
                        
                        # history of a file
                        filelog = "log -u";
                        fl = "log -u";
                        
                        # modified files in last commit
                        dl = "!git ll -1";
                        # diff of last commit
                        dlc = "diff --cached HEAD^";
                        
                        # find file
                        f = "!git ls-files | grep -i";
                        # find string
                        grep = "grep -Ii";
                        gr = "grep -Ii";
                        
                        # list aliases
                        la = "!git config -l | grep alias | cut -c 7-";
                        
                        # basic commands
                        cp = "cherry-pick";
                        st = "status -s";
                        cl = "clone";
                        ci = "commit";
                        co = "checkout";
                        br = "branch";
                        diff = "diff --word-diff";
                        dc = "diff --cached";
                        
                        # reset commands
                        r = "reset";
                        r1 = "reset HEAD^";
                        r2 = "reset HEAD^^";
                        rh = "reset --hard";
                        rh1 = "reset HEAD^ --hard";
                        rh2 = "reset HEAD^^ --hard";
                        
                        # stash commands
                        sl = "stash list";
                        sa = "stash apply";
                        ss = "stash save";
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
            
            programs.ssh.knownHosts = {
                "github.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
                "codeberg.org".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIVIC02vnjFyL+I4RHfvIGNtOgJMe769VTF1VR4EB3ZB";
                "gitlab.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf";
            };
        };
    };
}