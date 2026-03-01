# pve-soft-reset execute phases (sourced after audit)
# Uses globals from constants/audit; state may be read by reporting.
# shellcheck disable=SC2034

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

        local had_nullglob=false had_dotglob=false
        shopt -q nullglob && had_nullglob=true
        shopt -q dotglob && had_dotglob=true
        shopt -s nullglob dotglob

        local files=("${dir}"/*)

        if ! $had_nullglob; then
          shopt -u nullglob
        fi
        if ! $had_dotglob; then
          shopt -u dotglob
        fi

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
  for_each_sep_entry WIPE_LVM_ENTRIES "_execute_wipe_lvm_entry"
}

_execute_wipe_lvm_entry() {
  local storage_id="$1"
  local rest="$2"
  local vg lvs lv
  local lv_arr=()

  split_sep "$rest"
  vg="$PIPE_LEFT"
  lvs="$PIPE_RIGHT"

  IFS="$SEP" read -r -a lv_arr <<< "$lvs"
  for lv in "${lv_arr[@]}"; do
    lv="$(trim "$lv")"
    [[ -z "$lv" ]] && continue
    run_or_dry "lvremove -y ${vg}/${lv}" "Removing LVM volume ${vg}/${lv} (storage: ${storage_id})" true lvremove -y "${vg}/${lv}" || true
  done
}

execute_wipe_zfs() {
  for_each_sep_entry WIPE_ZFS_ENTRIES "_execute_wipe_zfs_entry"
}

_execute_wipe_zfs_entry() {
  local storage_id="$1"
  local rest="$2"
  local pool datasets ds
  local ds_arr=()

  split_sep "$rest"
  pool="$PIPE_LEFT"
  datasets="$PIPE_RIGHT"

  IFS="$SEP" read -r -a ds_arr <<< "$datasets"
  for ds in "${ds_arr[@]}"; do
    ds="$(trim "$ds")"
    [[ -z "$ds" ]] && continue
    run_or_dry "zfs destroy -rf $ds" "Removing ZFS dataset $ds (storage: $storage_id)" true zfs destroy -rf "$ds" || true
  done
}

execute_purge_third_party() {
  local s d base pattern f

  for s in "${PURGE_SERVICES[@]}"; do
    [[ -z "$s" ]] && continue
    run_or_dry "systemctl stop --timeout=10s $s" "Stopping service $s" true systemctl stop --timeout=10s "$s" 2>/dev/null || true
  done

  if [[ ${#PURGE_PACKAGES[@]} -gt 0 ]]; then
    run_or_dry "apt-get purge --auto-remove -y ..." "Purging third-party packages" true apt-get purge --auto-remove -y "${PURGE_PACKAGES[@]}" || true
  fi

  for d in "${PURGE_DIRS[@]}"; do
    [[ -z "$d" ]] && continue
    if [[ "$d" == *'*'* ]]; then
      base="$(dirname "$d")"
      pattern="$(basename "$d")"
      [[ -d "$base" ]] || continue
      while IFS= read -r -d '' f; do
        run_or_dry "rm -rf $f" "Removing $f" true rm -rf "$f" || true
      done < <(find "$base" -maxdepth 1 -name "$pattern" -print0 2>/dev/null)
    else
      [[ -e "$d" ]] && run_or_dry "rm -rf $d" "Removing $d" true rm -rf "$d" || true
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
    [[ -d "$d" ]] && run_or_dry "rm -rf $d" "Removing Ceph directory $d" true rm -rf "$d" || true
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

run_clear_cfg_actions() {
  # shellcheck disable=SC2178
  local -n actions=$1
  local action path label
  for action in "${actions[@]}"; do
    [[ -z "$action" ]] && continue
    split_sep "$action"
    path="$PIPE_LEFT"
    label="$PIPE_RIGHT"
    clear_cfg_if_exists "$path" "$label"
  done
}

run_remove_file_actions() {
  # shellcheck disable=SC2178
  local -n actions=$1
  local action path label
  for action in "${actions[@]}"; do
    [[ -z "$action" ]] && continue
    split_sep "$action"
    path="$PIPE_LEFT"
    label="$PIPE_RIGHT"
    remove_file_if_exists "$path" "$label"
  done
}

run_wipe_dir_actions() {
  # shellcheck disable=SC2178
  local -n actions=$1
  local action path label
  for action in "${actions[@]}"; do
    [[ -z "$action" ]] && continue
    split_sep "$action"
    path="$PIPE_LEFT"
    label="$PIPE_RIGHT"
    wipe_dir_contents "$path" "$label"
  done
}

execute_reset_pve_config() {
  local node_name
  node_name="$(resolve_node_name)"
  if [[ ! "$node_name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    log_error "Invalid hostname for PVE node path: $node_name"
    return 1
  fi

  local base="${PVE_ETC}/nodes/${node_name}"
  execute_reset_sdn
  execute_reset_mappings

  remove_matching_glob "${base}/qemu-server" "*.conf" "Remove VM config"
  remove_matching_glob "${base}/lxc" "*.conf" "Remove CT config"

  local pve_clear_cfg_actions=(
    "${PVE_ETC}/jobs.cfg${SEP}Reset backup jobs (jobs.cfg)"
    "${PVE_ETC}/notification.cfg${SEP}Reset notification config"
    "${PVE_ETC}/metric-servers.cfg${SEP}Reset metric servers config"
    "${PVE_ETC}/ha/resources.cfg${SEP}Reset HA resources"
    "${PVE_ETC}/ha/rules.cfg${SEP}Reset HA rules"
    "${PVE_ETC}/vzdump.conf${SEP}Reset backup defaults (vzdump.conf)"
    "${PVE_ETC}/pve-ssh-known_hosts${SEP}Clear pve-ssh-known_hosts"
  )
  run_clear_cfg_actions pve_clear_cfg_actions

  local host_fw="${PVE_ETC}/firewall/nodes/${node_name}/host.fw"
  [[ -f "$host_fw" ]] && run_or_dry_write "Reset $host_fw" "Reset host firewall config" "$host_fw" '[OPTIONS]\n\n[RULES]\n\n'

  local cluster_fw="${PVE_ETC}/firewall/cluster.fw"
  [[ -f "$cluster_fw" ]] && run_or_dry_write "Reset $cluster_fw" "Reset cluster firewall config" "$cluster_fw" '[OPTIONS]\n\nenable: 0\n\n[RULES]\n\n'

  local pve_manager_lib="/var/lib/pve-manager"
  local pve_remove_file_actions=(
    "${pve_manager_lib}/pkgversions${SEP}Clear manager status file pkgversions"
    "${pve_manager_lib}/node_task_history${SEP}Clear manager status file node_task_history"
  )
  run_remove_file_actions pve_remove_file_actions

  local pve_wipe_dir_actions=(
    "${base}/priv${SEP}Wipe node private directory"
    "/var/log/pve/tasks${SEP}Wipe task logs"
  )
  run_wipe_dir_actions pve_wipe_dir_actions

  local fw_cfg
  for fw_cfg in alias.cfg groups.cfg ipset.cfg; do
    clear_cfg_if_exists "${PVE_ETC}/firewall/${fw_cfg}" "Reset firewall definition $fw_cfg"
  done
}

execute_reset_users_datacenter() {
  local user_cfg_minimal="user:root@pam:1:0:::::\nacl:1:/:root@pam:Administrator:\n"
  run_or_dry_write "Write minimal user.cfg" "Reset users/ACL to root@pam only" "${PVE_ETC}/user.cfg" "$user_cfg_minimal"

  local users_remove_actions=(
    "${PVE_ETC}/priv/token.cfg${SEP}Remove API tokens"
    "${PVE_ETC}/priv/tfa.cfg${SEP}Remove 2FA config"
    "${PVE_ETC}/priv/notifications.cfg${SEP}Remove notification secrets"
  )
  run_remove_file_actions users_remove_actions

  local users_wipe_actions=(
    "${PVE_ETC}/priv/storage${SEP}Remove storage secrets"
    "${PVE_ETC}/acme${SEP}Wipe ACME accounts/certificates"
  )
  run_wipe_dir_actions users_wipe_actions

  local users_clear_actions=(
    "${PVE_ETC}/priv/shadow.cfg${SEP}Clear password hashes"
    "${PVE_ETC}/domains.cfg${SEP}Remove authentication realms"
    "${PVE_ETC}/pools.cfg${SEP}Remove resource pools"
  )
  run_clear_cfg_actions users_clear_actions

  run_or_dry_write "Write minimal datacenter.cfg" "Reset datacenter.cfg to minimal" "${PVE_ETC}/datacenter.cfg" "# PVE datacenter - minimal\n\n"

  local f
  for f in /root/.bash_history /root/.ssh/known_hosts /var/mail/root /var/spool/mail/root; do
    remove_file_if_exists "$f" "Clean root hygiene artifact $f"
  done
}

execute_backup_pve_config() {
  local backup_file
  backup_file="/root/pve-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  run_or_dry "Backup /etc/pve -> $backup_file" "Creating /etc/pve backup at $backup_file" false tar czf "$backup_file" /etc/pve
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

# Sum max(0, sep_count - 1) over entries in named array and add to global var (e.g. LVS_REMOVED).
add_sep_minus_one_to_var() {
  # shellcheck disable=SC2178
  local -n arr=$1
  local dest_var=$2
  local e sep_count add sum=0
  for e in "${arr[@]}"; do
    [[ -z "$e" ]] && continue
    sep_count="$(printf "%s" "$e" | tr -cd "$SEP" | wc -c)"
    add=0; [[ "$sep_count" -gt 0 ]] && add=$((sep_count - 1))
    sum=$((sum + add))
  done
  declare -g "$dest_var=$((${!dest_var:-0} + sum))"
}

run_execution_phases() {
  ensure_safety_guards

  log_info "Starting storage wipe phase (dir)"
  execute_wipe_dirs
  # Count dir storage entries processed (not individual subdirs wiped).
  DIRS_WIPED=$((DIRS_WIPED + ${#WIPE_DIR_ENTRIES[@]}))
  maybe_sync

  log_info "Starting storage wipe phase (LVM)"
  execute_wipe_lvm
  add_sep_minus_one_to_var WIPE_LVM_ENTRIES LVS_REMOVED
  maybe_sync

  log_info "Starting storage wipe phase (ZFS)"
  execute_wipe_zfs
  add_sep_minus_one_to_var WIPE_ZFS_ENTRIES ZFS_REMOVED
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
