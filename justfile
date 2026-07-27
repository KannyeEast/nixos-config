flake := env("NH_FLAKE", justfile_directory())
host := shell("hostname -s")

alias bump := update
alias deploy := switch
alias s := switch
alias b := boot
alias c := check
alias cs := check-secrets
alias es := edit-secrets

# Overview
[group("default")]
default:
    @just --list

# List ToDo's
[group("default")]
todo:
    @echo TO-DOs in:
    @rg -g '!justfile' -C 5 TODO || echo "Everything's done!"

# ── system ───────────────────────────────────────────────────────────────────
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

# ── flake ────────────────────────────────────────────────────────────────────
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

# ── secrets ────────────────────────────────────────────────────────────────────
# Verify all secrets can be decrypted with current keys
[group("secrets")]
check-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Checking secrets ..."
    for f in hosts/*/secrets.json; do
        [ -e "$f" ] || continue
        if sops --decrypt "$f" > /dev/null 2>&1;
        then echo "OK $f";
        else echo "FAIL $f";
    fi
    done

# Edit this host's secrets
[group("secrets")]
edit-secrets:
    @sops --decrypt hosts/{{host}}/secrets.json > /dev/null
    sops hosts/{{host}}/secrets.json

# Re-encrypt secrets to the recipients currently in .sops.yaml. Make sure you run this before removing the old key
# @TODO: Widen the glob once secrets/shared.json exists (currently hosts/* only)
# @TODO: 'adopt HOST' recipe - reinstall an existing host: extract hostPrivateKey
# with the admin key, place at /etc/ssh, rebuild (needs hostPrivateKey in secrets)
[group("secrets")]
rekey: && check-secrets
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Rotating secrets..."
    for f in hosts/*/secrets.json; do
        [ -e "$f" ] || continue
        echo "Rekeying $f"
        sops updatekeys -y "$f"
    done

# ── maintenance ──────────────────────────────────────────────────────────────
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

# ── git ──────────────────────────────────────────────────────────────────────
# Add changes to be committed
[group("git")]
stage:
    git add .

# Commit changes
[group("git")]
commit MESSAGE: stage
    git commit -m "{{MESSAGE}}"

# Push changes to repo
[group("git")]
push MESSAGE: (commit MESSAGE)
    git push

# Pull changes from the repo
[group("git")]
pull:
    git pull --rebase --autostash

# @TODO: Exclude .sops.yaml from this
# Sync dev branch to main
[group("git")]
sync:
    #!/usr/bin/env bash
    set -euo pipefail
    git switch main
    git rm -rq --ignore-unmatch .
    git checkout dev -- . ":(exclude)hosts"
    git checkout dev -- hosts/default
    git commit -m "Sync from dev" || echo "Nothing to sync."
    git push origin main
    git switch -

# ── private helpers ──────────────────────────────────────────────────────────
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