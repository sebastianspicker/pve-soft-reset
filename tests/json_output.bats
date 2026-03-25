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

@test "--json includes additive metadata fields and warnings array" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --json --non-interactive --include-storage local --exclude-storage local-lvm
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.meta.non_interactive == true' >/dev/null
  echo "$output" | jq -e '.meta.scope.include == "local"' >/dev/null
  echo "$output" | jq -e '.meta.scope.exclude == "local-lvm"' >/dev/null
  echo "$output" | jq -e '.warnings | type == "array"' >/dev/null
}

@test "--json-pretty prints valid JSON with indentation" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --json --json-pretty
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  printf '%s\n' "$output" | grep -q '^  "meta"'
}

@test "--json reports firewall_stack as nftables when nft succeeds" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"

  # Override the default mock (which exits 1) to succeed
  mock_cmd nft 'exit 0'

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.firewall_stack == "nftables"' >/dev/null
}

@test "--json reports ceph_found and ssh_keys_found boolean fields" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"

  # Default mocks: /etc/ceph and /var/lib/ceph do not exist in test tmpdir,
  # and /root/.ssh/authorized_keys is unlikely to have PVE keys.
  # This test verifies the fields exist as booleans in the JSON output.
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ceph_found | type == "boolean"' >/dev/null
  echo "$output" | jq -e '.ssh_keys_found | type == "boolean"' >/dev/null
}
