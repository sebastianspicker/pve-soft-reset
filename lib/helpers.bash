# pve-soft-reset helpers: colors, logging, generic helpers (sourced after constants + runtime state)
# split_sep sets PIPE_LEFT/PIPE_RIGHT for callers; other vars used by main/libs.
# shellcheck disable=SC2034

# -----------------------------------------------------------------------------
# Colors & logging
# -----------------------------------------------------------------------------
_color_setaf() { if $USE_COLOR; then printf "%s" "$(tput setaf "$1" 2>/dev/null)"; fi; return 0; }
color_red()   { _color_setaf 1; }
color_green() { _color_setaf 2; }
color_yellow(){ _color_setaf 3; }
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
    if $JSON_OUTPUT || $LIST_STORAGE; then
      out_fd=2
    fi
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
add_warning() {
  local msg="$1"
  WARNINGS+=("$msg")
}
log_warn()    { add_warning "$*"; _log_line "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*" "WARN"; }
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
  ${c_opt}--report-file <path>${c_rst}         Write preflight/planned/summary report to file.
  ${c_opt}--no-sync${c_rst}                    Skip sync calls after wipe phases.
  ${c_opt}--no-color${c_rst}                   Disable ANSI colors.
  ${c_opt}--verbose${c_rst}                    Enable verbose output.
  ${c_opt}--quiet${c_rst}                      Minimal output (warnings/errors only).
  ${c_opt}--non-interactive${c_rst}            Fail if an interactive confirmation would be required.
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
  ${c_opt}--json-pretty${c_rst}                Pretty-print JSON output (requires --json).

Exit codes: 0 success, 1 runtime/partial failure, 2 usage error, 3 preflight/safety blocker.
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

for_each_sep_entry() {
  # shellcheck disable=SC2178
  local -n arr_ref=$1
  local callback="$2"
  local entry
  for entry in "${arr_ref[@]}"; do
    [[ -z "$entry" ]] && continue
    split_sep "$entry"
    "$callback" "$PIPE_LEFT" "$PIPE_RIGHT"
  done
}

resolve_node_name() {
  local node=""
  if [[ -L /etc/pve/local ]]; then
    node="$(readlink /etc/pve/local 2>/dev/null || true)"
    node="${node##*/}"
  fi
  [[ -z "$node" ]] && node="$(hostname -s 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "")"
  printf "%s" "$node"
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

# Output one allowed base path per line (trimmed, non-empty). Used by guards and path check.
get_allowed_dir_bases() {
  local allowed_arr=()
  local a
  IFS=':' read -r -a allowed_arr <<< "${ALLOWED_DIR_STORAGE_BASE:-}"
  for a in "${allowed_arr[@]}"; do
    a="$(trim "$a")"
    [[ -n "$a" ]] && printf "%s\n" "$a"
  done
}

is_local_dir_path_simple() {
  local path="$1"
  [[ -z "$path" ]] && return 1
  [[ -d "$path" ]] || return 1
  [[ "$path" == /mnt/pve/* ]] && return 1

  local canonical allowed allowed_canon
  canonical="$(safe_realpath "$path")"
  [[ -z "$canonical" ]] && return 1

  while IFS= read -r allowed; do
    allowed_canon="$(safe_realpath "$allowed")"
    [[ -z "$allowed_canon" ]] && allowed_canon="$allowed"
    if [[ "$canonical" == "$allowed_canon" || "$canonical" == "$allowed_canon"/* ]]; then
      return 0
    fi
  done < <(get_allowed_dir_bases)
  return 1
}

# Allowed output variable names for nameref (do not pass user-controlled names).
csv_to_array() {
  local csv="$1"
  local out_name="$2"
  local raw_arr=()
  local item
  case "$out_name" in
    arr|scope_ids) ;;
    *)
      printf "Internal error: csv_to_array out_name must be arr or scope_ids (got: %s)\n" "$out_name" >&2
      exit "$EXIT_RUNTIME"
      ;;
  esac
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

# destructive=true: style the log line in red (for destructive actions).
run_or_dry() {
  local dry_msg="$1"
  local exec_msg="$2"
  local destructive="${3:-false}"
  shift 3

  if $DRY_RUN; then
    log_dry "$dry_msg"
    return 0
  fi

  if $destructive; then
    color_red
    log_info "$exec_msg"
    color_reset
  else
    log_info "$exec_msg"
  fi

  if ! "$@"; then
    ((FAILURE_COUNT+=1))
    return 1
  fi
  return 0
}

_run_or_dry_preamble() {
  local dry_msg="$1"
  local exec_msg="$2"
  if $DRY_RUN; then
    log_dry "$dry_msg"
    return 0
  fi
  log_info "$exec_msg"
  return 1
}

run_or_dry_clear() {
  local dry_msg="$1"
  local exec_msg="$2"
  local file="$3"
  _run_or_dry_preamble "$dry_msg" "$exec_msg" && return 0
  if : > "$file"; then
    return 0
  fi
  ((FAILURE_COUNT+=1))
  return 1
}

run_or_dry_write() {
  local dry_msg="$1"
  local exec_msg="$2"
  local file="$3"
  local content="$4"
  _run_or_dry_preamble "$dry_msg" "$exec_msg" && return 0
  if printf "%b" "$content" > "$file"; then
    ((CONFIGS_CLEARED+=1))
    return 0
  fi
  ((FAILURE_COUNT+=1))
  return 1
}

clear_cfg_if_exists() {
  local file="$1"
  local label="$2"
  [[ -f "$file" ]] || return 0
  if run_or_dry_clear "Clear $file" "$label" "$file"; then
    if ! $DRY_RUN; then
      ((CONFIGS_CLEARED+=1))
    fi
  fi
}

remove_file_if_exists() {
  local file="$1"
  local label="$2"
  [[ -f "$file" ]] || return 0
  if run_or_dry "rm $file" "$label" false rm -f "$file"; then
    if ! $DRY_RUN; then
      ((CONFIGS_CLEARED+=1))
    fi
  fi
}

wipe_dir_contents() {
  local dir="$1"
  local label="$2"
  [[ -d "$dir" ]] || return 0
  run_or_dry "rm -rf $dir/*" "$label" false find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf --one-file-system {} +
}

remove_matching_glob() {
  local base="$1"
  local pattern="$2"
  local label_prefix="$3"
  local f

  [[ -d "$base" ]] || return 0
  while IFS= read -r -d '' f; do
    if run_or_dry "rm $f" "$label_prefix: $f" false rm -f "$f"; then
      if ! $DRY_RUN; then
        ((CONFIGS_CLEARED+=1))
      fi
    fi
  done < <(find "$base" -maxdepth 1 -name "$pattern" -print0 2>/dev/null)
}

confirm_action() {
  local prompt="$1"
  if ! $CONFIRM; then
    return 0
  fi
  if $NON_INTERACTIVE; then
    die_preflight "Non-interactive mode blocks confirmation prompts; rerun with --yes for unattended execution"
  fi

  local ans
  read -r -p "$prompt [y/N] " ans
  [[ "$ans" =~ ^[yY]([eE][sS])?$ ]]
}

bool_json() {
  [[ "${1:-}" == "true" ]] && printf "true" || printf "false"
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
