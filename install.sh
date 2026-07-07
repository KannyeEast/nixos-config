#!/usr/bin/env bash
# Rough draft installer (fresh NixOS assumed).
# Preflight -> detect hardware -> ask identity -> print the host.json it WOULD
# write + the pre/post plan. Changes nothing. No jq dependency.
#
# Env toggles:  ROLES=base,desktop   LOOKUP_HW=0 (skip nixos-hardware query)
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

have()   { command -v "$1" >/dev/null 2>&1; }
first()  { for v in "$@"; do [ -n "$v" ] && { printf '%s' "$v"; return; }; done; }
in_list(){ local x; for x in "${GPU_LIST[@]:-}"; do [ "$x" = "$1" ] && return 0; done; return 1; }

# ── minimal JSON emitters (no jq) ───────────────────────────────
jstr() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"; }
jarr() { local out="" a; for a in "$@"; do [ -n "$a" ] || continue; out+="${out:+, }$(jstr "$a")"; done; printf '[%s]' "$out"; }

# NVIDIA architecture: read the chip codename the kernel reports (authoritative),
# fall back to approximate PCI device-id ranges only if that's unavailable.
nvidia_arch() {
  local chip
  chip=$( { dmesg 2>/dev/null | grep -iE 'nouveau|nvidia'; lspci -d 10de:: 2>/dev/null; } \
          | grep -oE '\b(GB|AD|GA|TU|GV|GP|GM|GK|GF)[0-9]{3}[A-Za-z]?\b' | head -1 )
  case "${chip:0:2}" in
    GB) echo blackwell;    return ;; AD) echo ada-lovelace; return ;;
    GA) echo ampere;       return ;; TU) echo turing;       return ;;
    GV) echo volta;        return ;; GP) echo pascal;       return ;;
    GM) echo maxwell;      return ;; GK) echo kepler;       return ;;
    GF) echo fermi;        return ;;
  esac
  local id=$(( ${1:-0} ))
  if   [ $id -ge $((0x2900)) ] && [ $id -le $((0x2FFF)) ]; then echo blackwell
  elif [ $id -ge $((0x2600)) ] && [ $id -le $((0x28FF)) ]; then echo ada-lovelace
  elif [ $id -ge $((0x2200)) ] && [ $id -le $((0x25FF)) ]; then echo ampere
  elif [ $id -ge $((0x1E00)) ] && [ $id -le $((0x21FF)) ]; then echo turing
  elif [ $id -ge $((0x1B00)) ] && [ $id -le $((0x1DFF)) ]; then echo pascal; fi
}

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
  have gcc && printSuccess "gcc available (exact -march / intel codename)" \
    || printInfo "gcc absent — march falls back to x86-64 level; intel gen unknown"
  have ssh-to-age && printSuccess "ssh-to-age available" \
    || printInfo "ssh-to-age absent — age recipient step will be a TODO"
  return $fail
}

# ── CPU: compiler march + nixos-hardware codename ───────────────
detect_cpu_march() {
  CPU_MARCH=""; CPU_CODENAME=""
  [ "$(uname -m)" = x86_64 ] || return
  local f lvl=1
  f=$(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null)
  printf '%s' "$f" | grep -qw sse4_2 && printf '%s' "$f" | grep -qw popcnt && lvl=2
  [ $lvl = 2 ] && printf '%s' "$f" | grep -qw avx2 && printf '%s' "$f" | grep -qw bmi2 \
                && printf '%s' "$f" | grep -qw fma && lvl=3
  [ $lvl = 3 ] && printf '%s' "$f" | grep -qw avx512f && lvl=4
  local exact=""
  have gcc && exact=$(gcc -march=native -Q --help=target 2>/dev/null \
                        | sed -n 's/^[[:space:]]*-march=[[:space:]]*//p' | head -1)
  CPU_MARCH=${exact:-x86-64-v$lvl}

  if [ "$CPU" = intel ] && [ -n "$exact" ]; then
    CPU_CODENAME=$(printf '%s' "$exact" | sed -E 's/(lake|bridge|well|cove|ridge|mont)$/-\1/')
  elif [ "$CPU" = amd ]; then
    local fam mod
    fam=$(awk -F: '$1 ~ /^cpu family[ \t]*$/{gsub(/ /,"",$2);print $2;exit}' /proc/cpuinfo)
    mod=$(awk -F: '$1 ~ /^model[ \t]*$/{gsub(/ /,"",$2);print $2;exit}' /proc/cpuinfo)
    case "$fam:$mod" in
      25:97) CPU_CODENAME=raphael ;;   # Zen4 desktop; extend as modules appear
    esac
  fi
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
  detect_cpu_march

  local d has_nvidia=0 has_amd=0 has_intel=0
  NVIDIA_DEVID=""
  for d in /sys/bus/pci/devices/*; do
    [ -e "$d/class" ] || continue
    case "$(cat "$d/class" 2>/dev/null)" in 0x03*) ;; *) continue ;; esac
    case "$(cat "$d/vendor" 2>/dev/null)" in
      0x10de) has_nvidia=1; NVIDIA_DEVID=$(cat "$d/device" 2>/dev/null) ;;
      0x1002) has_amd=1 ;;
      0x8086) has_intel=1 ;;
    esac
  done
  if [ $((has_nvidia + has_amd + has_intel)) -eq 0 ] && have lspci; then
    local g; g=$(lspci 2>/dev/null | grep -Ei 'vga|3d|display')
    printf '%s' "$g" | grep -qi nvidia     && has_nvidia=1
    printf '%s' "$g" | grep -qiE 'amd|ati' && has_amd=1
    printf '%s' "$g" | grep -qi intel      && has_intel=1
  fi
  GPU_LIST=()
  [ $has_nvidia = 1 ] && GPU_LIST+=(nvidia)
  [ $has_amd = 1 ]    && GPU_LIST+=(amd)
  [ $has_intel = 1 ]  && GPU_LIST+=(intel)

  # Which one is the discrete GPU (the one that matters for arch):
  #   nvidia present -> nvidia; intel+amd -> the vendor that ISN'T the CPU (iGPU);
  #   otherwise the single GPU.
  if   [ $has_nvidia = 1 ]; then DGPU=nvidia
  elif [ $has_amd = 1 ] && [ $has_intel = 1 ]; then { [ "$CPU" = intel ] && DGPU=amd; } || DGPU=intel
  elif [ $has_amd = 1 ];   then DGPU=amd
  elif [ $has_intel = 1 ]; then DGPU=intel
  else DGPU=""; fi

  NVIDIA_ARCH=""
  [ "$DGPU" = nvidia ] && NVIDIA_ARCH=$(nvidia_arch "${NVIDIA_DEVID:-0}")

  if   [ "$VIRT" != none ] && [ ${#GPU_LIST[@]} -eq 0 ]; then GPU_PROFILE=vm
  elif [ $has_nvidia = 1 ] && [ $has_intel = 1 ]; then GPU_PROFILE=nvidia-laptop
  elif [ $has_nvidia = 1 ] && [ $has_amd = 1 ];   then GPU_PROFILE=nvidia-hybrid
  else GPU_PROFILE=${DGPU:-unknown}; fi

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

# ── nixos-hardware modules ──────────────────────────────────────
# exact model, else the most specific cpu/gpu arch modules (each imports its
# generic default). A hybrid imports both GPU modules; arch specificity lands on
# the discrete GPU. Every name validated against the live attr list.
detect_hw_model() {
  HW_MODULES=(); HW_MODE=generic; HW_VALIDATED=0
  local attrs=""
  HW_TOKEN=$(printf '%s' "${BOARD:-}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
  if [ "${LOOKUP_HW:-1}" != 0 ] && have nix; then
    attrs=$(timeout 25 nix eval github:NixOS/nixos-hardware#nixosModules \
              --apply 'builtins.attrNames' --json \
              --extra-experimental-features 'nix-command flakes' 2>/dev/null \
              | tr -d '[]"' | tr ',' '\n')
    [ -n "$attrs" ] && HW_VALIDATED=1
  fi
  has_attr() { [ "$HW_VALIDATED" = 1 ] && printf '%s\n' "$attrs" | grep -qx "$1"; }
  pick()     { local base=$1 spec=$2; { [ -n "$spec" ] && has_attr "$spec"; } && printf '%s' "$spec" || printf '%s' "$base"; }

  # 1) exact model by board token
  if [ "$HW_VALIDATED" = 1 ] && [ -n "$HW_TOKEN" ]; then
    local m; m=$(printf '%s\n' "$attrs" | awk -v t="$HW_TOKEN" 'index($0,t)')
    if [ "$(printf '%s' "$m" | grep -c .)" = 1 ]; then HW_MODULES=("$m"); HW_MODE=model; return; fi
  fi

  # 2) cpu arch (specific gen if available)
  [ -n "$CPU" ] && HW_MODULES+=("$(pick "common-cpu-$CPU" "${CPU_CODENAME:+common-cpu-$CPU-$CPU_CODENAME}")")

  # 3) gpu: one module per present vendor (iGPU + dGPU); arch on the discrete one
  if in_list intel; then
    local ig=""; [ "$CPU" = intel ] && [ -n "$CPU_CODENAME" ] && ig="common-gpu-intel-$CPU_CODENAME"
    HW_MODULES+=("$(pick common-gpu-intel "$ig")")
  fi
  in_list nvidia && HW_MODULES+=("$(pick common-gpu-nvidia "${NVIDIA_ARCH:+common-gpu-nvidia-$NVIDIA_ARCH}")")
  in_list amd    && HW_MODULES+=("common-gpu-amd")

  # 4) platform bits
  if [ "$PLATFORM" = laptop ]; then
    HW_MODULES+=("common-pc-laptop"); [ "$SSD" = 1 ] && HW_MODULES+=("common-pc-laptop-ssd")
  else
    [ "$SSD" = 1 ] && HW_MODULES+=("common-pc-ssd")
  fi

  if [ "$HW_VALIDATED" = 1 ]; then
    local keep=() x; for x in "${HW_MODULES[@]}"; do has_attr "$x" && keep+=("$x"); done
    HW_MODULES=("${keep[@]}")
  fi
}

# ── identity (only interactive part) ────────────────────────────
gather_identity() {
  local def_host def_user
  def_host=$(first "$(uname -n 2>/dev/null)" "$(hostname 2>/dev/null)")
  case "$def_host" in default|localhost) def_host="" ;; esac
  while :; do
    if [ -n "$def_host" ]; then read -e -r -i "$def_host" -p "  hostname: " HOSTNAME_IN || true
    else read -e -r -p "  hostname: " HOSTNAME_IN || true; fi
    HOSTNAME_IN=${HOSTNAME_IN,,}
    case "$HOSTNAME_IN" in
      "")      printError "hostname required"; continue ;;
      default) printError "'default' is the example placeholder — pick another"; continue ;;
    esac
    [[ "$HOSTNAME_IN" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || { printError "letters, digits, hyphens only"; continue; }
    break
  done

  def_user=$(first "$(logname 2>/dev/null)" "${SUDO_USER:-}" "${USER:-}")
  case "$def_user" in user|default|root|nixos) def_user="" ;; esac
  while :; do
    if [ -n "$def_user" ]; then read -e -r -i "$def_user" -p "  username: " USERNAME_IN || true
    else read -e -r -p "  username: " USERNAME_IN || true; fi
    case "$USERNAME_IN" in
      "")           printError "username required"; continue ;;
      user|default) printError "'$USERNAME_IN' is the example placeholder — pick another"; continue ;;
    esac
    [[ "$USERNAME_IN" =~ ^[a-z_][a-z0-9_-]*$ ]] || { printError "start with a letter/_, then lowercase / digits / - _"; continue; }
    break
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
  "cpu": { "vendor": $(jstr "$CPU"), "march": $(jstr "$CPU_MARCH") },
  "gpu": $(jarr "${GPU_LIST[@]:-}"),
  "dgpu": { "vendor": $(jstr "$DGPU"), "arch": $(jstr "$NVIDIA_ARCH"), "profile": $(jstr "$GPU_PROFILE") },
  "hardwareModel": $(jarr "${HW_MODULES[@]:-}"),
  "detected": { "vendor": $(jstr "$VENDOR"), "product": $(jstr "$PRODUCT"), "board": $(jstr "$BOARD"), "nvidiaDevice": $(jstr "$NVIDIA_DEVID") },
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
if [ -n "$CPU" ]; then printSuccess "CPU:      $CPU  (march=$CPU_MARCH${CPU_CODENAME:+, gen=$CPU_CODENAME})"
else printWarn "CPU:      not detected"; fi
[ -n "$CPU_MARCH" ] && printInfo "march is optional tuning (nixpkgs.hostPlatform.gcc.arch) — bypasses the binary cache"
if [ ${#GPU_LIST[@]} -gt 0 ]; then
  gpu_desc=""
  for v in "${GPU_LIST[@]}"; do
    if [ "$v" = "$DGPU" ]; then gpu_desc+="${gpu_desc:+, }$v(dGPU)"; else gpu_desc+="${gpu_desc:+, }$v(iGPU)"; fi
  done
  printSuccess "GPU:      $gpu_desc${NVIDIA_ARCH:+  → $DGPU $NVIDIA_ARCH}"
  [ "$DGPU" = nvidia ] && [ -z "$NVIDIA_ARCH" ] && printWarn "nvidia arch unknown (dev=$NVIDIA_DEVID) — set the gpu module by hand"
else printWarn "GPU:      none found (profile: $GPU_PROFILE — normal under a VM/WSL)"; fi
printSuccess "Platform: $PLATFORM"
[ -n "$BOARD$PRODUCT" ] && printSuccess "Board:    ${VENDOR:-?} ${PRODUCT:-} [${BOARD:-?}]" || printWarn "Board:    not detected"
if [ -n "$PRIMARY_DISK" ]; then printSuccess "Disk:     $PRIMARY_DISK ($([ "$SSD" = 1 ] && echo ssd || echo rotational))"
else printWarn "Disk:     not detected"; fi
printSuccess "Locale:   $TIMEZONE / ${KEYMAP:-us} / $LOCALE"
[ -n "$AGE_RECIPIENT" ] && printSuccess "Age key:  $AGE_RECIPIENT" || printWarn "Age key:  none yet (host ed25519 key / ssh-to-age)"

printHeader "nixos-hardware"
detect_hw_model
if [ "$HW_MODE" = model ]; then printSuccess "matched model: ${HW_MODULES[0]}"
elif [ ${#HW_MODULES[@]} -gt 0 ]; then printSuccess "modules: ${HW_MODULES[*]}"
else printWarn "no modules resolved"; fi
[ "$HW_VALIDATED" = 1 ] || printInfo "not validated against nixos-hardware (no nix / LOOKUP_HW=0) — names are best-effort"

printHeader "Identity"
gather_identity

printHeader "hosts/$HOSTNAME_IN/host.json (preview — not written)"
build_host_json

printHeader "Planned steps (not executed)"
cat <<PLAN
  pre:
    [ ] nix-shell -p git gcc ssh-to-age nixos-install-tools   # if missing
    [ ] nixos-generate-config --show-hardware-config > hosts/$HOSTNAME_IN/hardware.nix
    [ ] template hosts/$HOSTNAME_IN/disko.nix from ${PRIMARY_DISK:-<disk>}
    [ ] ensure /etc/ssh/ssh_host_ed25519_key, then ssh-to-age -> host.json.secrets + .sops.yaml
    [ ] re-encrypt sops secrets for the new host recipient
  install:
    [ ] disko  (only if wiping ${PRIMARY_DISK:-<disk>})
    [ ] nixos-install --flake "$REPO_DIR#$HOSTNAME_IN"     # or nixos-anywhere
    #   Nix side imports each hardwareModel entry:
    #   imports = map (m: inputs.nixos-hardware.nixosModules.\${m}) host.hardwareModel;
    #   (hybrid prime bus IDs still set by hand or via the exact-model module)
  post:
    [ ] passwd for $USERNAME_IN  (until sops hashedPasswordFile is wired)
    [ ] git add hosts/$HOSTNAME_IN/host.json && commit
    [ ] reboot; first boot: just switch
PLAN

printHeader "Done"
printInfo "Draft only — nothing was written or installed."
