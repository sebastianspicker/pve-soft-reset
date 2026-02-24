#!/usr/bin/env bash

setup_mock_bin() {
  export MOCK_BIN="$BATS_TEST_TMPDIR/mock-bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"
}

mock_cmd() {
  local name="$1"
  shift
  cat > "$MOCK_BIN/$name" <<SCRIPT
#!/usr/bin/env bash
$*
SCRIPT
  chmod +x "$MOCK_BIN/$name"
}

setup_base_mocks() {
  # shellcheck disable=SC2016
  mock_cmd hostname 'if [[ "${1:-}" == "-s" ]]; then echo "node-a"; else echo "node-a"; fi'

  mock_cmd dpkg-query 'printf "bash\ncoreutils\n"'

  # shellcheck disable=SC2016
  mock_cmd apt-cache '
for pkg in "$@"; do
  cat <<OUT
${pkg}:
  Installed: 1.0
  Candidate: 1.0
 *** 1.0 100
        100 http://deb.debian.org/debian bookworm/main amd64 Packages
        release o=Debian,a=stable,n=bookworm,l=Debian,c=main,b=amd64
OUT
done
'

  mock_cmd dpkg 'exit 1'
  mock_cmd lvs 'printf "vm-100-disk-0\nroot\n"'
  # shellcheck disable=SC2016
  mock_cmd zfs 'if [[ "${1:-}" == "list" ]]; then printf "rpool/data/vm-200-disk-0\n"; fi'
  mock_cmd systemctl 'exit 0'
  mock_cmd lvremove 'exit 0'
  mock_cmd pvecm 'exit 1'
  mock_cmd nft 'exit 1'
  mock_cmd iptables 'exit 1'
}

setup_fixture_storage_cfg() {
  local fixture_src="$1"
  local fixture_out="$2"

  mkdir -p "$BATS_TEST_TMPDIR/local" "$BATS_TEST_TMPDIR/disabled" "$BATS_TEST_TMPDIR/other"
  sed "s#__BASE__#$BATS_TEST_TMPDIR#g" "$fixture_src" > "$fixture_out"
}

run_script() {
  local script="$1"
  shift
  PVE_SOFT_RESET_TEST_MODE=1 "$script" "$@"
}
