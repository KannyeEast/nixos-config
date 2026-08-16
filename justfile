flake := justfile_directory()
flakeRef := env("NH_FLAKE", "git+file://" + flake + "?submodules=1")

host := shell("hostname -s")

# List of forges: The first entry is treated as the primary/origin.
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

# Switch theme; Optionally also rebuild the system afterwards
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
# Stage changes to be committed
[group("git")]
stage:
  git -C {{flake}} add .

# Commit changes
[group("git")]
commit MESSAGE="": stage
  #!/usr/bin/env bash
  set -euo pipefail
  cd {{flake}}

  if git diff --cached --quiet; then
    echo "Nothing to commit."
    exit 0
  fi

  msg="{{MESSAGE}}"

  if [ -z "$msg" ]; then
    echo "Select commit type:"
    types=("feat" "fix" "docs" "refactor" "revert" "test" "chore" "skip")
    select type in "${types[@]}"; do
      case $type in
        skip) break ;;
        "") echo "Invalid selection"; exit 1 ;;
        *) 
          read -p "Enter scope (optional, e.g. modules): " scope
          read -p "Enter description: " desc
          if [ -n "$scope" ]; then
            msg="$type($scope): $desc"
          else
            msg="$type: $desc"
          fi
          break
          ;;
      esac
    done
  fi

  if [ -n "$msg" ]; then
    git commit -m "$msg"
  else
    echo "Commit aborted."
    exit 1
  fi

# Push changes to repo
[group("git")]
push MESSAGE="": (commit MESSAGE)
  git -C {{flake}} push

# Pull changes from the repo
[group("git")]
pull:
  git -C {{flake}} pull --rebase --autostash --recurse-submodules
  git -C {{flake}} submodule update --init --recursive

# Sync dev branch to main
[group("git")]
sync:
  #!/usr/bin/env bash
  set -euo pipefail
  cd {{flake}}

  git switch main 2>/dev/null || git switch -c main

  prev=$(git log -1 --format=%B --grep='^Sync from dev' \
      | sed -n 's/^Sync from dev (\([0-9a-f]\{7,40\}\))$/\1/p')

  # Wipe everything from the working tree
  git rm -rq --ignore-unmatch .

  # Opt-in: Only check out what belongs on main
  git checkout dev -- install.sh modules/ lib/ docs/ flake.nix README.md 2>/dev/null || true

  if [ -n "$prev" ] && git cat-file -e "$prev^{commit}" 2>/dev/null; then
    range="$prev..dev"
  else
    range="dev"
  fi
  body=$(git log --no-merges --reverse --format='- %s' "$range")

  if git diff --cached --quiet; then
    echo "Nothing to sync."
  else
    git commit -m "sync: ($(git rev-parse dev))" \
               -m "${body:-No individual commits.}"

    git push -u origin main --force
  fi

  git switch dev

# (Re)build remotes and push to every forge
[group("git")]
remotes:
  #!/usr/bin/env bash
  set -euo pipefail
  cd {{flake}}

  read -ra pairs <<< "{{forges}}"

  # Clean up all possible remotes from the list + origin + all
  for p in "${pairs[@]}"; do
    git remote remove "${p%%=*}" 2>/dev/null || true
  done
  for r in origin all; do
    git remote remove "$r" 2>/dev/null || true
  done

  # Add individual named remotes
  for p in "${pairs[@]}"; do
    git remote add "${p%%=*}" "${p#*=}"
  done

  # Set up origin to point to the first forge ([0])
  git remote add origin "${pairs[0]#*=}"

  # Clear any existing push URLs on origin just in case 'remotes' is run twice
  git remote set-url --delete --push origin '.*' 2>/dev/null || true

  # Add all forge URLs as push targets for origin (multiplexing)
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
  @git -C {{flake}} submodule update --init --recursive --remote
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
