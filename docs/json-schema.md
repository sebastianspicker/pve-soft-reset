# JSON Output (v1)

`--json` emits a single JSON object.

## Top-Level Structure

- `meta` (object)
  - `non_interactive` (boolean)
  - `scope.include` (string)
  - `scope.exclude` (string)
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
- `firewall_stack` (string)
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

```bash
./pve-soft-reset.sh --json | jq -e .
```

Pretty-printed output is available with:

```bash
./pve-soft-reset.sh --json --json-pretty
```
