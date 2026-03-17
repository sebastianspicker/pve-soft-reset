#!/usr/bin/env bats

load helpers/common.bash

setup() {
  setup_mock_bin
  setup_base_mocks

  export SCRIPT="$BATS_TEST_DIRNAME/../pve-soft-reset.sh"
  export STORAGE_CFG_PATH="$BATS_TEST_TMPDIR/storage.cfg"
  setup_fixture_storage_cfg "$BATS_TEST_DIRNAME/fixtures/storage.cfg.basic" "$STORAGE_CFG_PATH"

  export ALLOWED_DIR_STORAGE_BASE="$BATS_TEST_TMPDIR"
  mkdir -p "$BATS_TEST_TMPDIR/local/images" \
           "$BATS_TEST_TMPDIR/local/dump" \
           "$BATS_TEST_TMPDIR/local/template/iso" \
           "$BATS_TEST_TMPDIR/local/template/qemu"
}

@test "--plan lists vm-prefixed LVM volume in planned actions" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --plan
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'vm-100-disk-0'
}

@test "--plan excludes protected LVM volumes (root, swap, data thinpool)" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --plan
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qE 'local-lvm\|pve\|root'
  ! echo "$output" | grep -qE 'local-lvm\|pve\|data($|[^/])'
}

@test "--plan lists vm-prefixed ZFS dataset in planned actions" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --plan
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'vm-200-disk-0'
}

@test "--dry-run emits LVM remove dry-run message for vm-prefixed volume" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --dry-run --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '\[DRY-RUN\] lvremove.*vm-100-disk-0'
}

@test "--dry-run emits ZFS destroy dry-run message for vm-prefixed dataset" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --dry-run --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '\[DRY-RUN\] zfs destroy.*vm-200-disk-0'
}

@test "--dry-run emits dir wipe dry-run message for dir storage" {
  touch "$BATS_TEST_TMPDIR/local/images/vm-100-disk-0.raw"

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --dry-run --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '\[DRY-RUN\].*local/images'
}

@test "--dry-run summary reports zero failures" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --dry-run --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Failures:[[:space:]]*0'
}
