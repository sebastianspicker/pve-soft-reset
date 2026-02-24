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
