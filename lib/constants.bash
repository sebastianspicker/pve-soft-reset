# pve-soft-reset constants and option defaults (sourced by main script)
# All variables here are used by main and/or other libs.
# shellcheck disable=SC2034

VERSION="1.2.0"

readonly EXIT_OK=0
readonly EXIT_RUNTIME=1
readonly EXIT_USAGE=2
readonly EXIT_PREFLIGHT=3

# -----------------------------------------------------------------------------
# Options
# -----------------------------------------------------------------------------
DRY_RUN=false
AUDIT_ONLY=false
PLAN_ONLY=false
LIST_STORAGE=false
JSON_OUTPUT=false
CONFIRM=true
PURGE_ALL_THIRD_PARTY=false
RESET_PVE_CONFIG=false
RESET_USERS_DATACENTER=false
RESET_STORAGE_CFG=false
BACKUP_CONFIG=false
VERBOSE=false
QUIET=false
NO_SYNC=false
NO_COLOR=false
NON_INTERACTIVE=false
JSON_PRETTY=false

INCLUDE_STORAGE_CSV=""
EXCLUDE_STORAGE_CSV=""
REPORT_FILE=""

PVE_ETC="${PVE_ETC:-/etc/pve}"
STORAGE_CFG="${STORAGE_CFG:-/etc/pve/storage.cfg}"
LOG_FILE="${LOG_FILE:-/var/log/pve-soft-reset.log}"

# Test mode allows non-root and non-/etc/pve paths (used by automated tests only).
# Do not set PVE_SOFT_RESET_TEST_MODE in production; it bypasses safety checks.
TEST_MODE="${PVE_SOFT_RESET_TEST_MODE:-0}"

# Internal separator for safe tuple storage
SEP=$'\037'

# Content type -> directory mapping for dir storages
# PVE content types: images, rootdir, vztmpl, iso, backup, snippets
declare -A CONTENT_SUBDIR_MAP=(
  [images]=images
  [rootdir]=rootdir
  [vztmpl]=template/cache
  [iso]=template/iso
  [backup]=dump
  [snippets]=snippets
)
EXTRA_SUBDIRS=(template/qemu)

LVM_PROTECTED_DEFAULT="root swap data"
LVM_WIPE_EXTRA_PATTERN="${LVM_WIPE_EXTRA_PATTERN:-}"

# Third-party package detection baseline
VANILLA_ORIGINS="${VANILLA_ORIGINS:-Debian Proxmox}"
VANILLA_INCLUDE_CEPH="${VANILLA_INCLUDE_CEPH:-0}"
VANILLA_URI_PATTERNS="${VANILLA_URI_PATTERNS:-deb.debian.org security.debian.org download.proxmox.com enterprise.proxmox.com}"

# Known third-party stack defaults (CrowdSec)
CROWDSEC_SERVICES=(crowdsec crowdsec-firewall-bouncer crowdsec-firewall-bouncer-nftables crowdsec-firewall-bouncer-iptables)
CROWDSEC_PACKAGES=(crowdsec crowdsec-firewall-bouncer-nftables crowdsec-firewall-bouncer-iptables)
CROWDSEC_DIRS=(/etc/crowdsec /var/lib/crowdsec /var/log/crowdsec)

# Dir storage guardrail
ALLOWED_DIR_STORAGE_BASE="${ALLOWED_DIR_STORAGE_BASE:-/var/lib/vz}"
