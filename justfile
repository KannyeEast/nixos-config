flake := env("NH_FLAKE", justfile_directory())
host := shell("hostname -s")

# ── aliases ────────
alias bump := update
alias deploy := switch
alias s := switch
alias b := boot
alias c := check
alias es := edit-secrets
alias sop := edit-secrets

# ── overview ────────
# This list
[group("default")]
default:
    @just --list

# List ToDo's
[group("default")]
todo:
    @echo TO-DOs in:
    @rg -g '!justfile' -C 5 TODO || echo "Everything's done!"

# ── system ────────
# Rebuild and activate the configuration
[group("system")]
switch *ARGS: pull _stage (_closed "zen-beta" "Zen")
    nh os switch --ask {{flake}} -H {{host}} {{ARGS}}

# Build and activate on the next reboot
[group("system")]
boot *ARGS: pull _stage
    nh os boot --ask {{flake}} -H {{host}} {{ARGS}}

# Build without activating
[group("system")]
build *ARGS: pull _stage && diff
    nh os build {{flake}} -H {{host}} {{ARGS}}

# Show what switching would change
[group("system")]
diff:
    nix store diff-closures /run/current-system {{flake}}/result

# Boot the config in a VM
[group("system")]
vm: pull _stage
    nixos-rebuild build-vm --flake {{flake}}#{{host}}
    ./result/bin/run-{{host}}-vm

# ── flake ────────
# Evaluate every output
[group("flake")]
check *ARGS: _stage
    nix flake check {{flake}} {{ARGS}}
    
# Update a single or all inputs
[group("flake")]
update *INPUTS: _stage
    nix flake update {{INPUTS}} --flake {{flake}} --refresh
    
# Show the input tree
[group("flake")]
inputs:
    nix flake metadata {{flake}}

# ── secrets ────────
# Edit this host's secrets
[group("secrets")]
edit-secrets:
    @sops --decrypt hosts/{{host}}/secrets.json > /dev/null
    sops hosts/{{host}}/secrets.json

# ── maintenance ────────
# Garbage-collect old generations
[group("maintenance")]
clean:
    rm -f {{flake}}/result {{flake}}/result-*
    nh clean all --ask --keep-since 4d --keep 5
    
# Format and prune dead code
[group("maintenance")]
fmt:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{flake}}
    find . -name '*.nix' -exec nixfmt {} +
    if deadnix --fail .; then
        echo "No dead code."
    else
        read -rp "Remove the above? [y/N] " reply
        [[ "$reply" =~ ^[Yy]$ ]] && deadnix --edit .
    fi

# ── git ────────
# Add changes to be committed
[group("git")]
stage:
    git -C {{flake}} add .

# Commit changes
[group("git")]
commit MESSAGE: stage
    #!/usr/bin/env bash
    set -euo pipefail
    if git diff --cached --quiet; then
        echo "Nothing to commit."
    else
        git commit -m "{{MESSAGE}}"
    fi

# Push changes to repo
[group("git")]
push MESSAGE: (commit MESSAGE)
    git -C {{flake}} push

# Pull changes from the repo
[group("git")]
pull:
    git -C {{flake}} pull --rebase --autostash

# Sync dev branch to main
[group("git")]
sync:
    #!/usr/bin/env bash
    set -euo pipefail

    git switch main 2>/dev/null || git switch -c main
    git rm -rq --ignore-unmatch .
    git checkout dev -- . ":(exclude)hosts" ":(exclude).sops.yaml"
    git checkout dev -- hosts/default
    git commit -m "Sync from dev ($(git rev-parse dev))" || echo "Nothing to sync."
    git push
    git switch dev

# (Re)build the 'all' remote and pushes to every forge
[group("git")]
remotes:
    #!/usr/bin/env bash
    set -euo pipefail
    
    codeberg="git@codeberg.org:KanyeSouth/nixos-config.git"
    github="git@github.com:KannyeEast/nixos-config.git"
    gitlab="git@gitlab.com:KanyeNorth/nixos-config.git"
    
    for r in origin all codeberg github gitlab; do
        git remote remove "$r" 2>/dev/null || true
    done
    
    git remote add codeberg "$codeberg"
    git remote add github "$github"
    git remote add gitlab "$gitlab"
    
    git remote add origin "$codeberg"
    
    git remote set-url --add --push origin "$codeberg"
    git remote set-url --add --push origin "$github"
    git remote set-url --add --push origin "$gitlab"
    
    git fetch --all --prune
    git branch --set-upstream-to="origin/$(git branch --show-current)" 2>/dev/null || true

    git remote -v

# ── private helpers ────────
# Make new files visible without committing them
[private]
_stage:
    @git -C {{flake}} add --intent-to-add .
    
# Check if PROGRAM is currently running
[private]
_closed PATTERN NAME=PATTERN:
    #!/usr/bin/env bash
    set -euo pipefail
    if pgrep "{{PATTERN}}" >/dev/null; then
        echo "Error: {{NAME}} is running. Close it first." >&2
        exit 1
    fi