#!/usr/bin/env nix-shell
#!nix-shell -i bash -p age bash git jq mkpasswd nixos-install-tools openssh sops ssh-to-age
#
# install.sh - bootstrap a new host for this flake.
#
set -Eeu -o pipefail

# ── init ──────────────────────────────────────────────────────────────
DRY_RUN=false
VERBOSE=false
ADMIN_KEY=""
PASSWORD_FILE=""
REPO_ROOT=""

# ── logging ──────────────────────────────────────────────────────────────
RED=$'\033[0;31m';
GREEN=$'\033[0;32m';
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m';
BOLD=$'\033[1m';
NC=$'\033[0m'

printHeader() { printf '\n%s== %s ==%s\n' "$BOLD$GREEN" "$*" "$NC"; }
printSuccess() { printf '%s✓%s %s\n' "$GREEN" "$NC" "$*"; }
printError() { printf '%s✗%s %s\n' "$RED" "$NC" "$*" >&2; }
printWarn() { printf '%s!%s %s\n' "$YELLOW" "$NC" "$*"; }
printInfo() { printf '%sℹ%s %s\n' "$BLUE" "$NC" "$*"; }

trapError() {
    local code=$? cmd=$BASH_COMMAND line=${BASH_LINENO[0]} fn=${FUNCNAME[1]:-main}
    printError "'$cmd' failed (exit $code) at $fn():$line"
    exit "$code"
}
trap trapError ERR

# ── helpers ──────────────────────────────────────────────────────────────
gitRepo() { git -c safe.directory='*' "$@"; }

# ── flags ──────────────────────────────────────────────────────────────
showFlags() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS]
 
Bootstrap a (new) host for this flake. Creates or modifies:
  - host.json
  - host/user SSH Keys
  - secrets.yaml with userPassword and privateKey
  - hardware.nix
 
Options:
      --admin-key      PATH  Public half of the admin key (extra sops recipient)
      --password-file  PATH  Read the hashed password from a file instead of prompting
  -n, --dry-run              Print what would happen. Writes nothing
  -v, --verbose              Trace execution
  -h, --help                 This message
 
Examples:
  sudo ./install.sh --verbose --dry-run
EOF
}

needsArg() { [[ -n ${2:-} ]] || { printError "Error: $1 requires an argument"; exit 1; }; }

parseArgs() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --admin-key)     needsArg "$1" "${2:-}"; ADMIN_KEY="$2";     shift 2 ;;
            --password-file) needsArg "$1" "${2:-}"; PASSWORD_FILE="$2"; shift 2 ;;
            -n|--dry-run)    DRY_RUN=true;  shift ;;
            -v|--verbose)    VERBOSE=true;  shift ;;
            -h|--help)       showFlags; exit 0 ;;
            *)               printError "Error: Unknown option: $1"; showFlags; exit 1 ;;
        esac
    done

    if [[ $VERBOSE == true ]];
    then set -x;
    fi
}

# ── validate ──────────────────────────────────────────────────────────────
# Validate if all prerequisites are present for the install process 
validate() {
    printHeader "Validating environment"
    local fail=0

    # The nix-shell shebang only fires when executed directly.
    if [[ -n ${IN_NIX_SHELL:-} ]];
    then
        printSuccess "Verified nix-shell environment"
    else
        printError "Failed to install nix-shell packages"
        fail=1
    fi

    if grep -qi nixos /etc/os-release 2>/dev/null;
    then
        printSuccess "Verified NixOS"
    else
        printError "Not NixOS"
        fail=1
    fi

    # Writes /etc/ssh and chowns the user's home.
    if [[ $DRY_RUN == true || $EUID -eq 0 ]];
    then
        printSuccess "Verified privileges"
    else
        printError "Failed to access /etc/. Script must be run as root"
        fail=1
    fi

    # Prompts for hostname, username, password.
    if [[ -t 0 && -t 1 ]];
    then
        printSuccess "Verified terminal"
    else
        printError "No TTY"
        fail=1
    fi

    if REPO_ROOT="$(gitRepo rev-parse --show-toplevel 2>/dev/null)";
    then
        printSuccess "Verified config location: $REPO_ROOT"
    else
        printError "Failed to locate config. Not inside git worktree"
        fail=1
    fi

    if [[ -n ${REPO_ROOT:-} && -f $REPO_ROOT/flake.nix ]];
    then
        printSuccess "Verified flake.nix"
    else
        printError "Failed to locate flake.nix"
        fail=1
    fi

    if [[ -n $PASSWORD_FILE ]];
    then
        [[ -r $PASSWORD_FILE ]] \
        && printSuccess "Verified password file" \
        || { printError "Failed to read: $PASSWORD_FILE"; fail=1; }
    fi

    if [[ -n $ADMIN_KEY ]];
    then
        if [[ -r $ADMIN_KEY ]] && grep -qE '^(ssh-ed25519|ssh-rsa) ' "$ADMIN_KEY";
        then
            printSuccess "Verified admin key"
        else
            printError "Failed to locate admin key. $ADMIN_KEY is not a readable SSH key"
            fail=1
        fi
    fi

    [[ $fail -eq 0 ]] || return 1
    printSuccess "Validatied environment. All checks have passed"
}

# ── main ──────────────────────────────────────────────────────────────
main() {
    parseArgs "$@"
    validate || exit 1
}

main "$@"