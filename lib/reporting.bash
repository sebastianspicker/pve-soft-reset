# pve-soft-reset reporting (sourced after execute)

# -----------------------------------------------------------------------------
# Reporting helpers
# -----------------------------------------------------------------------------
_report_printf() {
  local fmt="$1"
  shift
  # shellcheck disable=SC2059
  printf "$fmt" "$@"
  if [[ -n "$REPORT_FILE" ]]; then
    # shellcheck disable=SC2059
    printf "$fmt" "$@" >> "$REPORT_FILE"
  fi
}

_report_file_printf() {
  [[ -n "$REPORT_FILE" ]] || return 0
  local fmt="$1"
  shift
  # shellcheck disable=SC2059
  printf "$fmt" "$@" >> "$REPORT_FILE"
}

json_array_pretty() {
  local indent="$1"
  local close_indent="$2"
  shift 2
  local first=1
  local item
  printf "["
  for item in "$@"; do
    [[ -z "$item" ]] && continue
    if [[ $first -eq 1 ]]; then
      first=0
    else
      printf ","
    fi
    printf "\n%s\"%s\"" "$indent" "$(printf "%s" "$item" | tr "$SEP" '|' | json_escape)"
  done
  if [[ $first -eq 1 ]]; then
    printf "]"
  else
    printf "\n%s]" "$close_indent"
  fi
}

# -----------------------------------------------------------------------------
# Reporting
# -----------------------------------------------------------------------------
print_preflight_panel() {
  _report_printf "\n"
  _report_printf "========== Preflight =========="
  _report_printf "\nMode: %s\n" "$EXEC_MODE"
  _report_printf "Version: %s\n" "$VERSION"
  _report_printf "Storage cfg: %s\n" "$STORAGE_CFG"
  _report_printf "Flags: dry-run=%s audit-only=%s plan=%s json=%s list-storage=%s no-sync=%s non-interactive=%s\n" \
    "$DRY_RUN" "$AUDIT_ONLY" "$PLAN_ONLY" "$JSON_OUTPUT" "$LIST_STORAGE" "$NO_SYNC" "$NON_INTERACTIVE"
  _report_printf "Scope: include='%s' exclude='%s'\n" "${INCLUDE_STORAGE_CSV:-}" "${EXCLUDE_STORAGE_CSV:-}"
  _report_printf "Reset flags: pve-config=%s users/datacenter=%s storage-cfg=%s backup-config=%s\n" \
    "$RESET_PVE_CONFIG" "$RESET_USERS_DATACENTER" "$RESET_STORAGE_CFG" "$BACKUP_CONFIG"
  _report_printf "Detected storage IDs: %s\n" "$(printf "%s " "${STORAGE_IDS_DISCOVERED[@]}" | sed 's/[[:space:]]*$//')"
  _report_printf "================================\n\n"
}

# Print a planned-actions section: title (count) and sorted lines with SEP replaced by |.
print_planned_section() {
  local title="$1"
  # shellcheck disable=SC2178
  local -n arr=$2
  _report_printf "%s (%d)\n" "$title" "${#arr[@]}"
  if [[ ${#arr[@]} -gt 0 ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && _report_printf "  %s\n" "$line"
    done < <(printf "%s\n" "${arr[@]}" | tr "$SEP" '|' | sort)
  fi
  _report_printf "\n"
}

print_planned_actions() {
  _report_printf "========== Planned Actions ==========\n\n"

  print_planned_section "Dir storages" WIPE_DIR_ENTRIES
  print_planned_section "LVM entries" WIPE_LVM_ENTRIES
  print_planned_section "ZFS entries" WIPE_ZFS_ENTRIES

  _report_printf "Third-party packages detected: %d\n" "${#THIRD_PARTY_PACKAGES[@]}"
  _report_printf "Purge targets: services=%d packages=%d dirs=%d\n" "${#PURGE_SERVICES[@]}" "${#PURGE_PACKAGES[@]}" "${#PURGE_DIRS[@]}"
  _report_printf "Firewall stack: %s\n" "$FIREWALL_STACK"
  _report_printf "Ceph artifacts: %s\n" "$CEPH_FOUND"
  _report_printf "SSH cluster keys found: %s\n" "$SSH_KEYS_FOUND"
  _report_printf "\n=====================================\n\n"
}

print_storage_ids() {
  local id
  for id in "${STORAGE_IDS_DISCOVERED[@]}"; do
    printf "%s\n" "$id"
  done
}

output_json_compact() {
  printf '{'
  printf '"meta":{'
  printf '"version":"%s",' "$VERSION"
  printf '"timestamp":"%s",' "$(date -Iseconds)"
  printf '"hostname":"%s",' "$(hostname 2>/dev/null || echo unknown)"
  printf '"failure_count":%s,' "${FAILURE_COUNT:-0}"
  printf '"mode":"%s",' "$EXEC_MODE"
  printf '"non_interactive":%s,' "$(bool_json "$NON_INTERACTIVE")"
  printf '"scope":{"include":"%s","exclude":"%s"}' \
    "$(printf "%s" "${INCLUDE_STORAGE_CSV:-}" | json_escape)" \
    "$(printf "%s" "${EXCLUDE_STORAGE_CSV:-}" | json_escape)"
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

  printf '"warnings":['
  json_array "${WARNINGS[@]}"
  printf '],'

  printf '"firewall_stack":"%s",' "$(printf "%s" "$FIREWALL_STACK" | json_escape)"
  printf '"reset_pve_config":%s,' "$(bool_json "$RESET_PVE_CONFIG")"
  printf '"reset_users_datacenter":%s,' "$(bool_json "$RESET_USERS_DATACENTER")"
  printf '"reset_storage_cfg":%s,' "$(bool_json "$RESET_STORAGE_CFG")"
  printf '"no_sync":%s' "$(bool_json "$NO_SYNC")"

  printf '}\n'
}

output_json_pretty() {
  printf "{\n"
  printf "  \"meta\": {\n"
  printf "    \"version\": \"%s\",\n" "$(printf "%s" "$VERSION" | json_escape)"
  printf "    \"timestamp\": \"%s\",\n" "$(date -Iseconds)"
  printf "    \"hostname\": \"%s\",\n" "$(hostname 2>/dev/null || echo unknown)"
  printf "    \"failure_count\": %s,\n" "${FAILURE_COUNT:-0}"
  printf "    \"mode\": \"%s\",\n" "$(printf "%s" "$EXEC_MODE" | json_escape)"
  printf "    \"non_interactive\": %s,\n" "$(bool_json "$NON_INTERACTIVE")"
  printf "    \"scope\": {\n"
  printf "      \"include\": \"%s\",\n" "$(printf "%s" "${INCLUDE_STORAGE_CSV:-}" | json_escape)"
  printf "      \"exclude\": \"%s\"\n" "$(printf "%s" "${EXCLUDE_STORAGE_CSV:-}" | json_escape)"
  printf "    }\n"
  printf "  },\n"

  printf "  \"wipe_dir_entries\": "
  json_array_pretty "    " "  " "${WIPE_DIR_ENTRIES[@]}"
  printf ",\n"

  printf "  \"wipe_lvm_entries\": "
  json_array_pretty "    " "  " "${WIPE_LVM_ENTRIES[@]}"
  printf ",\n"

  printf "  \"wipe_zfs_entries\": "
  json_array_pretty "    " "  " "${WIPE_ZFS_ENTRIES[@]}"
  printf ",\n"

  printf "  \"third_party_packages\": "
  json_array_pretty "    " "  " "${THIRD_PARTY_PACKAGES[@]}"
  printf ",\n"

  printf "  \"third_party_with_origin\": "
  json_array_pretty "    " "  " "${THIRD_PARTY_WITH_ORIGIN[@]}"
  printf ",\n"

  printf "  \"purge_services\": "
  json_array_pretty "    " "  " "${PURGE_SERVICES[@]}"
  printf ",\n"

  printf "  \"purge_packages\": "
  json_array_pretty "    " "  " "${PURGE_PACKAGES[@]}"
  printf ",\n"

  printf "  \"purge_dirs\": "
  json_array_pretty "    " "  " "${PURGE_DIRS[@]}"
  printf ",\n"

  printf "  \"storage_ids\": "
  json_array_pretty "    " "  " "${STORAGE_IDS_DISCOVERED[@]}"
  printf ",\n"

  printf "  \"warnings\": "
  json_array_pretty "    " "  " "${WARNINGS[@]}"
  printf ",\n"

  printf "  \"firewall_stack\": \"%s\",\n" "$(printf "%s" "$FIREWALL_STACK" | json_escape)"
  printf "  \"reset_pve_config\": %s,\n" "$(bool_json "$RESET_PVE_CONFIG")"
  printf "  \"reset_users_datacenter\": %s,\n" "$(bool_json "$RESET_USERS_DATACENTER")"
  printf "  \"reset_storage_cfg\": %s,\n" "$(bool_json "$RESET_STORAGE_CFG")"
  printf "  \"no_sync\": %s\n" "$(bool_json "$NO_SYNC")"
  printf "}\n"
}

output_json() {
  if $JSON_PRETTY; then
    output_json_pretty
  else
    output_json_compact
  fi
}

emit_summary_with_sink() {
  local sink_fn="$1"
  local start_time="$2"
  local end_time elapsed
  end_time="$(date +%s)"
  elapsed=$((end_time - start_time))

  "$sink_fn" "\n========== Summary ==========\n"
  "$sink_fn" "Mode:                    %s\n" "$EXEC_MODE"
  "$sink_fn" "Dir storages processed:  %s\n" "$DIRS_WIPED"
  "$sink_fn" "LVM volumes targeted:    %s\n" "$LVS_REMOVED"
  "$sink_fn" "ZFS datasets targeted:   %s\n" "$ZFS_REMOVED"
  "$sink_fn" "Config files changed:    %s\n" "$CONFIGS_CLEARED"
  "$sink_fn" "Failures:                %s\n" "$FAILURE_COUNT"
  "$sink_fn" "Elapsed:                 %ss\n" "$elapsed"
  "$sink_fn" "Exit state:              %s\n" "$([[ $FAILURE_COUNT -eq 0 ]] && echo success || echo partial-failure)"
  "$sink_fn" "=============================\n\n"
}

append_summary_to_report_only() {
  local start_time="$1"
  emit_summary_with_sink "_report_file_printf" "$start_time"
}

print_final_summary() {
  local start_time="$1"
  emit_summary_with_sink "_report_printf" "$start_time"
}
