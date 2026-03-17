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

@test "empty installed package list produces no third-party packages in JSON" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  mock_cmd dpkg-query 'printf ""'

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.third_party_packages | length == 0' >/dev/null
  echo "$output" | jq -e '.third_party_with_origin | length == 0' >/dev/null
}

@test "package with non-vanilla origin is flagged as third-party" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  mock_cmd dpkg-query 'printf "custom-tool\n"'
  # shellcheck disable=SC2016
  mock_cmd apt-cache '
for pkg in "$@"; do
  cat <<OUT
${pkg}:
  Installed: 1.0
  Candidate: 1.0
 *** 1.0 100
        100 https://packages.custom-vendor.io/debian bookworm/main amd64 Packages
        release o=CustomVendor,a=stable,n=bookworm,l=CustomVendor,c=main,b=amd64
OUT
done
'

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.third_party_packages | contains(["custom-tool"])' >/dev/null
}

@test "package with vanilla Debian origin is not flagged as third-party" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  mock_cmd dpkg-query 'printf "bash\n"'

  # setup_base_mocks already mocks apt-cache with Debian origin for all packages
  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.third_party_packages | length == 0' >/dev/null
}

@test "package with no apt-cache entry is flagged as third-party with unknown origin" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  mock_cmd dpkg-query 'printf "mystery-pkg\n"'
  mock_cmd apt-cache 'printf ""'

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.third_party_packages | contains(["mystery-pkg"])' >/dev/null
  echo "$output" | jq -e '[.third_party_with_origin[] | select(startswith("unknown|"))] | length > 0' >/dev/null
}

@test "CrowdSec package appears in purge targets when installed" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  mock_cmd dpkg-query 'printf "crowdsec\n"'
  mock_cmd dpkg 'printf "ii  crowdsec  1.6.0  amd64  CrowdSec\n"'
  # shellcheck disable=SC2016
  mock_cmd apt-cache '
for pkg in "$@"; do
  cat <<OUT
${pkg}:
  Installed: 1.0
  Candidate: 1.0
 *** 1.0 100
        100 https://packagecloud.io/crowdsec/crowdsec bookworm/main amd64 Packages
        release o=packagecloud/crowdsec/crowdsec,a=bookworm,n=bookworm
OUT
done
'

  run env STORAGE_CFG="$STORAGE_CFG_PATH" PVE_SOFT_RESET_TEST_MODE=1 "$SCRIPT" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.purge_packages | contains(["crowdsec"])' >/dev/null
}
