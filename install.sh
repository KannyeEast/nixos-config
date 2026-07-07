#!/usr/bin/env bash
# Rough draft installer (fresh NixOS assumed).
# Detects hardware in the background, asks only for identity, then prints the
# host.json it WOULD write plus the pre/post command plan. Changes nothing.
#
# Env toggles:  ROLES=base,desktop   LOOKUP_HW=0 (skip nixos-hardware query)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── colors + feedback (self-contained; my header, + a yellow warn) ──
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; NC=$'\033[0m'
printHeader()  { printf '\n%s== %s ==%s\n' "$BOLD$GREEN" "$*" "$NC"; }
printSuccess() { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$*"; }
printWarn()    { printf '  %s!%s %s\n' "$YELLOW" "$NC" "$*"; }
printError()   { printf '  %s✗%s %s\n' "$RED" "$NC" "$*" >&2; }
printInfo()    { printf '  %sℹ%s %s\n' "$BLUE" "$NC" "$*"; }

have()  { command -v "$1" >/dev/null 2>&1; }
first() { for v in "$@"; do [ -n "$v" ] && { printf '%s' "$v"; return; }; done; }

# ── silent detection ────────────────────────────────────────────
detect() {
  SYSTEM="$(uname -m)-linux"
  FIRMWARE=$([ -d /sys/firmware/efi ] && echo uefi || echo bios)
  if have systemd-detect-virt; then VIRT=$(systemd-detect-virt 2>/dev/null || true); fi
  VIRT=${VIRT:-none}

  case "$(grep -m1 vendor_id /proc/cpuinfo 2>/dev/null)" in
    *GenuineIntel*) CPU=intel ;; *AuthenticAMD*) CPU=amd ;; *) CPU="" ;;
  esac

  # GPU: read PCI display devices straight from sysfs (no lspci needed)
  GPU=()
  local d
  for d in /sys/bus/pci/devices/*; do
    [ -e "$d/class" ] || continue
    case "$(cat "$d/class" 2>/dev/null)" in 0x03*) ;; *) continue ;; esac
    case "$(cat "$d/vendor" 2>/dev/null)" in
      0x10de) GPU+=(nvidia) ;; 0x1002) GPU+=(amd) ;; 0x8086) GPU+=(intel) ;;
    esac
  done
  if [ ${#GPU[@]} -eq 0 ] && have lspci; then
    local line
    while IFS= read -r line; do
      case "$line" in
        *NVIDIA*|*nVidia*) GPU+=(nvidia) ;;
        *"Advanced Micro Devices"*|*"AMD/ATI"*) GPU+=(amd) ;;
        *Intel*) GPU+=(intel) ;;
      esac
    done < <(lspci 2>/dev/null | grep -Ei 'vga|3d|display')
  fi
  GPU=($(printf '%s\n' "${GPU[@]:-}" | awk 'NF && !seen[$0]++'))

  if compgen -G '/sys/class/power_supply/BAT*' >/dev/null 2>&1; then PLATFORM=laptop
  else case "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" in
    8|9|10|11|14) PLATFORM=laptop ;; *) PLATFORM=desktop ;; esac
  fi

  VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null | tr -d '\n')
  PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null | tr -d '\n')
  BOARD=$(cat /sys/class/dmi/id/board_name 2>/dev/null | tr -d '\n')

  PRIMARY_DISK=$(lsblk -dpno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1; exit}')
  TIMEZONE=$(first "$(timedatectl show -p Timezone --value 2>/dev/null)" "$(cat /etc/timezone 2>/dev/null)" UTC)
  LOCALE=${LANG:-en_US.UTF-8}
  KEYMAP=$(localectl status 2>/dev/null | awk -F': ' '/Keymap/{print $2}')

  AGE_RECIPIENT=""
  if have ssh-to-age && [ -f /etc/ssh/ssh_host_ed25519_key.pub ]; then
    AGE_RECIPIENT=$(ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null)
  fi
}

# ── nixos-hardware match (best effort; board_name -> module attr) ─
detect_hw_model() {
  HW_MODEL=""; HW_MATCHES=""
  HW_TOKEN=$(printf '%s' "${BOARD:-}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
  { [ -z "$HW_TOKEN" ] || [ "${LOOKUP_HW:-1}" = 0 ] || ! have nix; } && return
  local json
  json=$(timeout 25 nix eval github:NixOS/nixos-hardware#nixosModules \
           --apply 'builtins.attrNames' --json \
           --extra-experimental-features 'nix-command flakes' 2>/dev/null) || return
  [ -n "$json" ] || return
  HW_MATCHES=$(printf '%s' "$json" | tr -d '[]"' | tr ',' '\n' | awk -v t="$HW_TOKEN" 'index($0,t)')
  [ "$(printf '%s' "$HW_MATCHES" | grep -c .)" = 1 ] && HW_MODEL="$HW_MATCHES"
}

# ── identity (the only interactive part) ────────────────────────
gather_identity() {
  local reply def_host def_user
  def_host=$(first "$(uname -n 2>/dev/null)" "$(hostname 2>/dev/null)" nixos)
  while :; do
    read -rp "  Hostname [$def_host]: " HOSTNAME_IN || true
    HOSTNAME_IN=${HOSTNAME_IN:-$def_host}
    [ "$HOSTNAME_IN" = default ] && { printError "'default' is reserved."; continue; }
    [[ "$HOSTNAME_IN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] && break
    printError "letters, numbers, hyphens only."
  done
  def_user=$(first "$(logname 2>/dev/null)" "${SUDO_USER:-}" "${USER:-}" user)
  read -rp "  Username [$def_user]: " reply || true
  USERNAME_IN=${reply:-$def_user}
  ROLES=${ROLES:-base,desktop}
}

# ── host.json preview (what the installer WOULD write) ──────────
build_host_json() {
  have jq || { printWarn "jq missing — showing partial preview"; \
    printf '{ "hostname": "%s", "system": "%s", "roles": "%s" }\n' "$HOSTNAME_IN" "$SYSTEM" "$ROLES"; return; }
  local gpu_json roles_json
  gpu_json=$(printf '%s\n' "${GPU[@]:-}" | jq -R . | jq -s 'map(select(length>0))')
  roles_json=$(printf '%s' "$ROLES" | jq -R 'split(",")')
  jq -n \
    --arg hostname "$HOSTNAME_IN" --arg system "$SYSTEM" --arg platform "$PLATFORM" \
    --arg firmware "$FIRMWARE" --arg virt "$VIRT" --arg cpu "$CPU" --arg user "$USERNAME_IN" \
    --arg disk "$PRIMARY_DISK" --arg tz "$TIMEZONE" --arg locale "$LOCALE" \
    --arg keymap "${KEYMAP:-us}" --arg vendor "$VENDOR" --arg product "$PRODUCT" \
    --arg hwmodel "$HW_MODEL" --arg age "$AGE_RECIPIENT" \
    --argjson gpu "$gpu_json" --argjson roles "$roles_json" '
    {
      hostname: $hostname, system: $system, platform: $platform,
      firmware: $firmware, virt: $virt,
      cpu: $cpu, gpu: $gpu,
      hardwareModel: (if $hwmodel == "" then null else $hwmodel end),
      detected: { vendor: $vendor, product: $product },
      roles: $roles, user: $user,
      locale: { timeZone: $tz, locale: $locale, keymap: $keymap },
      primaryDisk: $disk,
      secrets: { sopsFile: ("secrets/" + $hostname + ".yaml"),
                 hostAgeRecipient: (if $age == "" then null else $age end) }
    }'
}

# ── main ────────────────────────────────────────────────────────
clear 2>/dev/null || true
printHeader "NixOS installer — draft (detect + preview, no changes)"
grep -qi nixos /etc/os-release 2>/dev/null \
  && printSuccess "NixOS live environment" \
  || printWarn "Not NixOS — detection will be partial (fine for a dry run)."

printHeader "Detecting hardware"
detect
printSuccess "System:   $SYSTEM ($FIRMWARE, virt=$VIRT)"
[ -n "$CPU" ]           && printSuccess "CPU:      $CPU"            || printWarn "CPU:      not detected"
[ -n "${GPU[*]:-}" ]    && printSuccess "GPU:      ${GPU[*]}"       || printWarn "GPU:      none found (no PCI display device — normal under a VM/WSL)"
printSuccess "Platform: $PLATFORM"
[ -n "$BOARD$PRODUCT" ] && printSuccess "Board:    ${VENDOR:-?} ${PRODUCT:-} [${BOARD:-?}]" || printWarn "Board:    not detected"
[ -n "$PRIMARY_DISK" ]  && printSuccess "Disk:     $PRIMARY_DISK"   || printWarn "Disk:     not detected"
printSuccess "Locale:   $TIMEZONE / ${KEYMAP:-us} / $LOCALE"
[ -n "$AGE_RECIPIENT" ] && printSuccess "Age key:  $AGE_RECIPIENT"  || printWarn "Age key:  none yet (host ed25519 key / ssh-to-age missing)"

printHeader "Matching nixos-hardware"
detect_hw_model
if   [ -n "$HW_MODEL" ];   then printSuccess "hardwareModel = $HW_MODEL"
elif [ -n "$HW_MATCHES" ]; then printWarn "candidates for '$HW_TOKEN': $(printf '%s' "$HW_MATCHES" | tr '\n' ' ')— pick one by hand"
elif [ "${LOOKUP_HW:-1}" = 0 ]; then printInfo "lookup disabled (LOOKUP_HW=0); board token '$HW_TOKEN'"
elif have nix;             then printWarn "no match for board '$HW_TOKEN' — set hardwareModel by hand"
else printInfo "skipped (nix unavailable); board token '${HW_TOKEN:-?}'"
fi

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
