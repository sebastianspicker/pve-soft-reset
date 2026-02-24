#!/usr/bin/env bash
#
# pve-soft-reset.sh - audit-based soft reset for Proxmox VE hosts
#
# Stable v1.x track (non-breaking CLI compatibility + additive improvements)
#
set -euo pipefail

VERSION="1.1.0"

readonly EXIT_OK=0
readonly EXIT_RUNTIME=1
readonly EXIT_USAGE=2
readonly EXIT_PREFLIGHT=3

# -----------------------------------------------------------------------------
# Options
# -----------------------------------------------------------------------------
DRY_RUN=false
AUDIT_ONLY=false
PLAN_ONLY=false
LIST_STORAGE=false
JSON_OUTPUT=false
CONFIRM=true
PURGE_ALL_THIRD_PARTY=false
RESET_PVE_CONFIG=false
RESET_USERS_DATACENTER=false
RESET_STORAGE_CFG=false
BACKUP_CONFIG=false
VERBOSE=false
QUIET=false
NO_SYNC=false
NO_COLOR=false

INCLUDE_STORAGE_CSV=""
EXCLUDE_STORAGE_CSV=""

PVE_ETC="${PVE_ETC:-/etc/pve}"
STORAGE_CFG="${STORAGE_CFG:-/etc/pve/storage.cfg}"
LOG_FILE="${LOG_FILE:-/var/log/pve-soft-reset.log}"

# Test mode allows non-root and non-/etc/pve paths (used by automated tests).
TEST_MODE="${PVE_SOFT_RESET_TEST_MODE:-0}"

# Internal separator for safe tuple storage
SEP=$'\037'

# Content type -> directory mapping for dir storages
# PVE content types: images, rootdir, vztmpl, iso, backup, snippets
declare -A CONTENT_SUBDIR_MAP=(
  [images]=images
  [rootdir]=rootdir
  [vztmpl]=template/cache
  [iso]=template/iso
  [backup]=dump
  [snippets]=snippets
)
EXTRA_SUBDIRS=(template/qemu)

LVM_PROTECTED_DEFAULT="root swap data"
LVM_WIPE_EXTRA_PATTERN="${LVM_WIPE_EXTRA_PATTERN:-}"

# Third-party package detection baseline
VANILLA_ORIGINS="${VANILLA_ORIGINS:-Debian Proxmox}"
VANILLA_INCLUDE_CEPH="${VANILLA_INCLUDE_CEPH:-0}"
VANILLA_URI_PATTERNS="${VANILLA_URI_PATTERNS:-deb.debian.org security.debian.org download.proxmox.com enterprise.proxmox.com}"

# Known third-party stack defaults (CrowdSec)
CROWDSEC_SERVICES=(crowdsec crowdsec-firewall-bouncer crowdsec-firewall-bouncer-nftables crowdsec-firewall-bouncer-iptables)
CROWDSEC_PACKAGES=(crowdsec crowdsec-firewall-bouncer-nftables crowdsec-firewall-bouncer-iptables)
CROWDSEC_DIRS=(/etc/crowdsec /var/lib/crowdsec /var/log/crowdsec)

# Dir storage guardrail
ALLOWED_DIR_STORAGE_BASE="${ALLOWED_DIR_STORAGE_BASE:-/var/lib/vz}"

# -----------------------------------------------------------------------------
# Runtime state
# -----------------------------------------------------------------------------
USE_COLOR=false
ENABLE_FILE_LOG=false
EXEC_MODE="execute"

FAILURE_COUNT=0
DIRS_WIPED=0
LVS_REMOVED=0
ZFS_REMOVED=0
CONFIGS_CLEARED=0

WIPE_DIR_ENTRIES=()   # id|path|subdir|subdir...
WIPE_LVM_VGS=()       # id|vg|thinpool
WIPE_LVM_ENTRIES=()   # id|vg|lv|lv...
WIPE_ZFS_POOLS=()     # id|pool
WIPE_ZFS_ENTRIES=()   # id|pool|dataset|dataset...

THIRD_PARTY_PACKAGES=()
THIRD_PARTY_WITH_ORIGIN=() # origin|pkg
PURGE_SERVICES=()
PURGE_PACKAGES=()
PURGE_DIRS=()

FIREWALL_STACK="unknown"
CEPH_FOUND=false
SSH_KEYS_FOUND=false

STORAGE_IDS_DISCOVERED=()

# -----------------------------------------------------------------------------
# Colors & logging
# -----------------------------------------------------------------------------
color_red()   { if $USE_COLOR; then printf "%s" "$(tput setaf 1 2>/dev/null)"; fi; return 0; }
color_green() { if $USE_COLOR; then printf "%s" "$(tput setaf 2 2>/dev/null)"; fi; return 0; }
color_yellow(){ if $USE_COLOR; then printf "%s" "$(tput setaf 3 2>/dev/null)"; fi; return 0; }
color_reset() { if $USE_COLOR; then printf "%s" "$(tput sgr0 2>/dev/null)"; fi; return 0; }

_log_line() {
  local line="$1"
  local level="${2:-INFO}"

  local print_console=true
  if $QUIET && [[ "$level" != "ERROR" && "$level" != "WARN" ]]; then
    print_console=false
  fi
  if [[ "$level" == "DEBUG" ]] && ! $VERBOSE; then
    print_console=false
  fi

  if $print_console; then
    local out_fd=1
    $JSON_OUTPUT && out_fd=2
    if [[ "$level" == "ERROR" ]]; then
      color_red; printf "%s\n" "$line" >&"$out_fd"; color_reset
    elif [[ "$level" == "WARN" ]]; then
      color_yellow; printf "%s\n" "$line" >&"$out_fd"; color_reset
    elif [[ "$level" == "SUCCESS" ]]; then
      color_green; printf "%s\n" "$line" >&"$out_fd"; color_reset
    else
      printf "%s\n" "$line" >&"$out_fd"
    fi
  fi

  if $ENABLE_FILE_LOG; then
    printf "%s\n" "$line" >> "$LOG_FILE" 2>/dev/null || true
  fi
}

log_info()    { _log_line "[$(date '+%Y-%m-%d %H:%M:%S')] $*" "INFO"; }
log_warn()    { _log_line "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*" "WARN"; }
log_error()   { _log_line "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" "ERROR"; }
log_success() { _log_line "[$(date '+%Y-%m-%d %H:%M:%S')] $*" "SUCCESS"; }
log_dry()     { _log_line "[DRY-RUN] $*" "INFO"; }

usage() {
  local c_opt c_rst
  c_opt="$(color_green)"
  c_rst="$(color_reset)"

  cat <<USAGE
Usage: ${c_opt}$0${c_rst} [OPTIONS]

General:
  ${c_opt}--dry-run${c_rst}                    Simulate execution (no modifications).
  ${c_opt}--audit-only${c_rst}                 Run audit, print planned actions, exit.
  ${c_opt}--plan${c_rst}                       Deterministic plan output, no execution, no prompts.
  ${c_opt}--list-storage${c_rst}               List discovered storage IDs and exit.
  ${c_opt}--json${c_rst}                       Output audit result JSON and exit.
  ${c_opt}-y, --yes${c_rst}                    Skip confirmation prompts.

Scope / UX:
  ${c_opt}--include-storage <csv>${c_rst}      Only include the listed storage IDs.
  ${c_opt}--exclude-storage <csv>${c_rst}      Exclude the listed storage IDs.
  ${c_opt}--no-sync${c_rst}                    Skip sync calls after wipe phases.
  ${c_opt}--no-color${c_rst}                   Disable ANSI colors.
  ${c_opt}--verbose${c_rst}                    Enable verbose output.
  ${c_opt}--quiet${c_rst}                      Minimal output (warnings/errors only).
  ${c_opt}--log-file <path>${c_rst}            Custom log file path.

Reset features:
  ${c_opt}--reset-pve-config${c_rst}           Reset guest configs, SDN, mappings, jobs, firewall, HA.
  ${c_opt}--reset-users-datacenter${c_rst}     Reset users/ACL/secrets/datacenter to minimal defaults.
  ${c_opt}--reset-storage-cfg${c_rst}          Overwrite storage.cfg with vanilla default.
  ${c_opt}--reset-all${c_rst}                  Equivalent to all three reset flags above.
  ${c_opt}--backup-config${c_rst}              Backup /etc/pve before reset operations.

Third-party purge:
  ${c_opt}--purge-all-third-party${c_rst}      Purge all detected non-vanilla packages.

Meta:
  ${c_opt}--version${c_rst}                    Print version and exit.
  ${c_opt}--help${c_rst}                       Show this help.
USAGE
}

die_usage() {
  local msg="$1"
  [[ -n "$msg" ]] && printf "Usage error: %s\n" "$msg" >&2
  printf "Use --help for usage.\n" >&2
  exit "$EXIT_USAGE"
}

die_preflight() {
  local msg="$1"
  printf "Preflight error: %s\n" "$msg" >&2
  exit "$EXIT_PREFLIGHT"
}

# -----------------------------------------------------------------------------
# Generic helpers
# -----------------------------------------------------------------------------
trim() {
  local var="$*"
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  printf "%s" "$var"
}

split_sep() {
  PIPE_LEFT="${1%%"$SEP"*}"
  PIPE_RIGHT="${1#*"$SEP"}"
}

safe_realpath() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    if realpath -m -- "$p" >/dev/null 2>&1; then
      realpath -m -- "$p" 2>/dev/null || printf ""
    else
      realpath -- "$p" 2>/dev/null || printf ""
    fi
  else
    readlink -f -- "$p" 2>/dev/null || printf ""
  fi
}

is_safe_subdir() {
  local sub="$1"
  [[ -z "$sub" ]] && return 1
  [[ "$sub" == *".."* ]] && return 1
  [[ "$sub" == /* ]] && return 1
  case "$sub" in *[*?]*|*'*'*) return 1 ;; esac
  return 0
}

is_local_dir_path_simple() {
  local path="$1"
  [[ -z "$path" ]] && return 1
  [[ -d "$path" ]] || return 1
  [[ "$path" == /mnt/pve/* ]] && return 1

  local canonical
  canonical="$(safe_realpath "$path")"
  [[ -z "$canonical" ]] && return 1

  local allowed_arr=()
  local allowed allowed_canon
  IFS=':' read -r -a allowed_arr <<< "${ALLOWED_DIR_STORAGE_BASE:-}"
  for allowed in "${allowed_arr[@]}"; do
    allowed="$(trim "$allowed")"
    [[ -z "$allowed" ]] && continue
    allowed_canon="$(safe_realpath "$allowed")"
    [[ -z "$allowed_canon" ]] && allowed_canon="$allowed"
    if [[ "$canonical" == "$allowed_canon" || "$canonical" == "$allowed_canon"/* ]]; then
      return 0
    fi
  done
  return 1
}

csv_to_array() {
  local csv="$1"
  local out_name="$2"
  local raw_arr=()
  local item
  IFS=',' read -r -a raw_arr <<< "$csv"
  local cleaned=()
  for item in "${raw_arr[@]}"; do
    item="$(trim "$item")"
    [[ -n "$item" ]] && cleaned+=("$item")
  done

  local -n out_ref="$out_name"
  out_ref=()
  for item in "${cleaned[@]}"; do
    out_ref+=("$item")
  done
}

run_or_dry() {
  local dry_msg="$1"
  local exec_msg="$2"
  shift 2

  if $DRY_RUN; then
    log_dry "$dry_msg"
    return 0
  fi

  log_info "$exec_msg"
  if ! "$@"; then
    ((FAILURE_COUNT+=1))
    return 1
  fi
  return 0
}

run_or_dry_destructive() {
  local dry_msg="$1"
  local exec_msg="$2"
  shift 2

  if $DRY_RUN; then
    log_dry "$dry_msg"
    return 0
  fi

  color_red
  log_info "$exec_msg"
  color_reset

  if ! "$@"; then
    ((FAILURE_COUNT+=1))
    return 1
  fi
  return 0
}

run_or_dry_clear() {
  local dry_msg="$1"
  local exec_msg="$2"
  local file="$3"

  if $DRY_RUN; then
    log_dry "$dry_msg"
  else
    log_info "$exec_msg"
    : > "$file" || ((FAILURE_COUNT+=1))
  fi
}

run_or_dry_write() {
  local dry_msg="$1"
  local exec_msg="$2"
  local file="$3"
  local content="$4"

  if $DRY_RUN; then
    log_dry "$dry_msg"
  else
    log_info "$exec_msg"
    printf "%b" "$content" > "$file" || ((FAILURE_COUNT+=1))
  fi
  ((CONFIGS_CLEARED+=1))
}

clear_cfg_if_exists() {
  local file="$1"
  local label="$2"
  [[ -f "$file" ]] || return 0
  run_or_dry_clear "Clear $file" "$label" "$file"
  ((CONFIGS_CLEARED+=1))
}

remove_file_if_exists() {
  local file="$1"
  local label="$2"
  [[ -f "$file" ]] || return 0
  run_or_dry "rm $file" "$label" rm -f "$file"
  ((CONFIGS_CLEARED+=1))
}

wipe_dir_contents() {
  local dir="$1"
  local label="$2"
  [[ -d "$dir" ]] || return 0
  run_or_dry "rm -rf $dir/*" "$label" find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf --one-file-system {} +
}

remove_matching_glob() {
  local base="$1"
  local pattern="$2"
  local label_prefix="$3"
  local f

  [[ -d "$base" ]] || return 0
  while IFS= read -r -d '' f; do
    run_or_dry "rm $f" "$label_prefix: $f" rm -f "$f"
    ((CONFIGS_CLEARED+=1))
  done < <(find "$base" -maxdepth 1 -name "$pattern" -print0 2>/dev/null)
}

confirm_action() {
  local prompt="$1"
  if ! $CONFIRM; then
    return 0
  fi

  local ans
  read -r -p "$prompt [y/N] " ans
  [[ "$ans" =~ ^[yY]([eE][sS])?$ ]]
}

bool_json() {
  $1 && printf "true" || printf "false"
}

json_escape() {
  sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g; s/[[:cntrl:]]/ /g'
}

json_array() {
  local first=1
  local item
  for item in "$@"; do
    [[ -z "$item" ]] && continue
    [[ $first -eq 1 ]] && first=0 || printf ","
    printf '"%s"' "$(printf "%s" "$item" | tr "$SEP" '|' | json_escape)"
  done
}

collect_storage_ids() {
  local ids=()
  local entry

  for entry in "${WIPE_DIR_ENTRIES[@]}"; do
    [[ -z "$entry" ]] && continue
    split_sep "$entry"
    ids+=("$PIPE_LEFT")
  done
  for entry in "${WIPE_LVM_VGS[@]}"; do
    [[ -z "$entry" ]] && continue
    split_sep "$entry"
    ids+=("$PIPE_LEFT")
  done
  for entry in "${WIPE_ZFS_POOLS[@]}"; do
    [[ -z "$entry" ]] && continue
    split_sep "$entry"
    ids+=("$PIPE_LEFT")
  done

  STORAGE_IDS_DISCOVERED=()
  if [[ ${#ids[@]} -gt 0 ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && STORAGE_IDS_DISCOVERED+=("$line")
    done < <(printf "%s\n" "${ids[@]}" | sort -u)
  fi
}

storage_id_exists() {
  local needle="$1"
  local id
  for id in "${STORAGE_IDS_DISCOVERED[@]}"; do
    [[ "$id" == "$needle" ]] && return 0
  done
  return 1
}

storage_id_in_csv() {
  local id="$1"
  local csv="$2"
  local arr=()
  local x

  [[ -z "$csv" ]] && return 1
  csv_to_array "$csv" arr
  for x in "${arr[@]}"; do
    [[ "$x" == "$id" ]] && return 0
  done
  return 1
}

is_storage_allowed_by_scope() {
  local id="$1"

  if [[ -n "$INCLUDE_STORAGE_CSV" ]] && ! storage_id_in_csv "$id" "$INCLUDE_STORAGE_CSV"; then
    return 1
  fi
  if [[ -n "$EXCLUDE_STORAGE_CSV" ]] && storage_id_in_csv "$id" "$EXCLUDE_STORAGE_CSV"; then
    return 1
  fi
  return 0
}

apply_storage_scope_filters() {
  collect_storage_ids

  local scope_ids=()
  local sid

  if [[ -n "$INCLUDE_STORAGE_CSV" ]]; then
    csv_to_array "$INCLUDE_STORAGE_CSV" scope_ids
    for sid in "${scope_ids[@]}"; do
      storage_id_exists "$sid" || die_usage "Unknown storage ID in --include-storage: $sid"
    done
  fi

  if [[ -n "$EXCLUDE_STORAGE_CSV" ]]; then
    csv_to_array "$EXCLUDE_STORAGE_CSV" scope_ids
    for sid in "${scope_ids[@]}"; do
      storage_id_exists "$sid" || die_usage "Unknown storage ID in --exclude-storage: $sid"
    done
  fi

  local filtered=()
  local entry

  filtered=()
  for entry in "${WIPE_DIR_ENTRIES[@]}"; do
    [[ -z "$entry" ]] && continue
    split_sep "$entry"
    is_storage_allowed_by_scope "$PIPE_LEFT" && filtered+=("$entry")
  done
  WIPE_DIR_ENTRIES=("${filtered[@]}")

  filtered=()
  for entry in "${WIPE_LVM_VGS[@]}"; do
    [[ -z "$entry" ]] && continue
    split_sep "$entry"
    is_storage_allowed_by_scope "$PIPE_LEFT" && filtered+=("$entry")
  done
  WIPE_LVM_VGS=("${filtered[@]}")

  filtered=()
  for entry in "${WIPE_ZFS_POOLS[@]}"; do
    [[ -z "$entry" ]] && continue
    split_sep "$entry"
    is_storage_allowed_by_scope "$PIPE_LEFT" && filtered+=("$entry")
  done
  WIPE_ZFS_POOLS=("${filtered[@]}")

  collect_storage_ids
}

# -----------------------------------------------------------------------------
# CLI parsing
# -----------------------------------------------------------------------------
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=true ;;
      --audit-only) AUDIT_ONLY=true ;;
      --plan) PLAN_ONLY=true ;;
      --list-storage) LIST_STORAGE=true ;;
      --json) JSON_OUTPUT=true ;;
      -y|--yes) CONFIRM=false ;;

      --include-storage)
        shift
        [[ $# -gt 0 ]] || die_usage "--include-storage requires a CSV value"
        INCLUDE_STORAGE_CSV="$1"
        ;;
      --exclude-storage)
        shift
        [[ $# -gt 0 ]] || die_usage "--exclude-storage requires a CSV value"
        EXCLUDE_STORAGE_CSV="$1"
        ;;

      --reset-pve-config) RESET_PVE_CONFIG=true ;;
      --reset-users-datacenter) RESET_USERS_DATACENTER=true ;;
      --reset-storage-cfg) RESET_STORAGE_CFG=true ;;
      --reset-all)
        RESET_PVE_CONFIG=true
        RESET_USERS_DATACENTER=true
        RESET_STORAGE_CFG=true
        ;;
      --backup-config) BACKUP_CONFIG=true ;;
      --purge-all-third-party) PURGE_ALL_THIRD_PARTY=true ;;
      --verbose) VERBOSE=true ;;
      --quiet) QUIET=true ;;
      --no-sync) NO_SYNC=true ;;
      --no-color) NO_COLOR=true ;;

      --log-file)
        shift
        [[ $# -gt 0 ]] || die_usage "--log-file requires a path"
        LOG_FILE="$1"
        ;;

      --version)
        printf "pve-soft-reset %s\n" "$VERSION"
        exit "$EXIT_OK"
        ;;
      --help)
        usage
        exit "$EXIT_OK"
        ;;
      *)
        die_usage "Unknown option: $1"
        ;;
    esac
    shift
  done

  local mode_count=0
  $DRY_RUN && ((mode_count+=1))
  $AUDIT_ONLY && ((mode_count+=1))
  $PLAN_ONLY && ((mode_count+=1))
  $LIST_STORAGE && ((mode_count+=1))
  $JSON_OUTPUT && ((mode_count+=1))
  [[ $mode_count -gt 1 ]] && die_usage "Use only one of: --dry-run, --audit-only, --plan, --list-storage, --json"

  if $PLAN_ONLY; then
    CONFIRM=false
    EXEC_MODE="plan"
  elif $AUDIT_ONLY; then
    EXEC_MODE="audit"
  elif $JSON_OUTPUT; then
    EXEC_MODE="json"
  elif $LIST_STORAGE; then
    EXEC_MODE="list-storage"
  elif $DRY_RUN; then
    EXEC_MODE="dry-run"
  else
    EXEC_MODE="execute"
  fi

  if $QUIET && $VERBOSE; then
    die_usage "--quiet and --verbose cannot be used together"
  fi

  # Machine-friendly modes default to quiet output.
  if $JSON_OUTPUT || $LIST_STORAGE; then
    QUIET=true
  fi
}

# -----------------------------------------------------------------------------
# Config and preflight validation
# -----------------------------------------------------------------------------
validate_config_paths() {
  if [[ "$TEST_MODE" == "1" ]]; then
    return 0
  fi

  local pve_etc_canon storage_cfg_canon
  pve_etc_canon="$(safe_realpath "$PVE_ETC")"
  if [[ -z "$pve_etc_canon" && -d "$PVE_ETC" ]]; then
    pve_etc_canon="$(cd "$PVE_ETC" && pwd -P 2>/dev/null || true)"
  fi

  [[ -z "$pve_etc_canon" || "$pve_etc_canon" != "/etc/pve" ]] && die_preflight "PVE_ETC must resolve to /etc/pve (current: $PVE_ETC)"
  PVE_ETC="/etc/pve"

  if [[ -f "$STORAGE_CFG" ]]; then
    storage_cfg_canon="$(safe_realpath "$STORAGE_CFG")"
  else
    storage_cfg_canon="$(safe_realpath "$STORAGE_CFG")"
  fi
  [[ -z "$storage_cfg_canon" ]] && storage_cfg_canon="$STORAGE_CFG"

  case "$storage_cfg_canon" in
    /etc/pve|/etc/pve/*) ;;
    *) die_preflight "STORAGE_CFG must be under /etc/pve (current: $STORAGE_CFG)" ;;
  esac

  STORAGE_CFG="$storage_cfg_canon"
}

is_destructive_mode() {
  [[ "$EXEC_MODE" == "execute" ]]
}

check_root_requirements() {
  if [[ "$TEST_MODE" == "1" ]]; then
    return 0
  fi

  if is_destructive_mode && [[ $EUID -ne 0 ]]; then
    die_preflight "This mode requires root privileges"
  fi
}

check_cluster_quorum() {
  if command -v pvecm >/dev/null 2>&1 && pvecm status >/dev/null 2>&1; then
    if ! pvecm status 2>/dev/null | grep -q "Quorate:[[:space:]]*Yes"; then
      log_error "Cluster has no quorum. Shared /etc/pve modifications are not possible."
      return 1
    fi
  fi
  return 0
}

check_dependencies() {
  local missing=()
  local deps=(apt-cache dpkg-query hostname grep sed sort find)
  local d

  for d in "${deps[@]}"; do
    command -v "$d" >/dev/null 2>&1 || missing+=("$d")
  done

  if [[ ${#WIPE_LVM_VGS[@]} -gt 0 ]]; then
    command -v lvs >/dev/null 2>&1 || missing+=("lvs")
    if is_destructive_mode; then
      command -v lvremove >/dev/null 2>&1 || missing+=("lvremove")
    fi
  fi

  if [[ ${#WIPE_ZFS_POOLS[@]} -gt 0 ]]; then
    command -v zfs >/dev/null 2>&1 || missing+=("zfs")
  fi

  if is_destructive_mode; then
    command -v systemctl >/dev/null 2>&1 || missing+=("systemctl")
    command -v flock >/dev/null 2>&1 || missing+=("flock")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    die_preflight "Missing required tools: ${missing[*]}"
  fi
}

ensure_safety_guards() {
  local allowed_arr=()
  local allowed
  IFS=':' read -r -a allowed_arr <<< "${ALLOWED_DIR_STORAGE_BASE:-}"
  for allowed in "${allowed_arr[@]}"; do
    allowed="$(trim "$allowed")"
    case "$allowed" in
      ""|"/"|"/etc"|"/etc/"|"/root"|"/root/")
        die_preflight "ALLOWED_DIR_STORAGE_BASE contains blacklisted path: '$allowed'"
        ;;
    esac
  done
}

setup_runtime() {
  USE_COLOR=false
  [[ -t 1 ]] && USE_COLOR=true
  $NO_COLOR && USE_COLOR=false

  ENABLE_FILE_LOG=false
  if [[ $EUID -eq 0 && "$EXEC_MODE" != "plan" && "$EXEC_MODE" != "audit" && "$EXEC_MODE" != "json" && "$EXEC_MODE" != "list-storage" ]]; then
    ENABLE_FILE_LOG=true
  fi

  if ! is_destructive_mode; then
    return 0
  fi

  if [[ ! -e "$LOG_FILE" ]]; then
    touch "$LOG_FILE" 2>/dev/null || true
    chmod 0600 "$LOG_FILE" 2>/dev/null || true
  else
    local size=0
    size="$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)"
    if [[ "$size" -gt 10485760 ]]; then
      mv "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
      touch "$LOG_FILE" 2>/dev/null || true
      chmod 0600 "$LOG_FILE" 2>/dev/null || true
    fi
  fi

  local lockfile="/run/pve-soft-reset.lock"
  exec 9>"$lockfile"
  if ! flock -n 9; then
    die_preflight "Another instance of pve-soft-reset is already running"
  fi

  # shellcheck disable=SC2329
  cleanup_lock() {
    local rc=$?
    rm -f "$lockfile" 2>/dev/null || true
    exit "$rc"
  }
  trap cleanup_lock EXIT INT TERM
}

# -----------------------------------------------------------------------------
# Audit: storage.cfg
# -----------------------------------------------------------------------------
current_node_name() {
  local node=""
  if [[ -L /etc/pve/local ]]; then
    node="$(readlink /etc/pve/local 2>/dev/null || true)"
    node="${node##*/}"
  fi
  [[ -z "$node" ]] && node="$(hostname -s 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "")"
  printf "%s" "$node"
}

subdirs_for_content() {
  local content="$1"
  local content_dirs="$2"
  local subdirs_list=""
  local seen=""
  local c subdir ov

  for c in $(printf "%s" "$content" | tr ',' ' '); do
    c="$(trim "$c")"
    [[ -z "$c" ]] && continue
    subdir="${CONTENT_SUBDIR_MAP[$c]:-}"

    if [[ -n "$content_dirs" ]]; then
      for ov in $(printf "%s" "$content_dirs" | tr ',' ' '); do
        ov="$(trim "$ov")"
        if [[ "$ov" =~ ^${c}= ]]; then
          subdir="$(trim "${ov#*=}")"
          break
        fi
      done
    fi

    [[ -z "$subdir" ]] && continue
    is_safe_subdir "$subdir" || continue

    if [[ "${SEP}${seen}${SEP}" != *"${SEP}${subdir}${SEP}"* ]]; then
      seen="${seen}${seen:+$SEP}${subdir}"
      subdirs_list="${subdirs_list:+${subdirs_list}${SEP}}${subdir}"
    fi
  done

  for subdir in "${EXTRA_SUBDIRS[@]}"; do
    if [[ "${SEP}${seen}${SEP}" != *"${SEP}${subdir}${SEP}"* ]]; then
      subdirs_list="${subdirs_list:+${subdirs_list}${SEP}}${subdir}"
      seen="${seen}${seen:+$SEP}${subdir}"
    fi
  done

  printf "%s" "$subdirs_list"
}

emit_storage_block() {
  local type="$1"
  local id="$2"
  local path="$3"
  local content="$4"
  local content_dirs="$5"
  local vgname="$6"
  local thinpool="$7"
  local disable="$8"
  local nodes_list="$9"

  [[ -z "$type" || -z "$id" ]] && return 0

  if [[ -n "$disable" && "$disable" != "0" ]]; then
    return 0
  fi

  if [[ -n "$nodes_list" ]]; then
    local current_node
    current_node="$(current_node_name)"

    local found=false
    local n
    local node_arr=()
    IFS=',' read -r -a node_arr <<< "$nodes_list"
    for n in "${node_arr[@]}"; do
      n="$(trim "$n")"
      [[ -z "$n" ]] && continue
      if [[ "$n" == "$current_node" ]]; then
        found=true
        break
      fi
    done
    $found || return 0
  fi

  case "$type" in
    dir)
      if [[ "$id" == *"$SEP"* || "$path" == *"$SEP"* ]]; then
        return 0
      fi
      if is_local_dir_path_simple "$path"; then
        local subdirs
        subdirs="$(subdirs_for_content "$content" "$content_dirs")"
        [[ -n "$subdirs" ]] && WIPE_DIR_ENTRIES+=("${id}${SEP}${path}${SEP}${subdirs}")
      fi
      ;;
    lvm|lvmthin)
      if [[ -n "$vgname" && "$vgname" != *"$SEP"* ]]; then
        WIPE_LVM_VGS+=("${id}${SEP}${vgname}${SEP}${thinpool:-}")
      fi
      ;;
    zfspool)
      if [[ -n "$thinpool" && "$thinpool" != *"$SEP"* ]]; then
        WIPE_ZFS_POOLS+=("${id}${SEP}${thinpool}")
      fi
      ;;
    *) ;;
  esac
}

audit_storage_cfg() {
  local cfg="$1"
  [[ -f "$cfg" ]] || { log_warn "Storage config not found: $cfg"; return 0; }

  local type="" id="" path="" content="" content_dirs="" vgname="" thinpool="" disable="" nodes_list=""
  local line key val

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(trim "$line")"

    if [[ -z "$line" ]]; then
      continue
    fi

    if [[ "$line" =~ ^([A-Za-z0-9_-]+):[[:space:]]*(.+)$ ]]; then
      emit_storage_block "$type" "$id" "$path" "$content" "$content_dirs" "$vgname" "$thinpool" "$disable" "$nodes_list"

      type="${BASH_REMATCH[1]}"
      id="$(trim "${BASH_REMATCH[2]}")"
      path=""
      content=""
      content_dirs=""
      vgname=""
      thinpool=""
      disable=""
      nodes_list=""
      continue
    fi

    if [[ "$line" =~ ^(path|content|content-dirs|vgname|thinpool|pool|disable|nodes)[[:space:]]+(.+)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="$(trim "${BASH_REMATCH[2]}")"
      case "$key" in
        path) path="$val" ;;
        content) content="$val" ;;
        content-dirs) content_dirs="$val" ;;
        vgname) vgname="$val" ;;
        thinpool|pool) thinpool="$val" ;;
        disable) disable="$val" ;;
        nodes) nodes_list="$val" ;;
      esac
    fi
  done < "$cfg"

  emit_storage_block "$type" "$id" "$path" "$content" "$content_dirs" "$vgname" "$thinpool" "$disable" "$nodes_list"
}

# -----------------------------------------------------------------------------
# Audit: LVM / ZFS
# -----------------------------------------------------------------------------
is_protected_lv() {
  local lv="$1"
  local protected="$2"
  local p
  local arr=()
  read -r -a arr <<< "$protected"
  for p in "${arr[@]}"; do
    [[ -n "$p" && "$lv" == "$p" ]] && return 0
  done
  return 1
}

list_lvs_to_remove() {
  local storage_id="$1"
  local vg="$2"
  local thinpool="$3"
  local protected="$LVM_PROTECTED_DEFAULT $thinpool"
  local lv
  local to_remove=()

  while IFS= read -r lv; do
    lv="$(trim "$lv")"
    [[ -z "$lv" ]] && continue

    if [[ "$lv" == *"-snap-"* || "$lv" == *_tmeta* || "$lv" == *_tdata* ]]; then
      continue
    fi
    is_protected_lv "$lv" "$protected" && continue

    if [[ "$lv" == vm-* || "$lv" == base-* ]]; then
      to_remove+=("$lv")
    elif [[ -n "$LVM_WIPE_EXTRA_PATTERN" && "$LVM_WIPE_EXTRA_PATTERN" != "*" ]]; then
      # shellcheck disable=SC2053
      [[ "$lv" == ${LVM_WIPE_EXTRA_PATTERN} ]] && to_remove+=("$lv")
    fi
  done < <(lvs --noheadings -o lv_name "$vg" 2>/dev/null || true)

  if [[ ${#to_remove[@]} -gt 0 ]]; then
    local joined
    joined="$(printf "%s$SEP" "${to_remove[@]}")"
    joined="${joined%"$SEP"}"
    WIPE_LVM_ENTRIES+=("${storage_id}${SEP}${vg}${SEP}${joined}")
  fi
}

audit_lvm_lvs() {
  local entry storage_id vg thinpool
  for entry in "${WIPE_LVM_VGS[@]}"; do
    [[ -z "$entry" ]] && continue
    split_sep "$entry"; storage_id="$PIPE_LEFT"; entry="$PIPE_RIGHT"
    split_sep "$entry"; vg="$PIPE_LEFT"; thinpool="$PIPE_RIGHT"
    list_lvs_to_remove "$storage_id" "$vg" "$thinpool"
  done
}

list_zfs_datasets_to_remove() {
  local storage_id="$1"
  local pool="$2"
  local ds ds_name
  local to_remove=()

  while IFS= read -r ds; do
    [[ -z "$ds" ]] && continue
    ds_name="${ds##*/}"
    if [[ "$ds_name" == vm-* || "$ds_name" == subvol-* ]]; then
      to_remove+=("$ds")
    fi
  done < <(zfs list -H -o name -r "$pool" 2>/dev/null || true)

  if [[ ${#to_remove[@]} -gt 0 ]]; then
    local joined
    joined="$(printf "%s$SEP" "${to_remove[@]}")"
    joined="${joined%"$SEP"}"
    WIPE_ZFS_ENTRIES+=("${storage_id}${SEP}${pool}${SEP}${joined}")
  fi
}

audit_zfs_datasets() {
  local entry storage_id pool
  for entry in "${WIPE_ZFS_POOLS[@]}"; do
    [[ -z "$entry" ]] && continue
    split_sep "$entry"; storage_id="$PIPE_LEFT"; pool="$PIPE_RIGHT"
    list_zfs_datasets_to_remove "$storage_id" "$pool"
  done
}

# -----------------------------------------------------------------------------
# Audit: third-party, ceph, ssh keys, firewall
# -----------------------------------------------------------------------------
build_package_origins_cache() {
  local pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && return 0

  unset PACKAGE_ORIGINS_CACHE
  declare -gA PACKAGE_ORIGINS_CACHE

  local chunk_size=500
  local i line pkg origin uri_host in_installed_block

  for ((i=0; i<${#pkgs[@]}; i+=chunk_size)); do
    local chunk=("${pkgs[@]:i:chunk_size}")
    pkg=""
    origin=""
    uri_host=""
    in_installed_block=0

    while IFS= read -r line; do
      if [[ "$line" =~ ^([^[:space:]]+):$ ]]; then
        if [[ -n "$pkg" ]]; then
          PACKAGE_ORIGINS_CACHE["$pkg"]="${origin:-uri:${uri_host}}"
        fi
        pkg="${BASH_REMATCH[1]}"
        origin=""
        uri_host=""
        in_installed_block=0
        continue
      fi

      if [[ "$line" =~ ^[[:space:]]*\*\*\* ]]; then
        in_installed_block=1
        continue
      fi

      if [[ "$in_installed_block" -eq 1 ]]; then
        if [[ "$line" =~ release[[:space:]]+o=([^,]+) ]]; then
          origin="${BASH_REMATCH[1]}"
          in_installed_block=0
        elif [[ -z "$uri_host" && "$line" =~ https?://([^/:]+) ]]; then
          uri_host="${BASH_REMATCH[1]}"
        fi
        if [[ "$line" =~ ^[[:space:]]*[0-9]+[.-][0-9] ]]; then
          in_installed_block=0
        fi
      fi
    done < <(apt-cache policy "${chunk[@]}" 2>/dev/null)

    if [[ -n "$pkg" ]]; then
      PACKAGE_ORIGINS_CACHE["$pkg"]="${origin:-uri:${uri_host}}"
    fi
  done
}

audit_third_party_by_origin() {
  THIRD_PARTY_PACKAGES=()
  THIRD_PARTY_WITH_ORIGIN=()

  local vanilla_origins_re="$VANILLA_ORIGINS"
  [[ "$VANILLA_INCLUDE_CEPH" == "1" ]] && vanilla_origins_re="$vanilla_origins_re Ceph"
  vanilla_origins_re="${vanilla_origins_re// /|}"
  vanilla_origins_re="$(printf "%s" "$vanilla_origins_re" | sed 's/[.*+?\[\]()^$\\{}]/\\&/g')"

  local vanilla_uri_patterns="$VANILLA_URI_PATTERNS"
  [[ "$VANILLA_INCLUDE_CEPH" == "1" ]] && vanilla_uri_patterns="$vanilla_uri_patterns ceph.com"

  local all_installed=()
  local pkg
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && all_installed+=("$pkg")
  done < <(dpkg-query -f '${binary:Package}\n' -W 2>/dev/null)

  log_info "Collecting package origin metadata..."
  build_package_origins_cache "${all_installed[@]}"

  local result host is_vanilla pat_arr=() pat
  for pkg in "${all_installed[@]}"; do
    result="${PACKAGE_ORIGINS_CACHE["$pkg"]:-}"

    if [[ -z "$result" ]]; then
      THIRD_PARTY_PACKAGES+=("$pkg")
      THIRD_PARTY_WITH_ORIGIN+=("unknown${SEP}$pkg")
      continue
    fi

    if [[ "$result" == uri:* ]]; then
      host="${result#uri:}"
      is_vanilla=0
      IFS=' ' read -r -a pat_arr <<< "$vanilla_uri_patterns"
      for pat in "${pat_arr[@]}"; do
        [[ -z "$pat" ]] && continue
        if [[ "$host" == *"$pat"* ]]; then
          is_vanilla=1
          break
        fi
      done
      if [[ "$is_vanilla" -eq 0 ]]; then
        THIRD_PARTY_PACKAGES+=("$pkg")
        THIRD_PARTY_WITH_ORIGIN+=("${host}${SEP}${pkg}")
      fi
      continue
    fi

    if ! printf "%s" "$result" | grep -qE "^(${vanilla_origins_re})$"; then
      THIRD_PARTY_PACKAGES+=("$pkg")
      THIRD_PARTY_WITH_ORIGIN+=("${result}${SEP}${pkg}")
    fi
  done
}

audit_third_party() {
  PURGE_SERVICES=()
  PURGE_PACKAGES=()
  PURGE_DIRS=()

  local pkg
  for pkg in "${CROWDSEC_PACKAGES[@]}"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
      PURGE_PACKAGES+=("$pkg")
    fi
  done

  if [[ ${#PURGE_PACKAGES[@]} -gt 0 ]]; then
    PURGE_SERVICES=("${CROWDSEC_SERVICES[@]}")
    PURGE_DIRS=("${CROWDSEC_DIRS[@]}")
    PURGE_DIRS+=(/etc/apt/sources.list.d/crowdsec*.list)
    PURGE_DIRS+=(/etc/apt/keyrings/crowdsec*.asc)
  fi

  if $PURGE_ALL_THIRD_PARTY && [[ ${#THIRD_PARTY_PACKAGES[@]} -gt 0 ]]; then
    local p
    for p in "${THIRD_PARTY_PACKAGES[@]}"; do
      PURGE_PACKAGES+=("$p")
    done
  fi
}

audit_ceph() {
  if [[ -d /etc/ceph || -d /var/lib/ceph ]]; then
    CEPH_FOUND=true
  else
    CEPH_FOUND=false
  fi
}

audit_ssh_keys() {
  local auth_keys="/root/.ssh/authorized_keys"
  if [[ -f "$auth_keys" ]] && grep -qE "root@|pve" "$auth_keys"; then
    SSH_KEYS_FOUND=true
  else
    SSH_KEYS_FOUND=false
  fi
}

audit_firewall() {
  if command -v nft >/dev/null 2>&1 && nft list tables >/dev/null 2>&1; then
    FIREWALL_STACK="nftables"
  elif command -v iptables >/dev/null 2>&1 && iptables -L >/dev/null 2>&1; then
    FIREWALL_STACK="iptables"
  else
    FIREWALL_STACK="unknown"
  fi
}

# -----------------------------------------------------------------------------
# Execute phases
# -----------------------------------------------------------------------------
execute_wipe_dirs() {
  local entry storage_id basepath subdirs base_canon
  local sub_arr=()
  local sub dir dir_canon

  for entry in "${WIPE_DIR_ENTRIES[@]}"; do
    [[ -z "$entry" ]] && continue

    split_sep "$entry"; storage_id="$PIPE_LEFT"; entry="$PIPE_RIGHT"
    split_sep "$entry"; basepath="$PIPE_LEFT"; subdirs="$PIPE_RIGHT"

    base_canon="$(safe_realpath "$basepath")"
    [[ -z "$base_canon" ]] && continue

    IFS="$SEP" read -r -a sub_arr <<< "$subdirs"
    for sub in "${sub_arr[@]}"; do
      sub="$(trim "$sub")"
      [[ -z "$sub" ]] && continue
      is_safe_subdir "$sub" || continue

      dir="${basepath}/${sub}"
      [[ -d "$dir" ]] || continue

      dir_canon="$(safe_realpath "$dir")"
      [[ -z "$dir_canon" ]] && continue
      [[ "$dir_canon" != "$base_canon" && "$dir_canon" != "$base_canon"/* ]] && continue

      if $DRY_RUN; then
        log_dry "rm -rf ${dir}/* (storage: ${storage_id})"
      else
        color_red
        log_info "Wiping directory contents: ${dir} (storage: ${storage_id})"
        color_reset

        local old_nullglob old_dotglob
        old_nullglob="$(shopt -p nullglob || true)"
        old_dotglob="$(shopt -p dotglob || true)"
        shopt -s nullglob dotglob

        local files=("${dir}"/*)

        eval "$old_nullglob"
        eval "$old_dotglob"

        if [[ ${#files[@]} -eq 0 ]]; then
          log_info "Directory already empty: $dir"
          continue
        fi

        local f
        for f in "${files[@]}"; do
          if [[ -L "$f" ]]; then
            rm -f "$f" || ((FAILURE_COUNT+=1))
          else
            rm -rf --one-file-system "$f" || ((FAILURE_COUNT+=1))
          fi
        done
      fi
    done
  done
}

execute_wipe_lvm() {
  local entry storage_id vg lvs
  local lv_arr=()
  local lv

  for entry in "${WIPE_LVM_ENTRIES[@]}"; do
    [[ -z "$entry" ]] && continue
    split_sep "$entry"; storage_id="$PIPE_LEFT"; entry="$PIPE_RIGHT"
    split_sep "$entry"; vg="$PIPE_LEFT"; lvs="$PIPE_RIGHT"

    IFS="$SEP" read -r -a lv_arr <<< "$lvs"
    for lv in "${lv_arr[@]}"; do
      lv="$(trim "$lv")"
      [[ -z "$lv" ]] && continue
      run_or_dry_destructive "lvremove -y ${vg}/${lv}" "Removing LVM volume ${vg}/${lv} (storage: ${storage_id})" lvremove -y "${vg}/${lv}" || true
    done
  done
}

execute_wipe_zfs() {
  local entry storage_id pool datasets
  local ds_arr=()
  local ds

  for entry in "${WIPE_ZFS_ENTRIES[@]}"; do
    [[ -z "$entry" ]] && continue
    split_sep "$entry"; storage_id="$PIPE_LEFT"; entry="$PIPE_RIGHT"
    split_sep "$entry"; pool="$PIPE_LEFT"; datasets="$PIPE_RIGHT"

    IFS="$SEP" read -r -a ds_arr <<< "$datasets"
    for ds in "${ds_arr[@]}"; do
      ds="$(trim "$ds")"
      [[ -z "$ds" ]] && continue
      run_or_dry_destructive "zfs destroy -rf $ds" "Removing ZFS dataset $ds (storage: $storage_id)" zfs destroy -rf "$ds" || true
    done
  done
}

execute_purge_third_party() {
  local s d base pattern f

  for s in "${PURGE_SERVICES[@]}"; do
    [[ -z "$s" ]] && continue
    run_or_dry_destructive "systemctl stop --timeout=10s $s" "Stopping service $s" systemctl stop --timeout=10s "$s" 2>/dev/null || true
  done

  if [[ ${#PURGE_PACKAGES[@]} -gt 0 ]]; then
    run_or_dry_destructive "apt-get purge --auto-remove -y ..." "Purging third-party packages" apt-get purge --auto-remove -y "${PURGE_PACKAGES[@]}" || true
  fi

  for d in "${PURGE_DIRS[@]}"; do
    [[ -z "$d" ]] && continue
    if [[ "$d" == *'*'* ]]; then
      base="$(dirname "$d")"
      pattern="$(basename "$d")"
      [[ -d "$base" ]] || continue
      while IFS= read -r -d '' f; do
        run_or_dry_destructive "rm -rf $f" "Removing $f" rm -rf "$f" || true
      done < <(find "$base" -maxdepth 1 -name "$pattern" -print0 2>/dev/null)
    else
      [[ -e "$d" ]] && run_or_dry_destructive "rm -rf $d" "Removing $d" rm -rf "$d" || true
    fi
  done

  if ! $DRY_RUN && [[ ${#PURGE_PACKAGES[@]} -gt 0 ]]; then
    if command -v fuser >/dev/null 2>&1 && fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock >/dev/null 2>&1; then
      log_warn "APT lock currently held, skipping apt-get update/clean/autoremove"
    else
      log_info "Refreshing APT metadata/cache after purge"
      apt-get update || ((FAILURE_COUNT+=1))
      apt-get clean || ((FAILURE_COUNT+=1))
      apt-get autoremove -y || ((FAILURE_COUNT+=1))
      rm -rf /var/lib/apt/lists/* || ((FAILURE_COUNT+=1))
    fi
  fi
}

execute_reset_ceph() {
  local d
  for d in /etc/ceph /var/lib/ceph; do
    [[ -d "$d" ]] && run_or_dry_destructive "rm -rf $d" "Removing Ceph directory $d" rm -rf "$d" || true
  done
}

execute_reset_ssh_keys() {
  local auth_keys="/root/.ssh/authorized_keys"
  [[ -f "$auth_keys" ]] || return 0
  if $DRY_RUN; then
    log_dry "Strip Proxmox-specific keys from $auth_keys"
  else
    log_info "Removing Proxmox cluster keys from $auth_keys"
    sed -i '/root@\|pve/d' "$auth_keys" || ((FAILURE_COUNT+=1))
  fi
}

execute_reset_sdn() {
  local sdn_dir="${PVE_ETC}/sdn"
  remove_matching_glob "$sdn_dir" "*.cfg" "Remove SDN config"
  remove_file_if_exists "${sdn_dir}/.running-config" "Remove SDN runtime config"
}

execute_reset_mappings() {
  local map_dir="${PVE_ETC}/mapping"
  local d
  [[ -d "$map_dir" ]] || return 0

  while IFS= read -r -d '' d; do
    remove_matching_glob "$d" "*.cfg" "Remove resource mapping"
  done < <(find "$map_dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
}

execute_reset_pve_config() {
  local node_name
  node_name="$(hostname -s 2>/dev/null || echo "localhost")"
  if [[ ! "$node_name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    log_error "Invalid hostname for PVE node path: $node_name"
    return 1
  fi

  local base="${PVE_ETC}/nodes/${node_name}"
  execute_reset_sdn
  execute_reset_mappings

  remove_matching_glob "${base}/qemu-server" "*.conf" "Remove VM config"
  remove_matching_glob "${base}/lxc" "*.conf" "Remove CT config"

  clear_cfg_if_exists "${PVE_ETC}/jobs.cfg" "Reset backup jobs (jobs.cfg)"
  clear_cfg_if_exists "${PVE_ETC}/notification.cfg" "Reset notification config"
  clear_cfg_if_exists "${PVE_ETC}/metric-servers.cfg" "Reset metric servers config"

  local host_fw="${PVE_ETC}/firewall/nodes/${node_name}/host.fw"
  [[ -f "$host_fw" ]] && run_or_dry_write "Reset $host_fw" "Reset host firewall config" "$host_fw" '[OPTIONS]\n\n[RULES]\n\n'

  local cluster_fw="${PVE_ETC}/firewall/cluster.fw"
  [[ -f "$cluster_fw" ]] && run_or_dry_write "Reset $cluster_fw" "Reset cluster firewall config" "$cluster_fw" '[OPTIONS]\n\nenable: 0\n\n[RULES]\n\n'

  clear_cfg_if_exists "${PVE_ETC}/ha/resources.cfg" "Reset HA resources"
  clear_cfg_if_exists "${PVE_ETC}/ha/rules.cfg" "Reset HA rules"
  clear_cfg_if_exists "${PVE_ETC}/vzdump.conf" "Reset backup defaults (vzdump.conf)"
  clear_cfg_if_exists "${PVE_ETC}/pve-ssh-known_hosts" "Clear pve-ssh-known_hosts"

  wipe_dir_contents "${base}/priv" "Wipe node private directory"

  local pve_manager_lib="/var/lib/pve-manager"
  remove_file_if_exists "${pve_manager_lib}/pkgversions" "Clear manager status file pkgversions"
  remove_file_if_exists "${pve_manager_lib}/node_task_history" "Clear manager status file node_task_history"

  wipe_dir_contents "/var/log/pve/tasks" "Wipe task logs"

  local fw_cfg
  for fw_cfg in alias.cfg groups.cfg ipset.cfg; do
    clear_cfg_if_exists "${PVE_ETC}/firewall/${fw_cfg}" "Reset firewall definition $fw_cfg"
  done
}

execute_reset_users_datacenter() {
  local user_cfg_minimal="user:root@pam:1:0:::::\nacl:1:/:root@pam:Administrator:\n"
  run_or_dry_write "Write minimal user.cfg" "Reset users/ACL to root@pam only" "${PVE_ETC}/user.cfg" "$user_cfg_minimal"

  remove_file_if_exists "${PVE_ETC}/priv/token.cfg" "Remove API tokens"
  remove_file_if_exists "${PVE_ETC}/priv/tfa.cfg" "Remove 2FA config"
  wipe_dir_contents "${PVE_ETC}/priv/storage" "Remove storage secrets"
  remove_file_if_exists "${PVE_ETC}/priv/notifications.cfg" "Remove notification secrets"
  clear_cfg_if_exists "${PVE_ETC}/priv/shadow.cfg" "Clear password hashes"

  run_or_dry_write "Write minimal datacenter.cfg" "Reset datacenter.cfg to minimal" "${PVE_ETC}/datacenter.cfg" "# PVE datacenter - minimal\n\n"

  clear_cfg_if_exists "${PVE_ETC}/domains.cfg" "Remove authentication realms"
  clear_cfg_if_exists "${PVE_ETC}/pools.cfg" "Remove resource pools"
  wipe_dir_contents "${PVE_ETC}/acme" "Wipe ACME accounts/certificates"

  local f
  for f in /root/.bash_history /root/.ssh/known_hosts /var/mail/root /var/spool/mail/root; do
    remove_file_if_exists "$f" "Clean root hygiene artifact $f"
  done
}

execute_backup_pve_config() {
  local backup_file
  backup_file="/root/pve-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  run_or_dry "Backup /etc/pve -> $backup_file" "Creating /etc/pve backup at $backup_file" tar czf "$backup_file" /etc/pve
}

execute_reset_storage_cfg() {
  local cfg="$STORAGE_CFG"
  case "$cfg" in
    /etc/pve|/etc/pve/*) ;;
    *)
      log_error "Refusing to overwrite storage.cfg outside /etc/pve: $cfg"
      ((FAILURE_COUNT+=1))
      return 1
      ;;
  esac

  local vanilla_cfg
  vanilla_cfg="dir: local\n\tpath /var/lib/vz\n\tcontent iso,vztmpl,backup\n\nlvmthin: local-lvm\n\tthinpool data\n\tvgname pve\n\tcontent rootdir,images\n"
  run_or_dry_write "Overwrite $cfg with vanilla default" "Reset storage.cfg to vanilla default" "$cfg" "$vanilla_cfg"
}

maybe_sync() {
  if ! $NO_SYNC && ! $DRY_RUN; then
    sync || ((FAILURE_COUNT+=1))
  fi
}

run_execution_phases() {
  ensure_safety_guards

  log_info "Starting storage wipe phase (dir)"
  execute_wipe_dirs
  DIRS_WIPED=$((DIRS_WIPED + ${#WIPE_DIR_ENTRIES[@]}))
  maybe_sync

  log_info "Starting storage wipe phase (LVM)"
  execute_wipe_lvm
  local e
  for e in "${WIPE_LVM_ENTRIES[@]}"; do
    [[ -z "$e" ]] && continue
    LVS_REMOVED=$((LVS_REMOVED + $(printf "%s" "$e" | tr -cd "$SEP" | wc -c)))
  done
  maybe_sync

  log_info "Starting storage wipe phase (ZFS)"
  execute_wipe_zfs
  for e in "${WIPE_ZFS_ENTRIES[@]}"; do
    [[ -z "$e" ]] && continue
    ZFS_REMOVED=$((ZFS_REMOVED + $(printf "%s" "$e" | tr -cd "$SEP" | wc -c)))
  done
  maybe_sync

  if [[ "$RESET_PVE_CONFIG" == "true" || "$RESET_USERS_DATACENTER" == "true" || "$RESET_STORAGE_CFG" == "true" ]]; then
    if ! check_cluster_quorum; then
      log_warn "Skipping config reset operations due to missing quorum"
      RESET_PVE_CONFIG=false
      RESET_USERS_DATACENTER=false
      RESET_STORAGE_CFG=false
    fi
  fi

  if [[ "$BACKUP_CONFIG" == "true" && ( "$RESET_PVE_CONFIG" == "true" || "$RESET_USERS_DATACENTER" == "true" || "$RESET_STORAGE_CFG" == "true" ) ]]; then
    execute_backup_pve_config
  fi

  if $PURGE_ALL_THIRD_PARTY && [[ ${#PURGE_PACKAGES[@]} -gt 0 ]]; then
    if ! confirm_action "Purge all ${#PURGE_PACKAGES[@]} detected third-party packages?"; then
      log_warn "Skipped purging all third-party packages"
      PURGE_PACKAGES=()
      PURGE_SERVICES=()
      PURGE_DIRS=()
    fi
  fi

  log_info "Running third-party cleanup"
  execute_purge_third_party

  if $RESET_PVE_CONFIG; then
    log_info "Resetting PVE config artifacts"
    execute_reset_pve_config || true
  fi

  if [[ "$CEPH_FOUND" == "true" ]]; then
    if confirm_action "Remove Ceph configuration/data (/etc/ceph, /var/lib/ceph)?"; then
      execute_reset_ceph
    fi
  fi

  if [[ "$SSH_KEYS_FOUND" == "true" ]]; then
    if confirm_action "Remove Proxmox cluster keys from authorized_keys?"; then
      execute_reset_ssh_keys
    fi
  fi

  if $RESET_USERS_DATACENTER; then
    if confirm_action "Reset users/ACL/datacenter to root@pam-only baseline?"; then
      execute_reset_users_datacenter
    else
      log_warn "Skipped --reset-users-datacenter"
    fi
  fi

  if $RESET_STORAGE_CFG; then
    if confirm_action "Overwrite storage.cfg with vanilla defaults?"; then
      execute_reset_storage_cfg || true
    else
      log_warn "Skipped --reset-storage-cfg"
    fi
  fi
}

# -----------------------------------------------------------------------------
# Reporting
# -----------------------------------------------------------------------------
print_preflight_panel() {
  printf "\n"
  printf "========== Preflight =========="
  printf "\nMode: %s\n" "$EXEC_MODE"
  printf "Version: %s\n" "$VERSION"
  printf "Storage cfg: %s\n" "$STORAGE_CFG"
  printf "Flags: dry-run=%s audit-only=%s plan=%s json=%s list-storage=%s no-sync=%s\n" \
    "$DRY_RUN" "$AUDIT_ONLY" "$PLAN_ONLY" "$JSON_OUTPUT" "$LIST_STORAGE" "$NO_SYNC"
  printf "Scope: include='%s' exclude='%s'\n" "${INCLUDE_STORAGE_CSV:-}" "${EXCLUDE_STORAGE_CSV:-}"
  printf "Reset flags: pve-config=%s users/datacenter=%s storage-cfg=%s backup-config=%s\n" \
    "$RESET_PVE_CONFIG" "$RESET_USERS_DATACENTER" "$RESET_STORAGE_CFG" "$BACKUP_CONFIG"
  printf "Detected storage IDs: %s\n" "$(printf "%s " "${STORAGE_IDS_DISCOVERED[@]}" | sed 's/[[:space:]]*$//')"
  printf "================================\n\n"
}

print_planned_actions() {
  printf "========== Planned Actions ==========\n\n"

  printf "Dir storages (%d)\n" "${#WIPE_DIR_ENTRIES[@]}"
  if [[ ${#WIPE_DIR_ENTRIES[@]} -gt 0 ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && printf "  %s\n" "$line"
    done < <(printf "%s\n" "${WIPE_DIR_ENTRIES[@]}" | tr "$SEP" '|' | sort)
  fi
  printf "\n"

  printf "LVM entries (%d)\n" "${#WIPE_LVM_ENTRIES[@]}"
  if [[ ${#WIPE_LVM_ENTRIES[@]} -gt 0 ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && printf "  %s\n" "$line"
    done < <(printf "%s\n" "${WIPE_LVM_ENTRIES[@]}" | tr "$SEP" '|' | sort)
  fi
  printf "\n"

  printf "ZFS entries (%d)\n" "${#WIPE_ZFS_ENTRIES[@]}"
  if [[ ${#WIPE_ZFS_ENTRIES[@]} -gt 0 ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && printf "  %s\n" "$line"
    done < <(printf "%s\n" "${WIPE_ZFS_ENTRIES[@]}" | tr "$SEP" '|' | sort)
  fi
  printf "\n"

  printf "Third-party packages detected: %d\n" "${#THIRD_PARTY_PACKAGES[@]}"
  printf "Purge targets: services=%d packages=%d dirs=%d\n" "${#PURGE_SERVICES[@]}" "${#PURGE_PACKAGES[@]}" "${#PURGE_DIRS[@]}"
  printf "Firewall stack: %s\n" "$FIREWALL_STACK"
  printf "Ceph artifacts: %s\n" "$CEPH_FOUND"
  printf "SSH cluster keys found: %s\n" "$SSH_KEYS_FOUND"
  printf "\n=====================================\n\n"
}

print_storage_ids() {
  local id
  for id in "${STORAGE_IDS_DISCOVERED[@]}"; do
    printf "%s\n" "$id"
  done
}

output_json() {
  printf '{'
  printf '"meta":{'
  printf '"version":"%s",' "$VERSION"
  printf '"timestamp":"%s",' "$(date -Iseconds)"
  printf '"hostname":"%s",' "$(hostname 2>/dev/null || echo unknown)"
  printf '"failure_count":%s,' "${FAILURE_COUNT:-0}"
  printf '"mode":"%s"' "$EXEC_MODE"
  printf '},'

  printf '"wipe_dir_entries":['
  json_array "${WIPE_DIR_ENTRIES[@]}"
  printf '],'

  printf '"wipe_lvm_entries":['
  json_array "${WIPE_LVM_ENTRIES[@]}"
  printf '],'

  printf '"wipe_zfs_entries":['
  json_array "${WIPE_ZFS_ENTRIES[@]}"
  printf '],'

  printf '"third_party_packages":['
  json_array "${THIRD_PARTY_PACKAGES[@]}"
  printf '],'

  printf '"third_party_with_origin":['
  json_array "${THIRD_PARTY_WITH_ORIGIN[@]}"
  printf '],'

  printf '"purge_services":['
  json_array "${PURGE_SERVICES[@]}"
  printf '],'

  printf '"purge_packages":['
  json_array "${PURGE_PACKAGES[@]}"
  printf '],'

  printf '"purge_dirs":['
  json_array "${PURGE_DIRS[@]}"
  printf '],'

  printf '"storage_ids":['
  json_array "${STORAGE_IDS_DISCOVERED[@]}"
  printf '],'

  printf '"firewall_stack":"%s",' "$(printf "%s" "$FIREWALL_STACK" | json_escape)"
  printf '"reset_pve_config":%s,' "$(bool_json "$RESET_PVE_CONFIG")"
  printf '"reset_users_datacenter":%s,' "$(bool_json "$RESET_USERS_DATACENTER")"
  printf '"reset_storage_cfg":%s,' "$(bool_json "$RESET_STORAGE_CFG")"
  printf '"no_sync":%s' "$(bool_json "$NO_SYNC")"

  printf '}\n'
}

print_final_summary() {
  local start_time="$1"
  local end_time elapsed
  end_time="$(date +%s)"
  elapsed=$((end_time - start_time))

  printf "\n========== Summary ==========\n"
  printf "Mode:                    %s\n" "$EXEC_MODE"
  printf "Dir storages processed:  %s\n" "$DIRS_WIPED"
  printf "LVM volumes targeted:    %s\n" "$LVS_REMOVED"
  printf "ZFS datasets targeted:   %s\n" "$ZFS_REMOVED"
  printf "Config files changed:    %s\n" "$CONFIGS_CLEARED"
  printf "Failures:                %s\n" "$FAILURE_COUNT"
  printf "Elapsed:                 %ss\n" "$elapsed"
  printf "Exit state:              %s\n" "$([[ $FAILURE_COUNT -eq 0 ]] && echo success || echo partial-failure)"
  printf "=============================\n\n"
}

run_audit_pipeline() {
  log_info "Starting audit pipeline"

  audit_storage_cfg "$STORAGE_CFG"
  collect_storage_ids
  apply_storage_scope_filters

  check_dependencies

  audit_lvm_lvs
  audit_zfs_datasets
  audit_third_party_by_origin
  audit_third_party
  audit_ceph
  audit_ssh_keys
  audit_firewall

  log_success "Audit pipeline finished"
}

main() {
  parse_args "$@"
  check_root_requirements
  validate_config_paths
  setup_runtime

  local start_time
  start_time="$(date +%s)"

  run_audit_pipeline

  if [[ "$EXEC_MODE" == "list-storage" ]]; then
    print_storage_ids
    exit "$EXIT_OK"
  fi

  if [[ "$EXEC_MODE" == "json" ]]; then
    output_json
    exit "$EXIT_OK"
  fi

  print_preflight_panel
  print_planned_actions

  if [[ "$EXEC_MODE" == "plan" || "$EXEC_MODE" == "audit" ]]; then
    exit "$EXIT_OK"
  fi

  if [[ "$EXEC_MODE" == "dry-run" ]]; then
    log_info "Executing dry-run"
    run_execution_phases
    print_final_summary "$start_time"
    if [[ $FAILURE_COUNT -gt 0 ]]; then
      exit "$EXIT_RUNTIME"
    fi
    exit "$EXIT_OK"
  fi

  # execute mode
  if ! confirm_action "Proceed with soft reset execution?"; then
    log_warn "Aborted by user"
    exit "$EXIT_OK"
  fi

  run_execution_phases
  print_final_summary "$start_time"

  if [[ $FAILURE_COUNT -gt 0 ]]; then
    log_error "$FAILURE_COUNT action(s) failed. Check log: $LOG_FILE"
    exit "$EXIT_RUNTIME"
  fi

  log_success "Soft reset completed"
  exit "$EXIT_OK"
}

main "$@"
