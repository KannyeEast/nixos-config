#!/usr/bin/env bash
# Rough draft installer (fresh NixOS assumed).
# Detects hardware in the background, asks only for identity, then prints the
# host.json it WOULD write plus the pre/post command plan. Changes nothing.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── print helpers (reuse repo's, fall back if run standalone) ────
if [ -f "$REPO_DIR/scripts/variables.sh" ]; then
  # strip a possible UTF-8 BOM before sourcing (variables.sh currently has one)
  # shellcheck disable=SC1090
  source <(sed '1s/^\xEF\xBB\xBF//' "$REPO_DIR/scripts/variables.sh")
fi
type printHeader  >/dev/null 2>&1 || printHeader()  { printf '\n\033[1;32m== %s ==\033[0m\n' "$*"; }
type printInfo    >/dev/null 2>&1 || printInfo()    { printf '  %s\n' "$*"; }
type printSuccess >/dev/null 2>&1 || printSuccess() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
type printError   >/dev/null 2>&1 || printError()   { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }
first() { for v in "$@"; do [ -n "$v" ] && { printf '%s' "$v"; return; }; done; }

# ── silent detection (no prompts, best effort) ──────────────────
detect() {
  SYSTEM="$(uname -m)-linux"
  FIRMWARE=$([ -d /sys/firmware/efi ] && echo uefi || echo bios)
  VIRT=$(have systemd-detect-virt && systemd-detect-virt 2>/dev/null || echo none)

  case "$(grep -m1 vendor_id /proc/cpuinfo 2>/dev/null)" in
    *GenuineIntel*) CPU=intel ;; *AuthenticAMD*) CPU=amd ;; *) CPU="" ;;
  esac

  GPU=()
  if have lspci; then
    local line
    while IFS= read -r line; do
      case "$line" in
        *NVIDIA*|*nVidia*) GPU+=(nvidia) ;;
        *"Advanced Micro Devices"*|*"AMD/ATI"*) GPU+=(amd) ;;
        *Intel*) GPU+=(intel) ;;
      esac
    done < <(lspci 2>/dev/null | grep -Ei 'vga|3d|display')
  fi
  # de-dupe
  GPU=($(printf '%s\n' "${GPU[@]:-}" | awk 'NF && !seen[$0]++'))

  if compgen -G '/sys/class/power_supply/BAT*' >/dev/null 2>&1; then
    PLATFORM=laptop
  else
    case "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" in
      8|9|10|11|14) PLATFORM=laptop ;; *) PLATFORM=desktop ;;
    esac
  fi

  VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null | tr -d '\n')
  PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null | tr -d '\n')
  BOARD=$(cat /sys/class/dmi/id/board_name 2>/dev/null | tr -d '\n')

  PRIMARY_DISK=$(lsblk -dpno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1; exit}')

  TIMEZONE=$(first \
    "$(timedatectl show -p Timezone --value 2>/dev/null)" \
    "$(cat /etc/timezone 2>/dev/null)" UTC)
  LOCALE=${LANG:-en_US.UTF-8}
  KEYMAP=$(first "$(localectl status 2>/dev/null | awk -F': ' '/Keymap/{print $2}')" us)

  # host key -> age recipient (sops/agenix). Empty if not generated/available yet.
  AGE_RECIPIENT=""
  if have ssh-to-age && [ -f /etc/ssh/ssh_host_ed25519_key.pub ]; then
    AGE_RECIPIENT=$(ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null)
  fi
}

# ── identity (the only interactive part) ────────────────────────
gather_identity() {
  local reply
  while :; do
    read -rp "  Hostname: " HOSTNAME_IN || true
    HOSTNAME_IN=${HOSTNAME_IN:-${HOST:-}}
    [ "$HOSTNAME_IN" = default ] && { printError "'default' is reserved."; continue; }
    [[ "$HOSTNAME_IN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] && break
    printError "letters, numbers, hyphens only."
  done
  local du; du=$(first "$(logname 2>/dev/null)" "${SUDO_USER:-}" "${USER:-}" user)
  read -rp "  Username [$du]: " reply || true
  USERNAME_IN=${reply:-$du}
  ROLES=${ROLES:-base,desktop}          # override via env; no prompt
}

# ── host.json preview (what the installer WOULD write) ──────────
build_host_json() {
  local gpu_json roles_json
  if have jq; then
    gpu_json=$(printf '%s\n' "${GPU[@]:-}" | jq -R . | jq -s 'map(select(length>0))')
    roles_json=$(printf '%s' "$ROLES" | jq -R 'split(",")')
    jq -n \
      --arg hostname "$HOSTNAME_IN" --arg system "$SYSTEM" \
      --arg platform "$PLATFORM"   --arg firmware "$FIRMWARE" \
      --arg virt "$VIRT"           --arg cpu "$CPU" \
      --arg user "$USERNAME_IN"    --arg disk "$PRIMARY_DISK" \
      --arg tz "$TIMEZONE"         --arg locale "$LOCALE" --arg keymap "$KEYMAP" \
      --arg vendor "$VENDOR"       --arg product "$PRODUCT" \
      --arg age "$AGE_RECIPIENT"   --argjson gpu "$gpu_json" --argjson roles "$roles_json" '
      {
        hostname: $hostname, system: $system, platform: $platform,
        firmware: $firmware, virt: $virt,
        cpu: $cpu, gpu: $gpu,
        hardwareModel: null,                # nixos-hardware attr — set by hand
        detected: { vendor: $vendor, product: $product },
        roles: $roles, user: $user,
        locale: { timeZone: $tz, locale: $locale, keymap: $keymap },
        primaryDisk: $disk,
        secrets: { sopsFile: ("secrets/" + $hostname + ".yaml"),
                   hostAgeRecipient: (if $age == "" then null else $age end) }
      }'
  else
    printf '{ "hostname": "%s", "system": "%s", "roles": "%s", "user": "%s",\n' \
      "$HOSTNAME_IN" "$SYSTEM" "$ROLES" "$USERNAME_IN"
    printf '  "cpu": "%s", "gpu": "%s", "primaryDisk": "%s", "age": "%s" }\n' \
      "$CPU" "${GPU[*]:-}" "$PRIMARY_DISK" "${AGE_RECIPIENT:-null}"
  fi
}

# ── main ────────────────────────────────────────────────────────
clear 2>/dev/null || true
printHeader "NixOS installer — draft (detect + preview, no changes)"

grep -qi nixos /etc/os-release 2>/dev/null \
  && printSuccess "NixOS live environment" \
  || printError "Not NixOS — detection will be partial (fine for a dry run)."

printHeader "Detecting hardware"
detect
printSuccess "system=$SYSTEM firmware=$FIRMWARE virt=$VIRT"
printSuccess "cpu=${CPU:-?} gpu=${GPU[*]:-?} platform=$PLATFORM"
printSuccess "board=${VENDOR:-?} ${PRODUCT:-?}"
printSuccess "disk=${PRIMARY_DISK:-?}  tz=$TIMEZONE  keymap=$KEYMAP"
[ -n "$AGE_RECIPIENT" ] && printSuccess "age=$AGE_RECIPIENT" \
                        || printInfo "age recipient: none yet (host key not generated / ssh-to-age missing)"

printHeader "Identity"
gather_identity

printHeader "hosts/$HOSTNAME_IN/host.json (preview — not written)"
build_host_json

printHeader "Planned steps (not executed)"
cat <<PLAN
  pre:
    [ ] nix-shell -p git jq ssh-to-age nixos-install-tools   # if missing
    [ ] nixos-generate-config --show-hardware-config > hosts/$HOSTNAME_IN/hardware.nix
    [ ] template hosts/$HOSTNAME_IN/disko.nix from ${PRIMARY_DISK:-<disk>}
    [ ] ensure /etc/ssh/ssh_host_ed25519_key, then ssh-to-age -> host.json.secrets + .sops.yaml
    [ ] re-encrypt sops secrets for the new host recipient
  install:
    [ ] disko  (only if wiping ${PRIMARY_DISK:-<disk>})
    [ ] nixos-install --flake "$REPO_DIR#$HOSTNAME_IN"     # or: nixos-anywhere --flake .#$HOSTNAME_IN <target>
  post:
    [ ] passwd for $USERNAME_IN  (until sops hashedPasswordFile is wired)
    [ ] git add hosts/$HOSTNAME_IN/host.json && commit
    [ ] reboot; first boot: just switch
PLAN

printHeader "Done"
printInfo "Draft only — nothing was written or installed."
