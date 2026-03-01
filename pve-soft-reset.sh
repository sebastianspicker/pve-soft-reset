#!/usr/bin/env bash
#
# pve-soft-reset.sh - audit-based soft reset for Proxmox VE hosts
#
# Stable v1.x track (non-breaking CLI compatibility + additive improvements)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Load constants and option defaults
# -----------------------------------------------------------------------------
# shellcheck source=lib/constants.bash
source "$SCRIPT_DIR/lib/constants.bash"

# -----------------------------------------------------------------------------
# Runtime state (must be visible to all sourced libs)
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
WARNINGS=()

# -----------------------------------------------------------------------------
# Load libs (order matters: helpers need state; storage_scope needs helpers; etc.)
# -----------------------------------------------------------------------------
# shellcheck source=lib/helpers.bash
source "$SCRIPT_DIR/lib/helpers.bash"
# shellcheck source=lib/storage_scope.bash
source "$SCRIPT_DIR/lib/storage_scope.bash"
# shellcheck source=lib/cli_preflight.bash
source "$SCRIPT_DIR/lib/cli_preflight.bash"
# shellcheck source=lib/audit.bash
source "$SCRIPT_DIR/lib/audit.bash"
# shellcheck source=lib/execute.bash
source "$SCRIPT_DIR/lib/execute.bash"
# shellcheck source=lib/reporting.bash
source "$SCRIPT_DIR/lib/reporting.bash"

# -----------------------------------------------------------------------------
# Audit pipeline and main
# -----------------------------------------------------------------------------
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
    if [[ -n "$REPORT_FILE" ]]; then
      append_summary_to_report_only "$start_time"
    fi
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
