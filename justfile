flake := justfile_directory()
flakeRef := env("NH_FLAKE", "git+file://" + flake + "?submodules=1")

host := shell("hostname -s")

# List of all forges we push/pull from
# The first entry is treated as the origin
# Any changes to this must be followed by a `just remotes`
forges := "codeberg=git@codeberg.org:KanyeSouth/nixos-config.git " + \
          "github=git@github.com:KannyeEast/nixos-config.git " + \
          "gitlab=git@gitlab.com:KanyeNorth/nixos-config.git"

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
    @rg -g '!justfile' -g '!*.md' -g '!*.txt' -C 5 TODO || echo "Everything's done!"

# ── system ────────
# Rebuild and activate the configuration
[group("system")]
switch *ARGS: pull _stage (_closed "zen-beta" "Zen")
    nh os switch --ask "{{flakeRef}}" -H {{host}} {{ARGS}}

# Build and activate on the next reboot
[group("system")]
boot *ARGS: pull _stage
    nh os boot --ask "{{flakeRef}}" -H {{host}} {{ARGS}}

# Build without activating
[group("system")]
build *ARGS: pull _stage && diff
    nh os build "{{flakeRef}}" -H {{host}} {{ARGS}}

# Show what switching would change
[group("system")]
diff:
    nix store diff-closures /run/current-system {{flake}}/result

# Boot the config in a VM
[group("system")]
vm: pull _stage
    nixos-rebuild build-vm --flake "{{flakeRef}}#{{host}}"
    ./result/bin/run-{{host}}-vm

# ── flake ────────
# Evaluate every output
[group("flake")]
check *ARGS: _stage
    nix flake check "{{flakeRef}}" {{ARGS}}
    
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
    nh clean all --ask --keep-since 4d --keep 5
    rm -f {{flake}}/result {{flake}}/result-*
    nix store optimise
    
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

# Render the colour scheme into every file listed in flavours/config.toml.
# Second argument rebuilds afterwards: `just theme litmus switch` or `... boot`.
[group("maintenance")]
theme scheme="dendrite" rebuild="":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p ~/.local/share/flavours
    flavours apply {{scheme}}
    flavours current
    case "{{rebuild}}" in
        switch) just switch ;;
        boot) just boot ;;
        *) echo "Unknown rebuild mode '{{rebuild}}' (use 'switch' or 'boot')." >&2; exit 1 ;;
    esac

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

# Pull changes from every forge
[group("git")]
pull:
    #!/usr/bin/env bash
    set -euo pipefail

    branch=$(git branch --show-current)
    originUrl=$(git remote get-url origin 2>/dev/null || true)

    declare -A state
    primary=""
    rest=()
    width=0

    # Pass 1 - discover, order, fetch. Order decides tie-breaks
    for r in $(git remote); do
        if [[ $r == origin ]]; then
            continue
        fi

        if [[ ${#r} -gt $width ]]; then
            width=${#r}
        fi

        if [[ -n $originUrl && $(git remote get-url "$r") == "$originUrl" ]]; then
            primary="$r"
        else
            rest+=("$r")
        fi

        if git fetch --prune --quiet "$r" 2>/dev/null; then
            state[$r]="ok"
        else
            state[$r]="unreachable"
        fi
    done

    forges=()
    if [[ -n $primary ]]; then
        forges+=("$primary")
    fi
    forges+=("${rest[@]}")

    if [[ ${#forges[@]} -eq 0 ]]; then
        echo "No forges configured. Run 'just remotes'." >&2
        exit 1
    fi

    # Pass 2 - pick the tip containing all others
    best=""
    winner=""
    for r in "${forges[@]}"; do
        ref="refs/remotes/$r/$branch"
        if [[ ${state[$r]} != ok ]] || ! git show-ref -q --verify "$ref"; then
            continue
        fi

        if [[ -z $best ]]; then
            best="$ref"
            winner="$r"
        elif git merge-base --is-ancestor "$best" "$ref"; then
            if [[ $(git rev-parse "$best") != $(git rev-parse "$ref") ]]; then
                best="$ref"
                winner="$r"
            fi
        elif ! git merge-base --is-ancestor "$ref" "$best"; then
            echo "Forges have diverged: $r/$branch and $winner/$branch share no descendant." >&2
            echo "Resolve by hand before pulling." >&2
            exit 1
        fi
    done

    if [[ -z $best ]]; then
        echo "No forge has '$branch'." >&2
        exit 1
    fi

    # Pass 3 - report
    for r in "${forges[@]}"; do
        ref="refs/remotes/$r/$branch"
        if [[ ${state[$r]} != ok ]]; then
            printf "  %-${width}s  %s\n" "$r" "${state[$r]}"
        elif ! git show-ref -q --verify "$ref"; then
            printf "  %-${width}s  no %s\n" "$r" "$branch"
        elif [[ $(git rev-parse "$ref") == $(git rev-parse "$best") ]]; then
            if [[ $r == "$winner" ]]; then
                printf "  %-${width}s  up to date  <- source\n" "$r"
            else
                printf "  %-${width}s  up to date\n" "$r"
            fi
        else
            printf "  %-${width}s  behind by %s\n" "$r" "$(git rev-list --count "$ref..$best")"
        fi
    done
    echo

    old=$(git rev-parse HEAD)
    if [[ $(git rev-list --count "$old..$best") -eq 0 ]]; then
        echo "Nothing to pull."
        exit 0
    fi

    git log --oneline --no-decorate --reverse "$old..$best" | sed 's/^/  /'
    echo

    git rebase --autostash --quiet "$best"
    git --no-pager diff --stat "$old" HEAD

# Sync dev branch to main
[group("git")]
sync:
    #!/usr/bin/env bash
    set -euo pipefail

    git switch main 2>/dev/null || git switch -c main

    prev=$(git log -1 --format=%B --grep='^Sync from dev' \
        | sed -n 's/^Sync from dev (\([0-9a-f]\{7,40\}\))$/\1/p')

    git rm -rq --ignore-unmatch .
    git checkout dev -- . ":(exclude)hosts" ":(exclude).sops.yaml" ":(exclude)flake.lock" ":(exclude).gitmodules"

    if [ -n "$prev" ] && git cat-file -e "$prev^{commit}" 2>/dev/null; then
        range="$prev..dev"
    else
        range="dev"
    fi
    body=$(git log --no-merges --reverse --format='- %s' "$range")

    if git diff --cached --quiet; then
        echo "Nothing to sync."
    else
        git commit -m "Sync from dev ($(git rev-parse dev))" \
                   -m "${body:-No individual commits.}"

        git push -u origin main --force
    fi

    git switch dev

# (Re)build every forge remote from the `forges` variable
[group("git")]
remotes:
    #!/usr/bin/env bash
    set -euo pipefail

    read -ra pairs <<< "{{forges}}"

    for p in "${pairs[@]}"; do
        git remote remove "${p%%=*}" 2>/dev/null || true
    done
    for r in origin all; do
        git remote remove "$r" 2>/dev/null || true
    done

    for p in "${pairs[@]}"; do
        git remote add "${p%%=*}" "${p#*=}"
    done

    git remote add origin "${pairs[0]#*=}"
    for p in "${pairs[@]}"; do
        git remote set-url --add --push origin "${p#*=}"
    done

    git fetch --all --prune

    for b in main dev; do
        if git show-ref --verify -q "refs/heads/$b"; then
            git branch --set-upstream-to="origin/$b" "$b" 2>/dev/null || true
        fi
    done

    git remote -v

# ── private helpers ────────
# Make files visible to evaluation without committing them
[private]
_stage:
    @git -C {{flake}} submodule update --init --recursive
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