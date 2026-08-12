# Grand Bruxelles Game — Master Status

Last coordinated review: 2026-08-12 07:19 Europe/Brussels

This is the live Day-1 integration/direction snapshot. Specialist documentation remains authoritative for implementation details; this file defines current gates, integration order and recovery priorities.

## Current main baseline

- `main`: `94a0196e0a30cb187d3692592e6a307cdbc8b427` (`ci(data): enforce per-cell maturity gates (#26)`).
- Main `Grand Bruxelles Game CI` and general `test` workflow are green on this head.
- First authoritative Ixelles 500 m seed cell is integrated and intentionally only `data_ready`; its manifest blocks promotion while terrain/heights/collisions/streaming/per-cell performance remain unproven.
- PNJ stop orchestration, disembark-first logic and step-free access interfaces are already absorbed into `main` from the last clean PNJ package.
- Headless performance regression baseline remains available; rendered GPU/frame-pacing budgets are still missing.
- Web preview/export machinery exists; preview success is not a realism certificate.

## Day-1 maturity check

| Area | State | Direction |
|---|---|---|
| Repository structure | WORKING FOUNDATION | Game ownership is clear, but stale/intermediate branches remain numerous. Keep them out of integration paths. |
| Branch discipline | ACTIVE REPAIR | Extraction-first is now mandatory. Three large specialist PRs are diverged and non-mergeable. |
| EPSG:31370 / Lambert 72 | STABLE FOUNDATION | Preserve Lambert 72 as source truth and project-local metre conversion at runtime/export boundaries. |
| UrbIS / official data pipeline | STABLE FOUNDATION | Strong base for geometry/provenance; height/terrain raster semantics still require hard proof. |
| OSM complementary data | WORKING PROTOTYPE | Keep secondary to authoritative Brussels geometry and preserve ODbL provenance. |
| Godot project health | WORKING | Main CI is green; specialist heads remain independently gated. |
| Automated tests / CI | WORKING | Domain gates catch real regressions; visual/runtime coverage still needs expansion. |
| Web preview | WORKING PREVIEW | Build/export exists; not a production or realism gate. |
| Performance baseline | USABLE HEADLESS BASELINE | Good regression guard; rendered benchmark still required. |
| Asset/license provenance | PARTIAL | Strong in mapping/photo-match lanes, incomplete project-wide. |
| Photo-match validation | REAL BUT EARLY | Lawful references and deterministic camera work exist; hero captures/mismatch closure remain open. |
| First playable vertical slice | INCOMPLETE | Midi → Grand-Place remains the integration benchmark and is not production-quality yet. |
| Branch integration health | RED/AMBER | Current weakest foundation dimension; specialist production outpaces safe absorption. |

## Active workstreams

### 1. Main / integration

Latest completed:
- per-cell machine-readable maturity contract integrated (`data_ready -> playable -> realism_validated`);
- first authoritative Ixelles seed cell remains correctly blocked at `data_ready`;
- main Game CI/test green.

Highest-priority resume:
- consolidate traffic from a clean branch created from the current `main`;
- do not integrate another large geographic block before height/terrain semantics and extraction packages are proven;
- add rendered visual/performance regression later as a shared foundation.

New recovery branch created this pass:
- `integration/traffic-canonical-core` from exact `main` head `94a0196e0a30cb187d3692592e6a307cdbc8b427`.

### 2. Laeken + Jette — PR #2

- Draft, base `main`, currently non-mergeable.
- Branch: `zone-laeken-jette`.
- Head: `4104b63cd84152d0e96c974b1cbbe6d98ff64080`.
- Drift: **278 ahead / 46 behind `main`**.
- 278 commits, 160 changed files.
- Ownership remains geographic/zone-specific; no wholesale merge.
- Source-faithful UrbIS geometry, terrain/height tooling, standalone scenes and photo-match infrastructure exist.
- Current realism resume: finish the deterministic Atomium ground-oblique capture/elevation proof, then Heysel context; Palais 5 stays unresolved until sufficiently fine authoritative geometry exists.
- Next integration must be a small extraction recreated from current `main`, never this 278-commit branch.

### 3. Rest of Brussels — PR #11

- Draft, base `main`, currently non-mergeable.
- Branch: `zone-reste-bruxelles-clean`.
- Head: `fe520eeecefc39b856aa9f0fcfeae4b5fc7cef16`.
- Drift: **58 ahead / 16 behind `main`**.
- 58 commits, 148 changed files.
- Ownership remains mapping/data/tooling only; do not merge wholesale.
- Critical correction: previous per-building DSM−DTM confidence counts are **invalidated** because repeated zero terrain/height samples were incorrectly treated as high confidence. The misleading CSV was removed and a semantic mosaic gate was added.
- No runtime height policy, terrain promotion or new municipality breadth until the official DSM/DTM values produce credible, non-degenerate elevation distributions through the stricter gate.

### 4. PNJ / police / civilians

Integrated foundation on `main` now includes:
- contextual population/crossings/stops;
- deterministic appearance/runtime hooks;
- ambient state variation;
- queues and stop orchestration;
- disembark-first behavior;
- step-free-access door constraints.

Next safe specialist lot:
- local crowd-reaction propagation;
- police de-escalation and return-to-patrol interfaces;
- pursuit/reaction interfaces that do not take ownership of traffic or mapping.

### 5. Vehicles & traffic — PR #3

- Draft, base `main`, currently non-mergeable.
- Branch: `vehicles-traffic`.
- Head: `70c023f83eacd3bdf33bae994c470cf5ac5446f0`.
- Drift: **152 ahead / 30 behind `main`**.
- 152 commits, 70 changed files.
- Structural debt still present: `traffic_manager_core.gd` plus v2-v9; `traffic_vehicle_core.gd` plus v2-v4; shared `main.tscn`, `vehicle_controller.gd` and shared CI modifications.
- Important finding: `traffic_manager.gd` points at **v8**, while v9 adds tow-service behavior. Therefore the highest-numbered file is not automatically the active canonical runtime.
- Freeze remains absolute: no `core_v10`, no new feature breadth, no wholesale merge.
- Recovery branch now exists: `integration/traffic-canonical-core`, created from current `main`.
- Exact recovery task: identify behavior actually exercised by the v8/v9 + vehicle-v4 test surface, flatten that behavior into one canonical manager and one canonical vehicle runtime, keep `main.tscn` untouched until core tests are green, then open a small PR.

## Branch hygiene alerts

- #2 `zone-laeken-jette`: RED/AMBER — 278 ahead / 46 behind, non-mergeable, 160 files. Extract only.
- #3 `vehicles-traffic`: RED — 152 ahead / 30 behind, non-mergeable, shared-scene/controller/CI contamination and versioned-core debt. Consolidation branch now created.
- #11 `zone-reste-bruxelles-clean`: AMBER/RED — 58 ahead / 16 behind, non-mergeable; ownership clean but raster-height evidence must be repaired before promotion.
- Historical `zone-reste-bruxelles` remains quarantined and is not an integration source.
- Stale/ambiguous branches still visible: `agent/police-ai-gameplay*`, old performance branches, `systems-npc-police-civilians-rebased`, recovery/checkpoint and merged extraction branches. Do not reuse without dependency verification.

## Living master backlog

1. **Traffic canonical consolidation** from current `main`; no scene wiring until red-to-green parity tests pass.
2. **Ixelles raster semantics**: re-run official DSM/DTM through the semantic quality gate; inspect real value distributions and sidecar/georeferencing interpretation; no new municipality.
3. **Laeken/Jette photo-match**: Atomium ground-oblique DTM eye elevation + deterministic 1280×720 capture + mismatch ranking, then Heysel context.
4. **PNJ/police**: crowd reactions + de-escalation/return-to-patrol behind narrow interfaces.
5. **Cell maturity hardening**: evidence hashes/references for terrain, heights, collisions, streaming, photo-match and per-cell performance.
6. **Vertical slice**: collisions, traffic interfaces, save/load, weather/day-night, spatial audio hooks, UI, shops/activities and interiors framework.
7. **Brussels-wide expansion** only after the above foundations can be integrated repeatedly without branch debt.

## Photo-match status

- Laeken/Heysel has lawful-reference infrastructure and deterministic camera auditing.
- Hero areas are not realism-complete.
- Atomium ground-oblique remains the immediate resume target; terrain eye elevation/capture proof is still required.
- Major visual gaps remain: generic façades/material repetition, unresolved fine landmark geometry, remaining fallback/uncertain heights, major vegetation/furniture/clutter alignment and missing final reference-matched captures.

## Direction / Assistant

### 1. What should be discussed with the user now
No blocking decision is required. Continue autonomously.

### 2. Recommendation
Measure Day-1 progress by **small green integrations absorbed into `main`**, not specialist commit count or Brussels coverage.

### 3. What can continue autonomously
Traffic consolidation, Ixelles raster debugging, Atomium/Heysel photo-match, PNJ de-escalation/crowd reactions, provenance QA and cell-maturity evidence hardening.

### 4. Single biggest risk
Specialist branches becoming more sophisticated than the integrated game, making valuable work progressively harder to absorb safely.

### 5. Next strategic idea worth testing
Extend each `cell_manifest.json` so every maturity promotion references machine-checkable evidence/hashes for authoritative source, terrain, building heights, collisions, streaming, photo-match and performance.

### 6. Concrete realism action
For hero views, fix the largest screen-space geometry discrepancies first: landmark alignment, silhouette/rooflines, road width, sidewalk/curb proportions and major terrain/vegetation masses before small material polish.

### 7. Concrete organization action
Treat long-lived specialist PRs as evidence/source branches only; all merge candidates must be recreated from the current `main` with one ownership domain and a small diff.

### 8. Maturity assessment
- **Prototype:** full traffic breadth, advanced crowd/police behavior, most façade/material/weather/audio/interior/economy breadth, rendered-performance testing.
- **Stable foundation:** EPSG:31370 convention, UrbIS-first policy, deterministic data tooling, main Godot CI, branch ownership gates, Web export, headless performance harness, first authoritative Ixelles data cell, cell maturity contract.
- **Production-ready:** nothing yet; no hero area or major gameplay subsystem meets full realism + provenance + QA + performance definition of done.

## Exact handoff

- `main`: `94a0196e0a30cb187d3692592e6a307cdbc8b427` before this documentation update.
- `integration/traffic-canonical-core`: created from that exact head.
- Resume traffic first by inventorying the test-observed v8/v9 and vehicle-v4 contract and flattening only that behavior into canonical runtimes without `main.tscn`.
- Resume #11 only by proving credible DSM/DTM value distributions through the new semantic gate.
- Resume #2 only by finishing Atomium ground-oblique capture/elevation evidence, then Heysel.
