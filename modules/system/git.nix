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
            # Verifies our own signatures locally; the forges keep their own copy
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

                    # Show both sides plus the common ancestor in conflicts
                    merge.conflictStyle = "zdiff3";
                    # Remember conflict resolutions and replay them
                    rerere.enabled = true;
                    push.autoSetupRemote = true;
                    pull.rebase = true;
                    fetch.prune = true;
                    diff.algorithm = "histogram";

                    alias = {
                        # ── log ────────
                        l = "log --oneline --decorate";
                        lg = "log --oneline --decorate --graph --all";
                        ld = "log --pretty=format:'%C(yellow)%h %ad%Cred%d %Creset%s%Cblue [%cn]' --decorate --date=relative";
                        lds = "log --pretty=format:'%C(yellow)%h %ad%Cred%d %Creset%s%Cblue [%cn]' --decorate --date=short";
                        lnc = "log --pretty=format:'%h %s [%cn]'";
                        last = "log -1 HEAD --stat";
                        # history of one file, with patches
                        fl = "log -u";

                        # ── inspect ────────
                        st = "status -s";
                        dc = "diff --cached";
                        dw = "diff --word-diff";
                        # files changed in the last commit
                        dl = "show --stat --oneline HEAD";
                        # find a tracked file by name
                        f = "!git ls-files | grep -i";
                        # find a string in tracked files
                        gr = "grep -Ii";
                        # list these aliases
                        la = "!git config -l | grep alias | cut -c 7-";

                        # ── work ────────
                        a = "add";
                        aa = "add --all";
                        ci = "commit";
                        cm = "commit -m";
                        amend = "commit --amend --no-edit";
                        co = "checkout";
                        sw = "switch";
                        br = "branch";
                        cl = "clone";
                        cp = "cherry-pick";
                        rb = "rebase";
                        rbi = "rebase -i";
                        wt = "worktree";

                        # ── undo ────────
                        # keep the changes, drop the commit
                        uncommit = "reset --soft HEAD^";
                        unstage = "restore --staged";
                        r = "reset";
                        rh = "reset --hard";
                        rh1 = "reset HEAD^ --hard";

                        # ── stash ────────
                        sl = "stash list";
                        sa = "stash apply";
                        ss = "stash push";
                    };

                    url = {
                        "ssh://git@github.com/".pushInsteadOf = "https://github.com/";
                        "ssh://git@codeberg.org/".pushInsteadOf = "https://codeberg.org/";
                        "ssh://git@gitlab.com/".pushInsteadOf = "https://gitlab.com/";
                    };
                };
            };
        };
    };
}
