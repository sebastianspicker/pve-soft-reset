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

@test "--log-file without argument exits with code 2" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --log-file
  [ "$status" -eq 2 ]
}

@test "blacklisted ALLOWED_DIR_STORAGE_BASE exits with preflight code 3" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" ALLOWED_DIR_STORAGE_BASE='/' PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --dry-run --yes
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi 'blacklisted path'
}

@test "--plan does not call destructive commands" {
  local marker="$BATS_TEST_TMPDIR/destructive-called"
  mock_cmd rm 'echo called >> "'$marker'"; exit 0'
  mock_cmd lvremove 'echo called >> "'$marker'"; exit 0'
  mock_cmd zfs 'if [[ "${1:-}" == "list" ]]; then printf "rpool/data/vm-200-disk-0\n"; else echo called >> "'$marker'"; fi'
  mock_cmd apt-get 'echo called >> "'$marker'"; exit 0'

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --plan
  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
}

@test "--no-color suppresses ANSI escape sequences" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --plan --no-color
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q $'\x1b\['
}

@test "blacklisted /var in ALLOWED_DIR_STORAGE_BASE exits with preflight code 3" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" ALLOWED_DIR_STORAGE_BASE='/var' PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --dry-run --yes
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi 'blacklisted path'
}

@test "--json-pretty without --json exits with code 2" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --json-pretty
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi 'requires --json'
}

@test "--non-interactive blocks prompt-required execution with preflight code 3" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --dry-run --reset-users-datacenter --non-interactive
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi 'non-interactive'
}

@test "--non-interactive with --yes runs without prompt block" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --dry-run --non-interactive --yes
  [ "$status" -eq 0 ]
}

@test "--report-file writes planning sections in --plan mode" {
  local report="$BATS_TEST_TMPDIR/plan-report.txt"
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --plan --report-file "$report"
  [ "$status" -eq 0 ]
  [ -f "$report" ]
  grep -q "Preflight" "$report"
  grep -q "Planned Actions" "$report"
  grep -q "Summary" "$report"
}

@test "--report-file under /etc/pve is rejected" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --plan --report-file /etc/pve/report.txt
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi 'report file'
}

@test "--report-file resolving into /etc/pve is rejected" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --plan --report-file "/tmp/../etc/pve/report.txt"
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi 'report file'
}

@test "symlink report-file is rejected in execute mode" {
  local target="$BATS_TEST_TMPDIR/real-report.txt"
  local link="$BATS_TEST_TMPDIR/report-link.txt"
  : > "$target"
  ln -s "$target" "$link"

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --yes --report-file "$link"
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi 'symlink'
}

@test "--report-file cannot be combined with --json" {
  local report="$BATS_TEST_TMPDIR/out.report.txt"
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --json --report-file "$report"
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi 'cannot be used with --json'
}

@test "--report-file cannot be combined with --list-storage" {
  local report="$BATS_TEST_TMPDIR/out.report.txt"
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --list-storage --report-file "$report"
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi 'cannot be used with --json or --list-storage'
}

@test "--log-file under /etc/pve is rejected in non-destructive mode" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --plan --log-file /etc/pve/pve-soft-reset.log
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi 'log file'
}

@test "--log-file resolving into /etc/pve is rejected in non-destructive mode" {
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --plan --log-file "/tmp/../etc/pve/pve-soft-reset.log"
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi 'log file'
}

@test "--log-file symlink is rejected in non-destructive mode" {
  local target="$BATS_TEST_TMPDIR/real-log.txt"
  local link="$BATS_TEST_TMPDIR/log-link.txt"
  : > "$target"
  ln -s "$target" "$link"

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --plan --log-file "$link"
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi 'symlink'
}

@test "dry-run does not report changed config files" {
  local pve_etc="$BATS_TEST_TMPDIR/pve-etc"
  mkdir -p "$pve_etc/priv"
  touch "$pve_etc/priv/token.cfg"

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_ETC="$pve_etc" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --dry-run --reset-users-datacenter --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Config files changed:[[:space:]]*0'
}

@test "dry-run with --reset-pve-config does not report changed config files" {
  local pve_etc="$BATS_TEST_TMPDIR/pve-etc"
  local node_dir="$pve_etc/nodes/node-a"
  mkdir -p "$node_dir/qemu-server" "$node_dir/lxc" "$pve_etc/mapping/pci" "$pve_etc/sdn"
  touch "$node_dir/qemu-server/100.conf" "$node_dir/lxc/200.conf" "$pve_etc/sdn/a.cfg" "$pve_etc/mapping/pci/a.cfg"

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_ETC="$pve_etc" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --dry-run --reset-pve-config --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Config files changed:[[:space:]]*0'
}
