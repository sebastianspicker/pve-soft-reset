#!/usr/bin/env bats

load helpers/common.bash

setup() {
  setup_mock_bin
  setup_base_mocks

  export SCRIPT="$BATS_TEST_DIRNAME/../pve-soft-reset.sh"
  export STORAGE_CFG_PATH="$BATS_TEST_TMPDIR/storage.cfg"
  setup_fixture_storage_cfg "$BATS_TEST_DIRNAME/fixtures/storage.cfg.basic" "$STORAGE_CFG_PATH"

  export ALLOWED_DIR_STORAGE_BASE="$BATS_TEST_TMPDIR"
}

@test "--list-storage lists discovered IDs (excluding disabled + other-node)" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --list-storage
  [ "$status" -eq 0 ]

  echo "$output" | grep -q '^local$'
  echo "$output" | grep -q '^local-lvm$'
  echo "$output" | grep -q '^zfs-local$'
  ! echo "$output" | grep -q '^disabled-store$'
  ! echo "$output" | grep -q '^other-node$'
}

@test "--include-storage rejects unknown IDs with usage exit code 2" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --plan --include-storage does-not-exist
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi 'unknown storage id'
}

@test "include/exclude scope is applied to planned actions" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" ALLOWED_DIR_STORAGE_BASE="$BATS_TEST_TMPDIR" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --plan --include-storage local,local-lvm --exclude-storage local
  [ "$status" -eq 0 ]

  ! echo "$output" | grep -q 'local|'
  echo "$output" | grep -q 'local-lvm|'
  ! echo "$output" | grep -q 'zfs-local|'
}

@test "storage ID containing SEP character is silently dropped" {
  # emit_storage_block guards against IDs or paths containing the internal
  # separator (unit separator U+001F). A malicious storage.cfg entry with
  # SEP in the id should be silently ignored, not propagated to wipe arrays.
  local injected_cfg="$BATS_TEST_TMPDIR/storage-inject.cfg"
  local sep=$'\037'
  mkdir -p "$BATS_TEST_TMPDIR/injected"
  printf "dir: injected%smalicious\n    path %s/injected\n    content iso\n" "$sep" "$BATS_TEST_TMPDIR" > "$injected_cfg"

  run env STORAGE_CFG="$injected_cfg" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --list-storage
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'injected'
  ! echo "$output" | grep -q 'malicious'
}

@test "empty storage.cfg produces no planned actions" {
  local empty_cfg="$BATS_TEST_TMPDIR/storage-empty.cfg"
  : > "$empty_cfg"

  run env STORAGE_CFG="$empty_cfg" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --plan
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'Dir storage'
  ! echo "$output" | grep -q 'LVM volumes'
  ! echo "$output" | grep -q 'ZFS datasets'
}
