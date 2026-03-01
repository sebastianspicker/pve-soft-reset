# pve-soft-reset CLI and preflight (sourced after storage_scope)
# Options and state set here are used by main and other libs.
# shellcheck disable=SC2034

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
      --json-pretty) JSON_PRETTY=true ;;
      -y|--yes) CONFIRM=false ;;
      --non-interactive) NON_INTERACTIVE=true ;;

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
      --report-file)
        shift
        [[ $# -gt 0 ]] || die_usage "--report-file requires a path"
        REPORT_FILE="$1"
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
  if $JSON_PRETTY && ! $JSON_OUTPUT; then
    die_usage "--json-pretty requires --json"
  fi
  if [[ -n "$REPORT_FILE" ]] && { $JSON_OUTPUT || $LIST_STORAGE; }; then
    die_usage "--report-file cannot be used with --json or --list-storage"
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
  local allowed_bases allowed
  allowed_bases="$(get_allowed_dir_bases)"
  if [[ -z "${allowed_bases//[[:space:]]}" ]]; then
    die_preflight "ALLOWED_DIR_STORAGE_BASE must not be empty or whitespace-only"
  fi
  while IFS= read -r allowed; do
    case "$allowed" in
      ""|"/"|"/etc"|"/etc/"|"/root"|"/root/"|"/var"|"/var/"|"/usr"|"/usr/"|"/home"|"/home/"|"/opt"|"/opt/")
        die_preflight "ALLOWED_DIR_STORAGE_BASE contains blacklisted path: '$allowed'"
        ;;
    esac
  done <<< "$allowed_bases"
}

path_points_to_pve_cfg() {
  local candidate="$1"
  local candidate_abs="$candidate"
  local pve_canon
  local candidate_norm candidate_canon pve_norm

  pve_canon="$(safe_realpath "/etc/pve")"
  [[ -z "$pve_canon" ]] && pve_canon="/etc/pve"

  if [[ "$candidate_abs" != /* ]]; then
    candidate_abs="$(pwd -P)/$candidate_abs"
  fi

  candidate_norm="$(normalize_abs_path_lexical "$candidate_abs")"
  candidate_canon="$(safe_realpath "$candidate_abs")"
  [[ -z "$candidate_canon" ]] && candidate_canon="$candidate_norm"
  pve_norm="$(normalize_abs_path_lexical "$pve_canon")"
  [[ -z "$pve_norm" ]] && pve_norm="/etc/pve"

  case "$candidate_abs" in
    /etc/pve|/etc/pve/*|"$pve_canon"|"$pve_canon"/*)
      return 0
      ;;
    *)
      ;;
  esac

  case "$candidate_norm" in
    /etc/pve|/etc/pve/*|"$pve_norm"|"$pve_norm"/*)
      return 0
      ;;
    *)
      ;;
  esac

  case "$candidate_canon" in
    /etc/pve|/etc/pve/*|"$pve_canon"|"$pve_canon"/*|"$pve_norm"|"$pve_norm"/*)
      return 0
      ;;
    *)
      ;;
  esac
  return 1
}

normalize_abs_path_lexical() {
  local path="$1"
  local part out=""
  local -a parts=() stack=()

  [[ "$path" == /* ]] || { printf ""; return 0; }

  IFS='/' read -r -a parts <<< "$path"
  for part in "${parts[@]}"; do
    case "$part" in
      ""|".") continue ;;
      "..")
        if [[ ${#stack[@]} -gt 0 ]]; then
          unset "stack[$(( ${#stack[@]} - 1 ))]"
        fi
        ;;
      *)
        stack+=("$part")
        ;;
    esac
  done

  for part in "${stack[@]}"; do
    out="${out}/${part}"
  done
  [[ -z "$out" ]] && out="/"
  printf "%s" "$out"
}

validate_report_file_path() {
  [[ -z "$REPORT_FILE" ]] && return 0

  local report_canon
  report_canon="$(safe_realpath "$REPORT_FILE")"
  [[ -z "$report_canon" ]] && report_canon="$REPORT_FILE"

  if path_points_to_pve_cfg "$REPORT_FILE"; then
    die_preflight "Report file must not be under /etc/pve (would risk config corruption): $REPORT_FILE"
  fi
  if path_points_to_pve_cfg "$report_canon"; then
    die_preflight "Report file must not resolve under /etc/pve (would risk config corruption): $REPORT_FILE"
  fi

  local report_dir
  report_dir="$(dirname "$REPORT_FILE")"
  [[ -d "$report_dir" ]] || die_preflight "Report file directory does not exist: $report_dir"
  [[ -w "$report_dir" ]] || die_preflight "Report file directory is not writable: $report_dir"
  if path_points_to_pve_cfg "$report_dir"; then
    die_preflight "Report file directory must not point to /etc/pve: $report_dir"
  fi

  if [[ -e "$REPORT_FILE" && -d "$REPORT_FILE" ]]; then
    die_preflight "Report file must not be a directory: $REPORT_FILE"
  fi
  if [[ -L "$REPORT_FILE" ]]; then
    die_preflight "Report file must not be a symlink: $REPORT_FILE"
  fi
}

validate_log_file_path() {
  local log_canon
  log_canon="$(safe_realpath "$LOG_FILE")"
  [[ -z "$log_canon" ]] && log_canon="$LOG_FILE"

  # Refuse to log to a symlink to avoid appending to an unintended target.
  if [[ -L "$LOG_FILE" ]]; then
    die_preflight "Log file must not be a symlink: $LOG_FILE"
  fi

  # Refuse to log under /etc/pve to avoid corrupting or overwriting PVE config files.
  if path_points_to_pve_cfg "$LOG_FILE"; then
    die_preflight "Log file must not be under /etc/pve (would risk config corruption): $LOG_FILE"
  fi
  if path_points_to_pve_cfg "$log_canon"; then
    die_preflight "Log file must not resolve under /etc/pve (would risk config corruption): $LOG_FILE"
  fi

  if [[ -d "$LOG_FILE" ]]; then
    die_preflight "Log file must not be a directory: $LOG_FILE"
  fi

  local log_dir
  log_dir="$(dirname "$LOG_FILE")"
  if [[ -d "$log_dir" ]] && path_points_to_pve_cfg "$log_dir"; then
    die_preflight "Log file directory must not point to /etc/pve: $log_dir"
  fi
}

setup_runtime() {
  USE_COLOR=false
  [[ -t 1 ]] && USE_COLOR=true
  $NO_COLOR && USE_COLOR=false

  ENABLE_FILE_LOG=false
  if [[ $EUID -eq 0 && "$EXEC_MODE" != "plan" && "$EXEC_MODE" != "audit" && "$EXEC_MODE" != "json" && "$EXEC_MODE" != "list-storage" ]]; then
    ENABLE_FILE_LOG=true
  fi

  validate_report_file_path
  if [[ -n "$REPORT_FILE" ]]; then
    : > "$REPORT_FILE" || die_preflight "Unable to write report file: $REPORT_FILE"
  fi

  validate_log_file_path

  if $ENABLE_FILE_LOG; then
    if [[ ! -e "$LOG_FILE" ]]; then
      touch "$LOG_FILE" 2>/dev/null || true
      chmod 0600 "$LOG_FILE" 2>/dev/null || true
    else
      local size=0
      # GNU stat (Linux/Proxmox); BSD uses stat -f%z
      size="$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)"
      if [[ "$size" -gt 10485760 ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
        touch "$LOG_FILE" 2>/dev/null || true
        chmod 0600 "$LOG_FILE" 2>/dev/null || true
      fi
    fi
  fi

  if ! is_destructive_mode; then
    return 0
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
