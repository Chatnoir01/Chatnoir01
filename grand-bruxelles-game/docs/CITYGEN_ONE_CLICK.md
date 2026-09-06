# Grand Bruxelles — CityGen ONE CLICK

## Purpose

`Grand Bruxelles ONE CLICK` is the orchestration entrypoint for the existing City Machine / Autonomous CityGen factory. It is intentionally **not** a second city generator.

The first contract solves three systemic problems before taking runtime ownership:

1. normalize zone maturity independently from player-facing LABO/JOUABLE labels;
2. turn opaque HOLD text into a deterministic actionable queue;
3. expose one GitHub Actions button that can generate the plan and, only when explicitly requested, queue bounded passes of the existing Autonomous CityGen executor.

## Zone lifecycle

The orchestration lifecycle is separate from the player catalog quality label:

- `BLOCKED`
- `PARTIAL_DATA_READY`
- `DATA_READY`
- `RUNTIME_READY`
- `LABO_READY`
- `PROMOTION_REVIEW_REQUIRED`

`PARTIAL_DATA_READY` is deliberate: a partial Anneessens/Bourse-like source set can keep accumulating evidence without being falsely treated as complete or runtime-authorized.

No lifecycle state in this tool automatically changes the player catalog. `JOUABLE` remains human-promoted.

## Canonical HOLD codes

The resolver currently recognizes:

- `MISSING_SOURCE`
- `STALE_SOURCE`
- `HEIGHT_CONFLICT`
- `MISSING_DTM`
- `MISSING_OSM`
- `MISSING_RUNTIME_GATE`
- `MISSING_VISUAL_PROOF`
- `RUNTIME_WIRING`
- `OWNERSHIP_CONFLICT`
- `PARTIAL_COVERAGE`
- `UNKNOWN_HOLD`

Every row records whether it is mechanically actionable and a recommended next executor action. `UNKNOWN_HOLD`, source conflicts and ownership conflicts remain fail-closed.

## ONE CLICK workflow

Run **Actions → Grand Bruxelles ONE CLICK → Run workflow**.

Default behavior is safe/read-only:

1. run the ONE CLICK regression gate;
2. read `tools/city_machine/registry.json` and the playable-zone catalog;
3. build `one_click_plan.json`;
4. prove that runtime/JOUABLE authorization and main mutation are all false;
5. upload the plan as an Actions artifact.

Optional `advance_citygen=true` queues the already-existing `Grand Bruxelles Autonomous CityGen` workflow on `main`. `batch_size` is limited to 1–25 and `passes` to 1–12. Those passes keep the existing durable-state and fail-closed behavior; this wrapper does not copy their source acquisition, terrain, height or candidate logic.

## Safety rails

- no automatic mutation of `main`;
- no automatic LABO → JOUABLE promotion;
- no invented source, height, DTM, OSM or runtime proof;
- no global workflow PASS is converted into per-cell evidence;
- specialist executors remain source of truth for their gates;
- unknown blockers remain manual HOLD;
- the plan is deterministic and restartable.

## Why the catalog and factory registry are separate

A zone can already be visitable in the game while still lacking a reusable City Machine industrial profile. ONE CLICK therefore reports both concepts instead of treating the playable catalog as proof that the factory can reconstruct that zone.

At the time this foundation was built, `main` had seven player-catalog zones but only the Jette City Machine profile. The intended next factory changes are to add source-backed profiles/adapters without changing the player labels merely to make the numbers look green.

## Next integration lots

This foundation intentionally avoids files owned by active NPC, vehicle, Grand-Place and Midi runtime branches. Follow-up lots should be small and current-main based:

1. wire the normalized Midi City Machine outputs into the existing Midi runtime owner;
2. feed real zone/readiness and regional scheduler evidence into the ONE CLICK facts adapter;
3. dispatch missing specialized runtime gates by canonical HOLD code;
4. add an anti-stale PR/ownership planner;
5. aggregate exact promotion evidence into `PROMOTION_REVIEW_REQUIRED` while preserving explicit human JOUABLE approval.
