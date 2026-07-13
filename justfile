flake := env("NH_FLAKE", justfile_directory())
host := shell("hostname -s")

alias s := switch
alias b := boot
alias c := check
alias bump := update

# Overview
default:
    @just --list

todo:
    @echo TO-DOs in:
    @rg -g '!justfile' -C 5 TODO || echo "Everything's done!"

# ── system ───────────────────────────────────────────────────────────────────
# Rebuild and activate the configuration
[group("system")]
switch *ARGS: _stage
    nh os switch --ask {{flake}} -H {{host}} {{ARGS}}

# Build and activate on the next reboot
[group("system")]
boot *ARGS: _stage
    nh os boot --ask {{flake}} -H {{host}} {{ARGS}}

# Build without activating
[group("system")]
build *ARGS: _stage
    nh os build {{flake}} -H {{host}} {{ARGS}}

# Boot the config in a VM
[group("system")]
vm: _stage
    nixos-rebuild build-vm --flake {{flake}}#{{host}}
    ./result/bin/run-{{host}}-vm
    
# Roll back to the previous generation
[group("system")]
rollback:
    sudo nixos-rebuild switch --rollback

# List system generations
[group("system")]
generations:
    nixos-rebuild list-generations

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
    @echo "Checking secrets..."
    @fd -g 'secrets.yaml' hosts -x sh -c \
    'sops --decrypt "$1" > /dev/null \
    && echo "OK $1" \
    || echo "FAIL $1"' -- {}
    
# ── maintenance ──────────────────────────────────────────────────────────────
# Garbage-collect old generations
[group("maintenance")]
clean:
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

[group("git")]
stage:
    git add .
    
[group("git")]
commit MESSAGE: stage
    git commit -m "{{MESSAGE}}"
    
[group("git")]
push MESSAGE: (commit MESSAGE)
    git push
    
# ── private helpers ──────────────────────────────────────────────────────────
# Flakes ignore untracked files — make new files visible without committing them
[private]
_stage:
    @git -C {{flake}} add --intent-to-add .