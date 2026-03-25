# JSON Output (v1)

`--json` emits a single JSON object.

## Top-Level Structure

- `meta` (object)
  - `version` (string)
  - `timestamp` (string, ISO 8601)
  - `hostname` (string)
  - `failure_count` (integer)
  - `mode` (string: `execute`, `dry-run`, `plan`, `audit`, `json`, or `list-storage`)
  - `non_interactive` (boolean)
  - `scope` (object)
    - `include` (string, CSV or empty)
    - `exclude` (string, CSV or empty)
- `wipe_dir_entries` (array of strings)
- `wipe_lvm_entries` (array of strings)
- `wipe_zfs_entries` (array of strings)
- `third_party_packages` (array of strings)
- `third_party_with_origin` (array of strings)
- `purge_services` (array of strings)
- `purge_packages` (array of strings)
- `purge_dirs` (array of strings)
- `storage_ids` (array of strings)
- `warnings` (array of strings)
- `errors` (array of strings)
- `firewall_stack` (string)
- `ceph_found` (boolean)
- `ssh_keys_found` (boolean)
- `reset_pve_config` (boolean)
- `reset_users_datacenter` (boolean)
- `reset_storage_cfg` (boolean)
- `no_sync` (boolean)

## Entry Encoding

Tuple-like entries are encoded as strings joined by `|` in JSON output.

Examples:

- `wipe_dir_entries`: `storage_id|path|subdir1|subdir2`
- `wipe_lvm_entries`: `storage_id|vg|lv1|lv2`
- `wipe_zfs_entries`: `storage_id|pool|dataset1|dataset2`
- `third_party_with_origin`: `origin|package`

## Validation Example

Requires [`jq`](https://jqlang.github.io/jq/):

```bash
./pve-soft-reset.sh --json | jq -e .
```

Pretty-printed output is available with:

```bash
./pve-soft-reset.sh --json --json-pretty
```
