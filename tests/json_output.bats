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

@test "--json outputs valid JSON" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --json
  [ "$status" -eq 0 ]

  echo "$output" | jq -e . >/dev/null
}

@test "--json contains stable top-level arrays" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --json
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.wipe_dir_entries | type == "array"' >/dev/null
  echo "$output" | jq -e '.wipe_lvm_entries | type == "array"' >/dev/null
  echo "$output" | jq -e '.wipe_zfs_entries | type == "array"' >/dev/null
  echo "$output" | jq -e '.third_party_packages | type == "array"' >/dev/null
  echo "$output" | jq -e '.third_party_with_origin | type == "array"' >/dev/null
  echo "$output" | jq -e '.storage_ids | type == "array"' >/dev/null
}
