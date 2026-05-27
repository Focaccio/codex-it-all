# SD-WAN Backup and Recovery Plan

Technical design for a portable baseline bundle workflow.

## Goal

Create a repeatable workflow that captures the configuration baseline for the
demo SD-WAN environment as one portable file. The file should be exportable from
the Orchestrator environment and usable to return the demo to a known-good
baseline after risky or failed changes.

Target environment:

- 1 self-hosted HPE Aruba Networking EdgeConnect Orchestrator
- 3 EdgeConnect EC-S-P appliances

This plan intentionally treats the artifact as a baseline bundle, not as a
single router-style configuration file. Orchestrator state and appliance state
are related but distinct and must be captured and restored through
vendor-supported mechanisms.

## Design Principles

- Use vendor-supported backup, restore, and API mechanisms.
- Do not scrape or modify Orchestrator application files as the source of truth.
- Do not assume Orchestrator configuration exists as one XML file.
- Keep one portable exported artifact for operators.
- Keep restore actions explicit and guarded.
- Default automation to dry-run and read-only behavior.
- Never commit credentials, license files, registration keys, account keys,
  portal responses, session cookies, appliance backups, or bundle payloads to
  Git.

## Artifact Shape

The exported baseline should be a compressed tar archive:

```text
sdwan-baseline-<name>-<timestamp>.tar.gz
```

Example:

```text
sdwan-baseline-demo-golden-2026-05-27T190000Z.tar.gz
```

Internal layout:

```text
manifest.yaml
README.txt
checksums/
  SHA256SUMS
orchestrator/
  backup/
    orchestrator-backup.<vendor-format>
  metadata/
    orchestrator-version.txt
    orchestrator-health.json
    inventory-snapshot.json
    api-schema-gmsApiInfo.json
appliances/
  edgeconnect-1/
    backup/
      appliance-backup.<vendor-format>
    metadata/
      appliance-health.json
      appliance-version.txt
      appliance-inventory.json
      api-schema-vxoaApiInfo.json
  edgeconnect-2/
    backup/
      appliance-backup.<vendor-format>
    metadata/
      appliance-health.json
      appliance-version.txt
      appliance-inventory.json
      api-schema-vxoaApiInfo.json
  edgeconnect-3/
    backup/
      appliance-backup.<vendor-format>
    metadata/
      appliance-health.json
      appliance-version.txt
      appliance-inventory.json
      api-schema-vxoaApiInfo.json
logs/
  capture.log
  validation.log
```

The exact backup file extensions and filenames should come from the vendor
export endpoints or UI download names. Do not invent a normalized internal
backup format.

## Manifest

`manifest.yaml` is the operator-readable and machine-readable index for the
bundle.

Required fields:

```yaml
bundle:
  format_version: 1
  name: demo-golden
  created_at: "2026-05-27T19:00:00Z"
  created_by: null
  description: Known-good demo baseline before change window.

environment:
  topology: one-orchestrator-three-ec-s-p
  inventory_source: inventory/demo-network.yaml
  air_gap: null

orchestrator:
  hostname: orchestrator-demo
  management_url: https://orchestrator.example.com
  version: null
  backup_file: orchestrator/backup/orchestrator-backup.<vendor-format>
  api_schema_file: orchestrator/metadata/api-schema-gmsApiInfo.json

appliances:
  - name: edgeconnect-1
    model: EC-S-P
    serial_number: null
    site: site-1
    ecos_version: null
    backup_file: appliances/edgeconnect-1/backup/appliance-backup.<vendor-format>
  - name: edgeconnect-2
    model: EC-S-P
    serial_number: null
    site: site-2
    ecos_version: null
    backup_file: appliances/edgeconnect-2/backup/appliance-backup.<vendor-format>
  - name: edgeconnect-3
    model: EC-S-P
    serial_number: null
    site: site-3
    ecos_version: null
    backup_file: appliances/edgeconnect-3/backup/appliance-backup.<vendor-format>

checksums:
  algorithm: sha256
  file: checksums/SHA256SUMS

restore:
  supports_orchestrator_restore: true
  supports_appliance_restore: true
  requires_operator_confirmation: true
  notes:
    - Restore must use vendor-supported Orchestrator and appliance restore paths.
    - Version compatibility must be checked before applying the bundle.
```

## Workflow 1: Capture Baseline

Command target:

```sh
python3 scripts/sdwan_baseline.py capture \
  --inventory inventory/demo-network.yaml \
  --name demo-golden \
  --output-dir artifacts/baselines
```

Planned steps:

1. Load and validate `inventory/demo-network.yaml`.
2. Confirm exactly one Orchestrator and three EC-S-P appliances are in scope.
3. Authenticate to Orchestrator using environment variables or an ignored local
   secrets file.
4. Run read-only preflight checks:
   - Orchestrator reachable.
   - Orchestrator API reachable.
   - All three appliances visible in Orchestrator inventory.
   - All three appliances reachable or at least manageable by Orchestrator.
   - Software versions recorded.
   - Air-Gap state recorded.
5. Fetch release-specific API schemas:
   - Orchestrator `gmsApiInfo.json`.
   - Appliance `vxoaApiInfo.json` for each EC-S-P if appliance access is
     available.
6. Trigger or download the vendor-supported Orchestrator backup.
7. Trigger or download vendor-supported appliance backups for the three EC-S-Ps.
8. Capture metadata snapshots:
   - Orchestrator version and health.
   - Appliance inventory.
   - Appliance versions and health.
   - Site names, model, serial number, and management URL where available.
9. Write `manifest.yaml`.
10. Generate `checksums/SHA256SUMS`.
11. Create the final `.tar.gz` bundle.
12. Validate the bundle by extracting it to a temporary directory and checking
    manifest paths and checksums.

Exit criteria:

- One `.tar.gz` bundle exists.
- Manifest references every included file.
- SHA-256 checksum validation passes.
- Bundle contains one Orchestrator backup and three appliance backups.
- Capture log is included.

## Workflow 2: Export Baseline Off Orchestrator

Command target:

```sh
python3 scripts/sdwan_baseline.py export \
  --bundle artifacts/baselines/sdwan-baseline-demo-golden-*.tar.gz \
  --destination /path/to/removable-media
```

Planned steps:

1. Verify the bundle exists and passes checksum validation.
2. Copy the bundle to the operator-selected destination.
3. Write a detached `.sha256` file beside the copied bundle.
4. Optionally write an export receipt:
   - Bundle name.
   - Size.
   - SHA-256 digest.
   - Export timestamp.
   - Destination path.

Air-Gap note:

- For isolated deployments, the destination should be approved removable media
  or another approved transfer location.
- Do not export uncompressed backup directories unless explicitly requested.

## Workflow 3: Inspect Baseline

Command target:

```sh
python3 scripts/sdwan_baseline.py inspect \
  --bundle artifacts/baselines/sdwan-baseline-demo-golden-*.tar.gz
```

Planned output:

- Bundle name and creation time.
- Orchestrator hostname and version.
- Appliance count, names, models, serials, sites, and ECOS versions.
- Backup file presence.
- Checksum status.
- Restore compatibility warnings.
- Air-Gap warnings if applicable.

This command must not require live Orchestrator access.

## Workflow 4: Restore Baseline

Command target:

```sh
python3 scripts/sdwan_baseline.py restore \
  --bundle artifacts/baselines/sdwan-baseline-demo-golden-*.tar.gz \
  --inventory inventory/demo-network.yaml \
  --dry-run
```

Apply mode:

```sh
python3 scripts/sdwan_baseline.py restore \
  --bundle artifacts/baselines/sdwan-baseline-demo-golden-*.tar.gz \
  --inventory inventory/demo-network.yaml \
  --apply \
  --confirm "RESTORE sdwan-demo"
```

Planned dry-run steps:

1. Extract the bundle to a temporary working directory.
2. Validate checksums.
3. Read `manifest.yaml`.
4. Compare bundle topology to current inventory.
5. Check Orchestrator software version compatibility.
6. Check appliance model and serial expectations.
7. Print the restore plan:
   - Orchestrator backup to restore.
   - Appliance backups to restore.
   - Expected interruption.
   - Post-restore validation checks.
8. Stop before making changes.

Planned apply steps:

1. Require `--apply`.
2. Require exact confirmation text.
3. Require successful checksum validation.
4. Require a fresh pre-restore safety capture unless explicitly bypassed.
5. Restore Orchestrator using the vendor-supported restore mechanism.
6. Restore the three EC-S-P appliance backups using the vendor-supported restore
   mechanism.
7. Run post-restore validation.
8. Write a restore report.

Restore guardrails:

- Do not restore if the bundle target does not match the inventory unless the
  operator explicitly supplies a documented override.
- Do not restore across incompatible Orchestrator or ECOS versions unless the
  vendor procedure supports it and the operator explicitly confirms it.
- Do not restore Air-Gap activation files or license artifacts from Git.
- Prefer appliance restore after Orchestrator restore, unless HPE guidance for
  the specific version requires a different order.

## Workflow 5: Post-Restore Validation

Command target:

```sh
python3 scripts/sdwan_baseline.py validate \
  --inventory inventory/demo-network.yaml
```

Checks:

- Orchestrator login/API reachable.
- Expected three EC-S-P appliances present.
- Appliance names, models, sites, and serial numbers match manifest or
  inventory.
- Appliances are online or in the expected demo state.
- Orchestrator version matches expected version.
- ECOS versions match expected versions or are reported as differences.
- API schema files can be fetched and compared to captured schema metadata.
- Key Orchestrator objects exist, including overlays, templates, sites, and
  tunnel exceptions where the demo uses them.
- New appliance backups can be triggered after restore.

Output:

- Human-readable validation summary.
- JSON validation report under an ignored runtime/output directory.

## Script Architecture

Primary script:

```text
scripts/sdwan_baseline.py
```

Suggested package layout:

```text
scripts/
  sdwan_baseline.py
  fetch_edgeconnect_openapi.py
sdwan_demo/
  __init__.py
  inventory.py
  orchestrator_client.py
  appliance_client.py
  bundle.py
  checksums.py
  commands/
    capture.py
    export.py
    inspect.py
    restore.py
    validate.py
tests/
  test_inventory.py
  test_bundle_manifest.py
  test_checksums.py
```

Keep the first implementation simple. It is acceptable to start with
`scripts/sdwan_baseline.py` and split into `sdwan_demo/` modules once behavior
is proven.

## API And Backup Integration Plan

Phase 1 should use the live OpenAPI schema and documented endpoints to confirm
the exact Orchestrator version's backup and restore operations.

Known starting points:

- `docs/edgeconnect-api-endpoints.md`
- Live Orchestrator `gmsApiInfo.json`
- Live appliance `vxoaApiInfo.json`
- Official `pyedgeconnect` SDK if it exposes the needed operations

Implementation tasks:

1. Fetch live API schemas with `scripts/fetch_edgeconnect_openapi.py`.
2. Search the schema for backup, restore, appliance inventory, health, version,
   and file download/upload endpoints.
3. Write a small endpoint map for the detected Orchestrator release.
4. Implement read-only discovery first.
5. Implement appliance backup trigger/download.
6. Implement Orchestrator backup trigger/download.
7. Implement restore only after capture and validation are reliable.

## Security Model

Secrets:

- Read credentials from environment variables or a local ignored `.env` file.
- Never write tokens or passwords into manifests.
- Redact authorization headers and cookies from logs.

Sensitive artifacts:

- Treat backup files as sensitive.
- Store local bundles under ignored `artifacts/` by default.
- Require explicit operator action to export bundles.
- For Air-Gap demos, follow approved transfer procedures.

Recommended ignore additions:

```text
artifacts/
.env
*.tar.gz
*.sha256
```

## Testing Plan

Unit tests:

- Inventory validation requires one Orchestrator and three EC-S-P appliances.
- Manifest generation includes all required paths.
- Checksum creation and verification works.
- Bundle extraction rejects path traversal entries.
- Inspect command works without live network access.

Integration tests:

- Fetch live Orchestrator schema.
- Fetch appliance schema from each EC-S-P when allowed.
- Run discovery against Orchestrator.
- Trigger a non-destructive appliance backup if supported.
- Capture a full baseline in a lab.
- Extract and validate the bundle.

Restore rehearsal:

- First restore into a disposable lab Orchestrator or snapshot-backed VM.
- Confirm Orchestrator-side objects return to expected baseline.
- Restore appliance configs only when the target appliances are safe to reset.
- Record version compatibility behavior.

## Implementation Phases

### Phase 0: Inventory And Schema Readiness

Deliverables:

- Finalize `inventory/demo-network.yaml`.
- Fetch and store live OpenAPI schemas under `references/edgeconnect/`.
- Identify exact backup and restore endpoints for the deployed release.

### Phase 1: Bundle Format And Offline Tooling

Deliverables:

- Manifest model.
- Checksum generation.
- Bundle create/extract/inspect.
- Unit tests for manifest, checksum, and archive safety.

### Phase 2: Read-Only Discovery

Deliverables:

- Orchestrator login/session handling.
- Inventory discovery.
- Version and health capture.
- Dry-run capture report.

### Phase 3: Capture Baseline

Deliverables:

- Orchestrator backup capture.
- Three EC-S-P appliance backup capture.
- Metadata capture.
- Final `.tar.gz` baseline bundle.
- Bundle validation.

### Phase 4: Export And Operational Runbook

Deliverables:

- Export command.
- Export receipt.
- Operator runbook for capture, inspect, export, and retention.

### Phase 5: Restore Dry-Run

Deliverables:

- Restore plan generation.
- Compatibility checks.
- Confirmation gates.
- Pre-restore safety capture.

### Phase 6: Restore Apply

Deliverables:

- Vendor-supported Orchestrator restore integration.
- Vendor-supported appliance restore integration.
- Post-restore validation.
- Restore report.

## Open Questions

- Which Orchestrator version will the demo use?
- Which ECOS version will the EC-S-P appliances run?
- Will appliance-local API access be available, or must all appliance backup
  operations go through Orchestrator?
- Is the demo fully Air-Gap, partially isolated, or normal connected mode?
- Where should exported bundles be stored off-Orchestrator?
- What is the acceptable restore interruption window?
- Should appliance restore be mandatory or optional during baseline restore?
- Should bundles be encrypted at rest, and if so, what key management process
  should be used?

## Definition Of Done

The baseline workflow is complete when an operator can:

1. Run one command to capture the baseline for the Orchestrator and three EC-S-P
   appliances.
2. Receive one validated `.tar.gz` bundle.
3. Export that bundle off the Orchestrator environment with a checksum.
4. Inspect the bundle without live network access.
5. Dry-run a restore and see exactly what will change.
6. Restore the baseline through guarded, vendor-supported steps.
7. Run validation and confirm the demo has returned to the known-good state.
