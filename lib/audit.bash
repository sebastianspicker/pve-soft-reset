# pve-soft-reset audit: storage.cfg, LVM, ZFS, third-party, ceph, ssh, firewall (sourced after cli_preflight)
# Arrays and vars set here (PURGE_*, CEPH_FOUND, etc.) are used by execute and reporting.
# shellcheck disable=SC2034

# -----------------------------------------------------------------------------
# Audit: storage.cfg
# -----------------------------------------------------------------------------
subdirs_for_content() {
  local content="$1"
  local content_dirs="$2"
  local subdirs_list=""
  local seen=""
  local c subdir ov
  local content_arr=() content_dirs_arr=()

  # Split on comma only (no word-split on space) so tokens with spaces are preserved
  IFS=',' read -r -a content_arr <<< "${content:-}"
  for c in "${content_arr[@]}"; do
    c="$(trim "$c")"
    [[ -z "$c" ]] && continue
    subdir="${CONTENT_SUBDIR_MAP[$c]:-}"

    if [[ -n "$content_dirs" ]]; then
      IFS=',' read -r -a content_dirs_arr <<< "$content_dirs"
      for ov in "${content_dirs_arr[@]}"; do
        ov="$(trim "$ov")"
        if [[ "$ov" == "$c="* ]]; then
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
    current_node="$(resolve_node_name)"

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
  for_each_sep_entry WIPE_LVM_VGS "_audit_lvm_lvs_callback"
}

_audit_lvm_lvs_callback() {
  local storage_id="$1"
  local rest="$2"
  local vg thinpool
  split_sep "$rest"
  vg="$PIPE_LEFT"
  thinpool="$PIPE_RIGHT"
  list_lvs_to_remove "$storage_id" "$vg" "$thinpool"
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
  for_each_sep_entry WIPE_ZFS_POOLS "_audit_zfs_datasets_callback"
}

_audit_zfs_datasets_callback() {
  local storage_id="$1"
  local pool="$2"
  list_zfs_datasets_to_remove "$storage_id" "$pool"
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

  # shellcheck disable=SC2153
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
    # shellcheck disable=SC2034
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

  if [[ ${#PURGE_PACKAGES[@]} -gt 0 ]]; then
    local dedup_packages=()
    local -A seen_packages=()
    local key
    for key in "${PURGE_PACKAGES[@]}"; do
      [[ -z "$key" ]] && continue
      if [[ -z "${seen_packages[$key]+x}" ]]; then
        seen_packages["$key"]=1
        dedup_packages+=("$key")
      fi
    done
    PURGE_PACKAGES=("${dedup_packages[@]}")
  fi
}

audit_ceph() {
  if [[ -d /etc/ceph || -d /var/lib/ceph ]]; then
    # shellcheck disable=SC2034
    CEPH_FOUND=true
  else
    # shellcheck disable=SC2034
    CEPH_FOUND=false
  fi
}

audit_ssh_keys() {
  local auth_keys="/root/.ssh/authorized_keys"
  if [[ -f "$auth_keys" ]] && grep -qE "root@|pve" "$auth_keys"; then
    # shellcheck disable=SC2034
    SSH_KEYS_FOUND=true
  else
    # shellcheck disable=SC2034
    SSH_KEYS_FOUND=false
  fi
}

audit_firewall() {
  if command -v nft >/dev/null 2>&1 && nft list tables >/dev/null 2>&1; then
    # shellcheck disable=SC2034
    FIREWALL_STACK="nftables"
  elif command -v iptables >/dev/null 2>&1 && iptables -L >/dev/null 2>&1; then
    # shellcheck disable=SC2034
    FIREWALL_STACK="iptables"
  else
    # shellcheck disable=SC2034
    FIREWALL_STACK="unknown"
  fi
}
