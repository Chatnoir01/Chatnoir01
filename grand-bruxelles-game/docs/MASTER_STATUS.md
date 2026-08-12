# Grand Bruxelles Game — Master Status

Last coordinated review: 2026-08-12 14:22 Europe/Brussels

`main` plus small branches created from the exact current `main` define integration truth. Long-lived specialist branches are evidence/workspaces only; never merge them wholesale.

## Current main baseline

- `main`: `f1797ee0d86177ace2bc0b753ec31f405d3394b8` (`web: publish playable Grand Bruxelles build [skip ci]`), automatically published after #79.
- Clean integrations completed since the previous master snapshot:
  - #74 exact live civilian routine recovery after incidents;
  - #75 versioned Midi→Centre mission state snapshot contract;
  - #76 versioned atomic save store with integrity/recovery;
  - #77 mission save coordinator binding mission state to the save store;
  - #79 restore civilians to the current live daily schedule after incidents, including schedule-transition recovery.
- Open current-main gameplay handoff: #80 `integration/global-save-transaction-current`.
- Open long-lived specialist drafts: #2 Laeken/Jette and #11 rest of Brussels. Both are extraction-only.
- Web export is healthy. Public GitHub Pages remains an external repository-configuration issue, not a Godot export blocker.

## DAY-1 MATURITY CHECK

| Foundation | State | Day-1 direction |
|---|---|---|
| Repository structure | AMBER | Domain folders/workflows are usable, but branch inventory and unrelated repository-root history remain large. Keep integration path-scoped. |
| Branch discipline | RED/AMBER | Small integration lots are strongly gated and working. Specialist branches continue to diverge too fast and must not be merge units. |
| Authoritative data pipeline | STRONG FOUNDATION | UrbIS-first discovery, source hashing, EPSG validation, DSM/DTM evidence and official Ixelles 3D proof exist. Per-building approval remains pending. |
| Coordinate system integrity | STABLE FOUNDATION | EPSG:31370 / Belgian Lambert 72 remains authoritative source truth; local Godot metres derive from it. |
| Godot project health | STRONG FOUNDATION | Godot 4.7.1 main scene, canonical traffic, PNJ runtime, rendered checks and Web export function in CI. |
| Automated tests | STRONG FOUNDATION | General, domain, PNJ, traffic, branch-hygiene, asset-provenance, save, rendered-performance and photo-match gates are active. City-scale stress remains missing. |
| Web preview | BUILD GREEN / PUBLICATION SETTING BLOCKER | Build works; initial Pages activation is external configuration. |
| Performance baseline | AMBER | Deterministic rendered regression exists, but real GPU budgets, streaming/LOD and city-scale load are not production-proven. |
| Asset/license provenance | STABLE FOUNDATION | Existing binary assets are registered and unregistered binary assets are rejected in CI. The art library is still mostly placeholder-level. |
| First playable vertical slice | PLAYABLE PROTOTYPE | Midi→Centre runs with traffic, PNJ and a first mission. Bourse/Centre remains visibly generic and fails realism completion. |
| Branch integration health | RED/AMBER | Current-main extraction lots integrate well; specialist production still outruns integration truth. |

## Branch hygiene alerts

### PR #2 — `zone-laeken-jette`
- draft, base `main`, mergeable at GitHub metadata level but structurally unsafe as a merge unit;
- measured against current `main`: **499 ahead / 155 behind**;
- about 499 commits in the specialist history;
- contains valuable Atomium/Heysel/Palais 5/Jette data, DTM/DSM, trees, photo-match and standalone zone work, but too much unrelated specialist history to integrate safely;
- **never merge/rebase wholesale**. Extract one source-backed hero/data/runtime lot onto a fresh current-main branch.

### PR #11 — `zone-reste-bruxelles-clean`
- draft, base `main`, mergeable at GitHub metadata level but structurally unsafe as a merge unit;
- measured against current `main`: **112 ahead / 125 behind**;
- branch has continued broad mapping despite the Day-1 freeze;
- valuable Ixelles/terrain/municipality evidence remains useful as a source store;
- **do not add broad geography on this base**. Extract only small current-main Ixelles/cell contracts.

### PR #80 — `integration/global-save-transaction-current`
- clean small current-main gameplay lot; no geography, PNJ/police, traffic, `main.tscn` or `project.godot` ownership;
- latest head `d29c328caf8b6ea5f827fa2733aff1e5abac646f`;
- Branch Hygiene, Game CI, general tests and Photo Match are green on the latest head;
- dedicated Game State Save gate is currently **RED**: `GAME_STATE_SAVE_COORDINATOR_FAIL: transaction rollback failed`;
- Performance Baseline was still running at this review;
- **do not merge until rollback is fixed and every gate is green**.

## 1. Main / integration

Stable enough to build on:
- canonical traffic manager and vehicle runtime;
- official Brussels Mobility density evidence;
- PNJ population/crossing runtime;
- police de-escalation, custody and foot-patrol runtime foundations;
- civilian routine recovery plus live daily-schedule resumption;
- mission state snapshots, atomic versioned save store and mission-save round trip;
- branch quarantine/current-main gates;
- asset provenance gate;
- deterministic rendered performance/visual regression;
- Bourse/Atomium/Miroir photo-match registry and serious-mismatch evidence gate;
- official Ixelles UrbIS 3D second-source discovery.

Highest-priority resume candidate is #80 because it is a clean interrupted current-main handoff. It must remain blocked from merge until its transaction rollback regression is green. After this small save foundation lot, the highest-value visual priority is Bourse.

## 2. Centre / Bourse

The current compact Midi→Centre runtime is sufficient for a prototype but not a faithful Centre reconstruction. Existing photo-match evidence still reports a non-recognizable Palais de la Bourse silhouette, generic frontage/massing and street proportions that do not match the real reference.

The current Centre strategy must change from generic procedural enhancement to source-backed hero correction:
1. identify the real Palais de la Bourse footprint in authoritative UrbIS data;
2. obtain defensible height/roof evidence from UrbIS 3D and/or official DSM/LiDAR evidence;
3. validate the forecourt, street and sidewalk geometry;
4. replace the major silhouette/roofline mismatch;
5. rerun the fixed photo-match capture before adding micro-detail.

Do not broaden Centre coverage until this benchmark visibly improves.

## 3. Laeken + Jette

PR #2 is now a source/evidence store only. Continue only work that produces an extractable hero result. The next integration should be one tiny current-main extraction containing source/provenance + one hero component + deterministic test/capture, preferably Atomium ground-oblique or Palais 5. Avoid importing its Web pipeline, workflows or broad branch history.

## 4. Rest of Brussels / Ixelles

The broad specialist branch must no longer drive sequencing.

Next safe current-main lot:
- spatially match Ixelles building candidates to official UrbIS 3D `BuildingFaces`;
- derive ground/roof evidence, uncertainty and outlier distributions;
- approve only proven building heights; all uncertain cases remain `runtime_approved=false`.

Then generate/validate the 2 m DTM terrain package for the same five cells, quantifying seams, normals, collisions, render cost and streaming cost. Keep the 1 m terrain only as a justified hero/photo-match fallback.

## 5. PNJ / police / civilians

Completed foundation now includes:
- crowd response/memory;
- police response, de-escalation and custody;
- foot-patrol planning and live runtime consumption;
- civilian gradual recovery;
- exact walking/ambient/transit routine recovery;
- live daily-schedule recovery after incidents, including schedule transitions (#79).

Next PNJ realism lots after the current save handoff:
- varied pedestrian walk speeds and curb dwell;
- crowd spacing/avoidance and deterministic deadlock recovery;
- low-synchronization ambient timing;
- visual consumption of patrol look bias/animation metadata without inventing art assumptions.

## 6. Vehicles / traffic

Traffic foundation includes cars, scooters/motorcycles, routing, crossings, priority/right-of-way, time-of-day density, parking, deliveries, collision/wreck metadata and tow lifecycle plus official Brussels Mobility density evidence.

Next safe traffic lot: offline corridor/time-bucket evaluation against official Brussels Mobility evidence. After calibration evidence exists, proceed in separate small lots for STIB road interaction, intersection behavior, parking/garage behavior and accident/recovery depth. Do not mix these with PNJ or geographic ownership.

## 7. Gameplay / missions / economy / interiors / environment

Stable foundations:
- first Midi→Centre driving mission;
- versioned mission state export/restore;
- atomic versioned save store;
- mission save coordinator.

Current interrupted foundation:
- #80 transactional multi-domain game-state save coordinator; rollback regression red.

Still prototype or missing:
- save UI/autosave/checkpoint policy and real scene wiring;
- multiple mission chains and world-state consequences;
- economy, shops, activities and garages/repair gameplay;
- interiors framework;
- weather/day-night and Brussels-specific lighting;
- spatial audio/ambient soundscape;
- UI polish;
- collision coverage;
- city-wide LOD/streaming and stress validation.

After the save coordinator is stable, visual/geographic blockers take priority over adding more gameplay frameworks. Then preferred playable sequence: weather/day-night/lighting → spatial audio → shops/interiors framework → richer activities/garages.

## 8. Direction / Assistant

1. **Discuss with user now:** no gameplay decision blocks progress. GitHub Pages activation is optional only.
2. **Recommendation:** finish/fix the tiny #80 save handoff, then stop adding foundation layers and obtain a visible Bourse realism win before broader expansion.
3. **Can continue autonomously:** #80 diagnosis/fix workflow, Bourse authoritative geometry audit, Ixelles 3D comparison, one Laeken hero extraction, traffic calibration, PNJ movement realism, cell-readiness tooling.
4. **Single biggest risk:** specialist production outpacing integration truth. Day-1 branches at 499-ahead and 112-ahead are already expensive evidence stores rather than maintainable development branches.
5. **Strategic idea worth testing:** require every runtime geographic cell/hero anchor to pass a promotion machine: `candidate → source_verified → runtime_validated → photo_matched → runtime_approved`; expansion consumes only approved or explicitly provisional cells.
6. **Concrete realism action:** replace the generic Palais de la Bourse silhouette/roofline and immediate frontage/street massing using authoritative data, then rerun the exact fixed reference capture.
7. **Concrete organization action:** enforce a hard `workspace-only` state for quarantined specialist branches; new geographic production starts from current `main` and extracts only one coherent cell/hero lot.
8. **Maturity:** prototype = visible art, broad gameplay, interiors/economy/weather/audio, city streaming and most Brussels-wide coverage. Stable foundation = coordinates, source pipeline, CI, canonical traffic, PNJ core, save primitives, provenance, performance/photo-match and extraction workflow. Production-ready = nothing yet.

## Living master backlog

1. Fix #80 transaction rollback regression; merge only when all gates are green and branch is 0 behind `main`.
2. Bourse source-backed silhouette/roof/frontage/street geometry correction + fixed photo-match comparison.
3. Ixelles per-building UrbIS 3D comparison → confidence/outlier gate → runtime height approval only for proven cases.
4. Ixelles 2 m terrain runtime package: seams, normals, collisions, streaming/render cost.
5. Extract one source-backed Palais 5/Atomium hero package from Laeken onto current main.
6. PNJ movement/crowd realism: walk-speed variance, curb dwell, spacing, deadlock recovery.
7. Traffic official calibration evaluation, then STIB/intersection/parking/garage/accident lots.
8. Cell-readiness promotion state machine and hero-anchor coverage contract.
9. Weather/day-night + Brussels lighting and spatial audio.
10. Shops/activities/interiors/garages framework; Brussels-wide expansion only after repeatable cell promotion.

## Exact handoff

- Current `main`: `f1797ee0d86177ace2bc0b753ec31f405d3394b8`, Web publication immediately after merged #79.
- #79 is complete and merged: civilians now recover to the current live daily schedule after incidents, including schedule-transition cases.
- Open clean handoff: PR #80, branch `integration/global-save-transaction-current`, latest head `d29c328caf8b6ea5f827fa2733aff1e5abac646f`.
- #80 files: `.github/workflows/grand-bruxelles-game-state-save.yml`, `game/scripts/game_state_save_coordinator.gd`, `game/tests/game_state_save_coordinator_test.gd`.
- #80 current failure: dedicated Game State Save workflow, transactional test, `GAME_STATE_SAVE_COORDINATOR_FAIL: transaction rollback failed`; do not merge.
- #80 other observed gates on this head: Branch Hygiene GREEN, Game CI GREEN, general tests GREEN, Photo Match GREEN; Performance still running at review time.
- Open quarantined specialists: #2 (`499 ahead / 155 behind`) and #11 (`112 ahead / 125 behind`); both extraction-only.
- Current `MASTER_STATUS.md` on `main` was stale before this coordination pass; this update reconstructs it from exact `main`.
- Precise next coordinator action: finish/fix #80 rollback contract on its small current-main gameplay branch; if its branch becomes stale, recreate the same three-file lot from the new exact `main` rather than forcing a merge. Once green and integrated, immediately resume Bourse source-backed geometry/photo-match as the main visual priority.
