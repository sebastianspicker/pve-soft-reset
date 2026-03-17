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

@test "--dry-run --reset-pve-config logs intended removal of VM configs" {
  local pve_etc="$BATS_TEST_TMPDIR/pve-etc"
  local node_dir="$pve_etc/nodes/node-a"
  mkdir -p "$node_dir/qemu-server"
  touch "$node_dir/qemu-server/100.conf"

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_ETC="$pve_etc" PVE_SOFT_RESET_TEST_MODE=1 \
    "$SCRIPT" --dry-run --reset-pve-config --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '100\.conf'
}

@test "--dry-run --reset-pve-config logs intended removal of CT configs" {
  local pve_etc="$BATS_TEST_TMPDIR/pve-etc"
  local node_dir="$pve_etc/nodes/node-a"
  mkdir -p "$node_dir/lxc"
  touch "$node_dir/lxc/200.conf"

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_ETC="$pve_etc" PVE_SOFT_RESET_TEST_MODE=1 \
    "$SCRIPT" --dry-run --reset-pve-config --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '200\.conf'
}

@test "--dry-run --reset-pve-config logs intended clearing of jobs.cfg" {
  local pve_etc="$BATS_TEST_TMPDIR/pve-etc"
  mkdir -p "$pve_etc"
  touch "$pve_etc/jobs.cfg"

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_ETC="$pve_etc" PVE_SOFT_RESET_TEST_MODE=1 \
    "$SCRIPT" --dry-run --reset-pve-config --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'jobs\.cfg'
}

@test "--dry-run --reset-pve-config logs intended removal of SDN configs" {
  local pve_etc="$BATS_TEST_TMPDIR/pve-etc"
  mkdir -p "$pve_etc/sdn"
  touch "$pve_etc/sdn/vnet.cfg"

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_ETC="$pve_etc" PVE_SOFT_RESET_TEST_MODE=1 \
    "$SCRIPT" --dry-run --reset-pve-config --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'vnet\.cfg'
}

@test "--dry-run --reset-pve-config with no existing config files exits cleanly" {
  local pve_etc="$BATS_TEST_TMPDIR/pve-etc"
  mkdir -p "$pve_etc"

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_ETC="$pve_etc" PVE_SOFT_RESET_TEST_MODE=1 \
    "$SCRIPT" --dry-run --reset-pve-config --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Failures:[[:space:]]*0'
}

@test "--reset-pve-config with invalid node hostname increments failure count" {
  local pve_etc="$BATS_TEST_TMPDIR/pve-etc"
  mkdir -p "$pve_etc"
  mock_cmd hostname 'printf "bad hostname!"'

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_ETC="$pve_etc" PVE_SOFT_RESET_TEST_MODE=1 \
    "$SCRIPT" --dry-run --reset-pve-config --yes
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi 'invalid hostname'
  echo "$output" | grep -q 'Failures:[[:space:]]*1'
}
