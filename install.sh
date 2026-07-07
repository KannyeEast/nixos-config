#!/usr/bin/env bash
# Rough draft installer (fresh NixOS assumed).
# Preflight -> detect hardware -> ask identity -> print the host.json it WOULD
# write + the pre/post plan. Changes nothing. No jq dependency.
#
# Env toggles:  ROLES=base,desktop   LOOKUP_HW=0 (skip nixos-hardware model query)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── colors + feedback ───────────────────────────────────────────
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; NC=$'\033[0m'
printHeader()  { printf '\n%s== %s ==%s\n' "$BOLD$GREEN" "$*" "$NC"; }
printSuccess() { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$*"; }
printWarn()    { printf '  %s!%s %s\n' "$YELLOW" "$NC" "$*"; }
printError()   { printf '  %s✗%s %s\n' "$RED" "$NC" "$*" >&2; }
printInfo()    { printf '  %sℹ%s %s\n' "$BLUE" "$NC" "$*"; }

have()  { command -v "$1" >/dev/null 2>&1; }
first() { for v in "$@"; do [ -n "$v" ] && { printf '%s' "$v"; return; }; done; }

# ── minimal JSON emitters (no jq) ───────────────────────────────
jstr() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"; }
jarr() { local out="" a; for a in "$@"; do [ -n "$a" ] || continue; out+="${out:+, }$(jstr "$a")"; done; printf '[%s]' "$out"; }

# ── preflight ───────────────────────────────────────────────────
verify() {
  local fail=0
  grep -qi nixos /etc/os-release 2>/dev/null \
    && printSuccess "NixOS live environment" \
    || { printError "not NixOS (required for a real install)"; fail=1; }
  have nix && printSuccess "nix available" || { printError "nix missing"; fail=1; }
  have git && printSuccess "git available" || printWarn "git missing  (nix-shell -p git)"
  [ -r /sys/bus/pci/devices ] && printSuccess "PCI sysfs readable" \
    || printWarn "no PCI sysfs — GPU detection will be limited"
  have ssh-to-age && printSuccess "ssh-to-age available" \
    || printInfo "ssh-to-age absent — age recipient step will be a TODO"
  return $fail
}

# ── hardware detection ──────────────────────────────────────────
detect() {
  SYSTEM="$(uname -m)-linux"
  FIRMWARE=$([ -d /sys/firmware/efi ] && echo uefi || echo bios)
  if have systemd-detect-virt; then VIRT=$(systemd-detect-virt 2>/dev/null || true); fi
  VIRT=${VIRT:-none}

  case "$(grep -m1 vendor_id /proc/cpuinfo 2>/dev/null)" in
    *GenuineIntel*) CPU=intel ;; *AuthenticAMD*) CPU=amd ;; *) CPU="" ;;
  esac

  # GPU vendors from sysfs PCI display devices (class 0x03xxxx)
  local d has_nvidia=0 has_amd=0 has_intel=0
  for d in /sys/bus/pci/devices/*; do
    [ -e "$d/class" ] || continue
    case "$(cat "$d/class" 2>/dev/null)" in 0x03*) ;; *) continue ;; esac
    case "$(cat "$d/vendor" 2>/dev/null)" in
      0x10de) has_nvidia=1 ;; 0x1002) has_amd=1 ;; 0x8086) has_intel=1 ;;
    esac
  done
  if [ $((has_nvidia + has_amd + has_intel)) -eq 0 ] && have lspci; then
    local g; g=$(lspci 2>/dev/null | grep -Ei 'vga|3d|display')
    printf '%s' "$g" | grep -qi nvidia       && has_nvidia=1
    printf '%s' "$g" | grep -qiE 'amd|ati'   && has_amd=1
    printf '%s' "$g" | grep -qi intel        && has_intel=1
  fi
  GPU_LIST=()
  [ $has_nvidia = 1 ] && GPU_LIST+=(nvidia)
  [ $has_amd = 1 ]    && GPU_LIST+=(amd)
  [ $has_intel = 1 ]  && GPU_LIST+=(intel)
  # collapse to a single meaningful profile
  if   [ "$VIRT" != none ] && [ ${#GPU_LIST[@]} -eq 0 ]; then GPU_PROFILE=vm
  elif [ $has_nvidia = 1 ] && [ $has_intel = 1 ]; then GPU_PROFILE=nvidia-laptop   # Optimus (intel iGPU + nvidia dGPU)
  elif [ $has_nvidia = 1 ] && [ $has_amd = 1 ];   then GPU_PROFILE=nvidia-hybrid
  elif [ $has_nvidia = 1 ]; then GPU_PROFILE=nvidia
  elif [ $has_amd = 1 ];    then GPU_PROFILE=amd
  elif [ $has_intel = 1 ];  then GPU_PROFILE=intel
  else GPU_PROFILE=unknown; fi

  if compgen -G '/sys/class/power_supply/BAT*' >/dev/null 2>&1; then PLATFORM=laptop
  else case "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" in
    8|9|10|11|14) PLATFORM=laptop ;; *) PLATFORM=desktop ;; esac
  fi

  VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null | tr -d '\n')
  PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null | tr -d '\n')
  BOARD=$(cat /sys/class/dmi/id/board_name 2>/dev/null | tr -d '\n')

  PRIMARY_DISK=$(lsblk -dpno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1; exit}')
  local db=${PRIMARY_DISK##*/}
  SSD=0; [ -n "$db" ] && [ "$(cat /sys/block/$db/queue/rotational 2>/dev/null)" = 0 ] && SSD=1

  TIMEZONE=$(first "$(timedatectl show -p Timezone --value 2>/dev/null)" "$(cat /etc/timezone 2>/dev/null)" UTC)
  LOCALE=${LANG:-en_US.UTF-8}
  KEYMAP=$(localectl status 2>/dev/null | awk -F': ' '/Keymap/{print $2}')

  AGE_RECIPIENT=""
  if have ssh-to-age && [ -f /etc/ssh/ssh_host_ed25519_key.pub ]; then
    AGE_RECIPIENT=$(ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null)
  fi
}

# ── nixos-hardware modules (laptops only) ───────────────────────
# Match an exact model (board_name) if we can; otherwise fall back to the
# stable generic common-* modules for the detected cpu/gpu/laptop/ssd.
# hardwareModel is a LIST so the Nix side imports 1..n modules.
detect_hw_model() {
  HW_MODULES=(); HW_MODE=""
  if [ "$PLATFORM" != laptop ]; then HW_MODE=skip-nonlaptop; return; fi

  HW_TOKEN=$(printf '%s' "${BOARD:-}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
  if [ -n "$HW_TOKEN" ] && [ "${LOOKUP_HW:-1}" != 0 ] && have nix; then
    local json matches
    json=$(timeout 25 nix eval github:NixOS/nixos-hardware#nixosModules \
             --apply 'builtins.attrNames' --json \
             --extra-experimental-features 'nix-command flakes' 2>/dev/null)
    if [ -n "$json" ]; then
      matches=$(printf '%s' "$json" | tr -d '[]"' | tr ',' '\n' | awk -v t="$HW_TOKEN" 'index($0,t)')
      if [ "$(printf '%s' "$matches" | grep -c .)" = 1 ]; then
        HW_MODULES=("$matches"); HW_MODE=model; return
      fi
    fi
  fi

  HW_MODE=generic
  [ -n "$CPU" ] && HW_MODULES+=("common-cpu-$CPU")
  case "$GPU_PROFILE" in
    nvidia|nvidia-laptop|nvidia-hybrid) HW_MODULES+=("common-gpu-nvidia") ;;
    amd)   HW_MODULES+=("common-gpu-amd") ;;
    intel) HW_MODULES+=("common-gpu-intel") ;;
  esac
  HW_MODULES+=("common-pc-laptop")
  [ "$SSD" = 1 ] && HW_MODULES+=("common-pc-laptop-ssd")
}

# ── identity (only interactive part) ────────────────────────────
gather_identity() {
  local reply def_user
  printInfo "Hostname — lowercase machine name, e.g. framework-13 (not 'default')"
  while :; do
    read -rp "  hostname> " reply || true
    reply=${reply,,}
    case "$reply" in ""|default) printError "pick a real hostname"; continue ;; esac
    [[ "$reply" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || { printError "letters, digits, hyphens only"; continue; }
    HOSTNAME_IN="$reply"; break
  done

  def_user=$(first "$(logname 2>/dev/null)" "${SUDO_USER:-}" "${USER:-}")
  case "$def_user" in ""|user|default|root|nixos) def_user="" ;; esac
  printInfo "Username — your login${def_user:+ (suggested: $def_user)}, lowercase (not 'user')"
  while :; do
    read -rp "  username> " reply || true
    reply=${reply:-$def_user}
    case "$reply" in ""|user|default) printError "pick a real username"; continue ;; esac
    [[ "$reply" =~ ^[a-z_][a-z0-9_-]*$ ]] || { printError "start with a letter/_, then lowercase / digits / - _"; continue; }
    USERNAME_IN="$reply"; break
  done
  ROLES=${ROLES:-base,desktop}
}

# ── host.json preview (hand-built, no jq) ───────────────────────
build_host_json() {
  local age_json="null"; [ -n "$AGE_RECIPIENT" ] && age_json=$(jstr "$AGE_RECIPIENT")
  cat <<JSON
{
  "hostname": $(jstr "$HOSTNAME_IN"),
  "system": $(jstr "$SYSTEM"),
  "platform": $(jstr "$PLATFORM"),
  "firmware": $(jstr "$FIRMWARE"),
  "virt": $(jstr "$VIRT"),
  "cpu": $(jstr "$CPU"),
  "gpu": $(jarr "${GPU_LIST[@]:-}"),
  "gpuProfile": $(jstr "$GPU_PROFILE"),
  "hardwareModel": $(jarr "${HW_MODULES[@]:-}"),
  "detected": { "vendor": $(jstr "$VENDOR"), "product": $(jstr "$PRODUCT"), "board": $(jstr "$BOARD") },
  "roles": $(jarr $(printf '%s' "$ROLES" | tr ',' ' ')),
  "user": $(jstr "$USERNAME_IN"),
  "locale": { "timeZone": $(jstr "$TIMEZONE"), "locale": $(jstr "$LOCALE"), "keymap": $(jstr "${KEYMAP:-us}") },
  "primaryDisk": $(jstr "$PRIMARY_DISK"),
  "secrets": { "sopsFile": $(jstr "secrets/$HOSTNAME_IN.yaml"), "hostAgeRecipient": $age_json }
}
JSON
}

# ── main ────────────────────────────────────────────────────────
clear 2>/dev/null || true
printHeader "NixOS installer — draft (detect + preview, no changes)"

printHeader "Preflight"
verify || printWarn "preflight has failures — a real install would stop here (draft continues)"

printHeader "Detecting hardware"
detect
printSuccess "System:   $SYSTEM ($FIRMWARE, virt=$VIRT)"
[ -n "$CPU" ]           && printSuccess "CPU:      $CPU" || printWarn "CPU:      not detected"
if [ ${#GPU_LIST[@]} -gt 0 ]; then printSuccess "GPU:      ${GPU_LIST[*]}  → profile: $GPU_PROFILE"
else printWarn "GPU:      none found (profile: $GPU_PROFILE — normal under a VM/WSL)"; fi
printSuccess "Platform: $PLATFORM"
[ -n "$BOARD$PRODUCT" ] && printSuccess "Board:    ${VENDOR:-?} ${PRODUCT:-} [${BOARD:-?}]" || printWarn "Board:    not detected"
if [ -n "$PRIMARY_DISK" ]; then printSuccess "Disk:     $PRIMARY_DISK ($([ "$SSD" = 1 ] && echo ssd || echo rotational))"
else printWarn "Disk:     not detected"; fi
printSuccess "Locale:   $TIMEZONE / ${KEYMAP:-us} / $LOCALE"
[ -n "$AGE_RECIPIENT" ] && printSuccess "Age key:  $AGE_RECIPIENT" || printWarn "Age key:  none yet (host ed25519 key / ssh-to-age)"

printHeader "nixos-hardware"
detect_hw_model
case "$HW_MODE" in
  skip-nonlaptop) printInfo "not a laptop → skipping (hardwareModel = [])" ;;
  model)          printSuccess "matched model: ${HW_MODULES[0]}" ;;
  generic)        printSuccess "generic modules: ${HW_MODULES[*]}"
                  have nix || printInfo "exact-model lookup skipped (no nix); generics are unvalidated" ;;
esac

printHeader "Identity"
gather_identity

printHeader "hosts/$HOSTNAME_IN/host.json (preview — not written)"
build_host_json

printHeader "Planned steps (not executed)"
cat <<PLAN
  pre:
    [ ] nix-shell -p git ssh-to-age nixos-install-tools   # if missing
    [ ] nixos-generate-config --show-hardware-config > hosts/$HOSTNAME_IN/hardware.nix
    [ ] template hosts/$HOSTNAME_IN/disko.nix from ${PRIMARY_DISK:-<disk>}
    [ ] ensure /etc/ssh/ssh_host_ed25519_key, then ssh-to-age -> host.json.secrets + .sops.yaml
    [ ] re-encrypt sops secrets for the new host recipient
  install:
    [ ] disko  (only if wiping ${PRIMARY_DISK:-<disk>})
    [ ] nixos-install --flake "$REPO_DIR#$HOSTNAME_IN"     # or nixos-anywhere
    #   Nix side imports each hardwareModel entry:
    #   imports = map (m: inputs.nixos-hardware.nixosModules.\${m}) host.hardwareModel;
  post:
    [ ] passwd for $USERNAME_IN  (until sops hashedPasswordFile is wired)
    [ ] git add hosts/$HOSTNAME_IN/host.json && commit
    [ ] reboot; first boot: just switch
PLAN

printHeader "Done"
printInfo "Draft only — nothing was written or installed."
