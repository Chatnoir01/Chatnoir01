# Grand Bruxelles Game — Master Status

Last coordinated review: 2026-08-12 08:25 Europe/Brussels

This is the live Day-1 integration/direction snapshot. Specialist documentation remains authoritative for implementation details; this file defines current gates, integration order and recovery priorities.

## Current main baseline

- `main`: `11a83fb0c3f0e64b497cf4ffcf2bc331b88d70f2` (`web: publish playable Grand Bruxelles build [skip ci]`).
- Functional parent: `8339916accea4c3074a54c658824237c90555454` (`traffic: establish canonical runtime parity contract`, PR #29).
- PR #29 is merged. Its five gates were green on the final head: Traffic Canonical, Game CI, Branch Hygiene, general `test`, Performance Baseline.
- First authoritative Ixelles 500 m seed cell remains intentionally only `data_ready`; its manifest blocks promotion while terrain/heights/collisions/streaming/per-cell performance remain unproven.
- PNJ stop orchestration, disembark-first behavior, step-free access, local crowd reactions and police de-escalation foundations are integrated.
- Headless performance regression baseline remains available; rendered GPU/frame-pacing budgets are still missing.
- Web preview/export machinery is healthy; preview success is not a realism certificate.

## Day-1 maturity check

| Area | State | Direction |
|---|---|---|
| Repository structure | WORKING FOUNDATION | Ownership domains are clear, but stale/intermediate branches remain numerous. Keep them out of integration paths. |
| Branch discipline | ACTIVE REPAIR / RED-AMBER | Extraction-first is mandatory. One traffic freeze was violated by a new v10 core, proving long-lived specialist branches cannot be trusted as integration paths. |
| EPSG:31370 / Lambert 72 | STABLE FOUNDATION | Preserve Lambert 72 as source truth and project-local metre conversion only at runtime/export boundaries. |
| UrbIS / official data pipeline | STABLE FOUNDATION | Strong geometry/provenance base; raster semantics now repaired on Ixelles but secondary validation is still required before runtime promotion. |
| OSM complementary data | WORKING PROTOTYPE | Keep secondary to authoritative Brussels geometry and preserve ODbL provenance. |
| Godot project health | WORKING | Main CI is green on the latest functional integration; specialist heads remain independently gated. |
| Automated tests / CI | WORKING | Domain gates catch real regressions, including two traffic contract-test defects this run. Visual/runtime coverage still needs expansion. |
| Web preview | WORKING PREVIEW | Build/export exists; not a production or realism gate. |
| Performance baseline | USABLE HEADLESS BASELINE | Good regression guard; rendered benchmark still required. |
| Asset/license provenance | PARTIAL | Strong in mapping/photo-match lanes, incomplete project-wide. |
| Photo-match validation | REAL BUT EARLY | Atomium ground-oblique now has source position + DTM eye elevation + deterministic capture; mismatch closure remains open. |
| First playable vertical slice | INCOMPLETE | Midi → Grand-Place remains the integration benchmark and is not production-quality yet. |
| Branch integration health | RED/AMBER | Current weakest foundation dimension; specialist production still outpaces safe absorption. |

## Active workstreams

### 1. Main / integration

Latest completed:
- PR #29 canonical traffic parity contract integrated into `main`;
- contract protects 17 manager methods, 9 vehicle methods, v8 wreck lifecycle and v9 tow behavior as an optional extension;
- canonical target names are now unversioned (`traffic_manager_core.gd`, `traffic_vehicle_core.gd`);
- two CI/test defects were found and fixed before merge: GDScript type inference and an over-broad `_v` filename check.

Active recovery branch:
- `integration/traffic-canonical-runtime`;
- fast-forwarded to current `main` head `11a83fb0...`;
- no implementation commit yet;
- target is exactly one canonical manager and one canonical vehicle core, with no `main.tscn` wiring until isolated parity is green.

Highest-priority resume:
- write the red parity test for the canonical manager/vehicle pair;
- inventory validated behavior from legacy v8, v9, v10 and vehicle-v4 tests;
- flatten only behavior that has evidence/tests; no `core_v*` imports.

### 2. Laeken + Jette — PR #2

- Draft, base `main`, currently diverged/non-mergeable.
- Branch: `zone-laeken-jette`.
- Head: `4c73c33428a5c519a738f2349a25e503892439c3`.
- Drift: **292 ahead / 51 behind `main`**.
- 292 commits.
- Ownership remains geographic/zone-specific; no wholesale merge.
- Atomium ground-oblique now has lawful source coordinates, official DTM eye elevation (~66.63 m including 1.70 m eye height) and deterministic 1280x720 capture.
- Current realism resume: correct the largest mismatches in that capture, then resolve/render both Heysel candidate viewpoints; Palais 5 remains unresolved until sufficiently fine authoritative geometry exists.
- Next integration must be a small extraction recreated from current `main`, never this branch.

### 3. Rest of Brussels — PR #11

- Draft, base `main`, currently diverged/non-mergeable.
- Branch: `zone-reste-bruxelles-clean`.
- Head: `afeeba6b12e738c8aa83e8f69f05f46b9f8ef704`.
- Drift: **75 ahead / 21 behind `main`**.
- 75 commits.
- Ownership remains mapping/data/tooling only; do not merge wholesale.
- Previous all-zero DSM/DTM evidence was invalidated; root cause was extreme float32 NoData interacting with raster mosaicking.
- Corrected pipeline now produces plausible Ixelles terrain/elevation distributions and conservative height candidates, but all candidates remain `runtime_approved=false` pending secondary validation.
- DTM 1/2/4/8 m LOD/error evidence exists; no new municipality until a measured terrain candidate and second-source height validation are accepted.

### 4. PNJ / police / civilians

Integrated foundation on `main` includes:
- contextual population/crossings/stops;
- deterministic appearance/runtime hooks;
- ambient state variation;
- queues and stop orchestration;
- disembark-first behavior;
- step-free-access door constraints;
- local crowd-reaction model;
- police de-escalation / return-to-patrol model.

Next safe specialist lot:
- wire police response and crowd reaction into `NpcAgent` runtime with red-to-green tests;
- preserve narrow pursuit/arrest interfaces that do not take ownership of traffic or mapping.

### 5. Vehicles & traffic — PR #3

- Draft, base `main`, technically mergeable at the moment but structurally quarantined.
- Branch: `vehicles-traffic`.
- Current drift: **157 ahead / 35 behind `main`**.
- 74 changed files.
- HARD GATE VIOLATION: `traffic_manager_core_v10.gd` was added despite the explicit freeze against any `core_v10`.
- v10 extends v9 and adds an NPC-crossing bridge; this behavior is now only a candidate for canonical recovery, not integration truth.
- Structural debt now includes `traffic_manager_core.gd` plus v2-v10, `traffic_vehicle_core.gd` plus v2-v4, shared `main.tscn`, `vehicle_controller.gd` and shared CI changes.
- PR #3 body has been updated: the branch is evidence/source only. No further runtime implementation belongs there.
- Approved implementation path: `integration/traffic-canonical-runtime` only.

## Branch hygiene alerts

- #2 `zone-laeken-jette`: RED/AMBER — 292 ahead / 51 behind. Extract only.
- #3 `vehicles-traffic`: RED — 157 ahead / 35 behind, shared-scene/controller/CI contamination, v2-v10 manager generations, and an explicit freeze violation. Evidence only.
- #11 `zone-reste-bruxelles-clean`: AMBER/RED — 75 ahead / 21 behind; ownership clean, but only small evidence/runtime packages may be extracted.
- Historical `zone-reste-bruxelles` remains quarantined and is not an integration source.
- Stale/ambiguous branches remain visible: old police stages, old performance branches, NPC rebases, recovery/checkpoint and merged extraction branches. Do not reuse without dependency verification.

## Living master backlog

1. **Traffic canonical runtime** on `integration/traffic-canonical-runtime`: red parity test, then one manager + one vehicle core; no shared scene wiring yet.
2. **Ixelles secondary validation**: select terrain LOD from measured error/performance and cross-check building-height candidates against a second authoritative source before runtime approval.
3. **Laeken/Jette photo-match closure**: Atomium mismatch ranking/fixes, then Heysel two-candidate render comparison; no raw geographic breadth.
4. **PNJ/police runtime wiring**: integrate crowd reactions + de-escalation into `NpcAgent`, behind clean interfaces.
5. **Cell maturity hardening**: machine-checkable hashes/references for terrain, heights, collisions, streaming, photo-match and per-cell performance.
6. **Vertical slice**: collisions, traffic interfaces, save/load, weather/day-night, spatial audio hooks, UI, shops/activities and interiors framework.
7. **Brussels-wide expansion** only after the above foundations can be integrated repeatedly without branch debt.

## Photo-match status

- Atomium ground-oblique: lawful source coordinates, authoritative DTM eye elevation and deterministic 1280x720 capture are complete.
- That capture is not realism-complete: landmark scale/cadrage, foreground surfaces, vegetation, furniture, basin/fountain context, facade specificity and materials remain visibly weak.
- Heysel: lawful reference registered; 92 m top-sphere and 36 m lateral viewpoint remain plausible candidates, not proven camera positions. Next step is UrbIS stadium target geometry + two renders + mismatch comparison.
- Palais 5 remains blocked pending hall-specific authoritative geometry.

## Direction / Assistant

### 1. What should be discussed with the user now
No blocking decision is required. Continue autonomously.

### 2. Recommendation
For the next several runs, judge progress by **small green integrations into `main`** and by reduction of uncertainty, not specialist commit count or area coverage.

### 3. What can continue autonomously
Traffic canonical runtime, Ixelles second-source validation/DTM LOD choice, Atomium/Heysel photo-match closure, PNJ runtime wiring, provenance QA and cell-maturity evidence hardening.

### 4. Single biggest risk
Long-lived specialist branches continuing to evolve after quarantine instructions, producing competing truths faster than `main` can absorb them.

### 5. Next strategic idea worth testing
Add a machine-enforced `integration_source` / `quarantined_source_only` metadata gate for specialist PRs/branches so CI can fail when a quarantined branch creates a forbidden `core_v*` generation or modifies shared scene/controller files.

### 6. Concrete realism action
For hero views, fix the largest screen-space discrepancies first: landmark scale/alignment, silhouette/rooflines, road width, sidewalk/curb proportions, terrain and major vegetation masses before small material polish.

### 7. Concrete organization action
Promote quarantine from documentation to CI: fail specialist traffic pushes that add `traffic_manager_core_v[0-9]+` or touch shared `main.tscn`/controller files after the freeze point.

### 8. Maturity assessment
- **Prototype:** full traffic breadth on specialist branch, advanced crowd/police behavior, most facade/material/weather/audio/interior/economy breadth, rendered-performance testing.
- **Stable foundation:** EPSG:31370 convention, UrbIS-first policy, deterministic data tooling, main Godot CI, branch ownership gates, Web export, headless performance harness, first authoritative Ixelles data cell, cell maturity contract, canonical traffic API contract.
- **Production-ready:** nothing yet; no hero area or major gameplay subsystem meets full realism + provenance + QA + performance definition of done.

## Exact handoff

- `main`: `11a83fb0c3f0e64b497cf4ffcf2bc331b88d70f2`.
- Integrated this pass: PR #29 canonical traffic parity contract (`8339916a...`), followed by automatic Web publish (`11a83fb0...`).
- Active traffic implementation branch: `integration/traffic-canonical-runtime`, exactly aligned to current `main` and still code-empty.
- PR #3 is evidence/source only; v10 freeze violation is recorded and must not be propagated automatically.
- Exact next action: on `integration/traffic-canonical-runtime`, write a failing parity test that requires the unversioned canonical manager/vehicle pair, then implement the smallest behaviorally complete pair by flattening only validated v8/v9/v10 + vehicle-v4 behavior without `main.tscn`.
- #11 next: second-source height validation + measured terrain LOD decision, no new municipality.
- #2 next: Atomium mismatch closure, then Heysel candidate renders.
