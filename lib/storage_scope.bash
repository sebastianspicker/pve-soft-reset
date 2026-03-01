# pve-soft-reset storage scope: collect IDs, filter by include/exclude (sourced after helpers)
# WIPE_* and STORAGE_IDS_DISCOVERED are used by main and other libs.
# shellcheck disable=SC2034

# Append first field (storage id) of each entry in named array to _COLLECT_IDS_TMP.
_collect_ids_from_array() {
  for_each_sep_entry "$1" "_collect_ids_callback"
}

_collect_ids_callback() {
  _COLLECT_IDS_TMP+=("$1")
}

collect_storage_ids() {
  _COLLECT_IDS_TMP=()
  _collect_ids_from_array WIPE_DIR_ENTRIES
  _collect_ids_from_array WIPE_LVM_VGS
  _collect_ids_from_array WIPE_ZFS_POOLS

  STORAGE_IDS_DISCOVERED=()
  if [[ ${#_COLLECT_IDS_TMP[@]} -gt 0 ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && STORAGE_IDS_DISCOVERED+=("$line")
    done < <(printf "%s\n" "${_COLLECT_IDS_TMP[@]}" | sort -u)
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

  filter_entry_array_by_scope WIPE_DIR_ENTRIES
  filter_entry_array_by_scope WIPE_LVM_VGS
  filter_entry_array_by_scope WIPE_ZFS_POOLS

  collect_storage_ids
}

# Filter a wipe-style array in place: keep only entries whose first field (storage id) passes scope.
filter_entry_array_by_scope() {
  # shellcheck disable=SC2178
  local -n arr=$1
  _FILTERED_ENTRIES_TMP=()
  for_each_sep_entry "$1" "_filter_entry_by_scope_callback"
  arr=("${_FILTERED_ENTRIES_TMP[@]}")
}

_filter_entry_by_scope_callback() {
  local storage_id="$1"
  local rest="$2"
  if is_storage_allowed_by_scope "$storage_id"; then
    _FILTERED_ENTRIES_TMP+=("${storage_id}${SEP}${rest}")
  fi
}
