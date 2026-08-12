# Grand Bruxelles Game — Master Status

Last coordinated review: 2026-08-12 09:25 Europe/Brussels

This is the live Day-1 integration/direction snapshot. Specialist branches are evidence and workspaces; `main` plus small current-base extraction PRs define integration truth.

## Current main baseline

- `main`: `809e5b99b80c6807ad777c2fc45f1eefa9abe7f9` (`ci: enforce Day-1 extract-only branch quarantine`).
- Latest playable-content parent: `f6ced2b07f9ebd89bba04d63e06d14691f138ee5` (`traffic: add NPC crossing bridge`).
- Automatic Web export republished that playable parent at `393927072d755ff9595a7bf8fd8c9a88ae2548bf`.
- Recent clean integrations: canonical traffic runtime + tow + main-scene wiring, visual realism pass, PNJ/police response wiring, Brussels Mobility calibration snapshot, NPC/traffic crossing bridge, branch quarantine gate.
- Obsolete traffic draft PR #30 is closed; its branch remains evidence/history only.
- Open specialist drafts are PR #2 (Laeken/Jette) and PR #11 (rest of Brussels). Neither is an integration unit.

## DAY-1 MATURITY CHECK

| Foundation | State | Day-1 direction |
|---|---|---|
| Repository structure | WORKING FOUNDATION | Clear domain folders exist, but branch count is high. Prefer small extraction branches and retire superseded PRs. |
| Branch discipline | ACTIVE REPAIR | Extract-only quarantine is now machine-enforced for heavily drifted specialist PRs. |
| Authoritative data pipeline | STABLE FOUNDATION / PARTIAL RUNTIME | UrbIS-first, Lambert 72, provenance and deterministic processing are strong; terrain/heights still need runtime approval gates. |
| Coordinate system integrity | STABLE FOUNDATION | EPSG:31370 / Belgian Lambert 72 remains source truth; local Godot metres must derive from it, never replace it. |
| Godot project health | WORKING | Canonical traffic and PNJ bridge load in the real main scene; Web export remains healthy. |
| Automated tests | WORKING | General, domain and integration tests catch regressions; visual screenshot diff and rendered performance remain weak. |
| Web preview | WORKING PLAYABLE PREVIEW | Auto-export succeeds after gameplay changes; this is not a realism certificate. |
| Performance baseline | USABLE HEADLESS BASELINE | Headless regression guard exists; GPU/rendered frame-time budgets and streaming stress are still missing. |
| Asset/license provenance | PARTIAL | Strongest for mapping/photo-match/traffic data; project-wide asset registry still incomplete. |
| First playable vertical slice | INCOMPLETE BUT ACTIVE | Midi → Centre is playable and now has traffic + PNJ hooks, but geometry, visuals, missions, interiors, audio and systemic depth are not production quality. |
| Branch integration health | RED/AMBER → IMPROVING | Long-lived specialist branches are heavily diverged; new CI prevents accidental wholesale integration. |

## 1. Main / integration

### Completed / stable enough to build on
- one canonical unversioned traffic manager + vehicle core integrated in small lots;
- tow-service extension integrated;
- canonical traffic wired into `main.tscn` and tested by instantiating the real scene;
- visual realism pass merged without replacing canonical traffic;
- PNJ/police response integration recovered onto current main;
- Brussels Mobility official traffic calibration snapshot/pipeline integrated without silently changing runtime behavior;
- NPC crossing bridge integrated as a modular adapter;
- extract-only branch quarantine CI integrated.

### Highest-priority next lot
Create a small current-main vertical-slice hardening branch that adds **rendered main-scene performance + screenshot/photo-match evidence** without adding new geography. Day 1 now has enough systems that the next major risk is visually plausible but unmeasured runtime complexity.

### Do not do yet
- do not merge large geographic specialist branches;
- do not create new versioned traffic cores;
- do not broaden Brussels coverage before terrain/height/runtime cell promotion is repeatable;
- do not treat Web build success as visual fidelity proof.

## 2. Laeken + Jette — PR #2

- Branch: `zone-laeken-jette`.
- PR: draft, base `main`, **non-mergeable**.
- Current measured drift: **337 commits ahead / 70 behind `main`**.
- Current PR size: 337 commits, 181 changed files.
- Ownership: geographic/zone-specific; no shared-main integration should be added here.
- Strong evidence already exists: official UrbIS geometry, DTM/DSM work, trees, orthophoto metadata, Atomium hero tooling, deterministic capture infrastructure, Jette phase 2.
- Atomium hero view is still prototype realism: landmark framing/silhouette, foreground surfaces, vegetation, furniture, basin/fountain context, facade specificity and materials remain visibly weak.
- Heysel reference candidates are not yet proven camera positions.

**Resume next:** use the existing deterministic Atomium ground-oblique capture as a mismatch queue. Fix the largest screen-space discrepancies first, then render both Heysel candidates against source-backed geometry. No additional commune breadth until one hero view passes a repeatable photo-match review.

**Integration rule:** extract only one coherent data/runtime/visual package onto a new branch from current `main`; never rebase/merge the 337-commit branch wholesale.

## 3. Rest of Brussels — PR #11

- Branch: `zone-reste-bruxelles-clean`.
- PR: draft, base `main`, **non-mergeable**.
- Current measured drift: **79 commits ahead / 40 behind `main`**.
- Ownership remains mapping/data/tooling only.
- Official Ixelles DSM/DTM zero-mosaic bug is resolved; the cause was unsafe float32 NoData behavior during mosaicking.
- DTM evidence selects **2 m** as current runtime terrain candidate (worst-cell p95 ~0.137 m), with 1 m retained for hero fallback.
- Building height candidates remain `runtime_approved=false` pending second-source validation.

**Resume next:** cross-check Ixelles building heights against a second authoritative source, preferably UrbIS 3D Constructions; then generate a 2 m terrain runtime package for the existing five-cell block and measure seams, normals, collision behavior, streaming memory and rendered cost. No new municipality until that gate is green.

**Integration rule:** only extract a small evidence/runtime checkpoint onto current `main` after the terrain + second-source height gates pass.

## 4. Systems / gameplay

### PNJ / police / civilians
Integrated foundation now includes population/crossing/stop context, deterministic appearances, ambient variation, queues, disembark-first behavior, accessibility hooks, local crowd reactions, police de-escalation/return-to-patrol and clean `NpcAgent` response integration.

Next safe lot: connect the new traffic crossing bridge to real runtime PNJ selection/orchestration in the Midi vertical slice and prove that pedestrians wait at curbs, cross only on valid gaps/signals and restore destinations without deadlocks. Keep arrest/pursuit interfaces narrow and independent of traffic ownership.

### Vehicles / traffic
Canonical runtime is now the integration truth. The old `vehicles-traffic` branch remains quarantined evidence only. Current canonical main includes cars/scooters/motorcycles, graph routing, Brussels-style controls/right-priority handling, crossings, time-of-day density, parking, deliveries, wreck lifecycle, towing and the modular PNJ crossing bridge.

Recent realism improvement: official Brussels Mobility 1-minute calibration snapshot/pipeline is integrated with provenance and Lambert 72 conversion. Runtime density behavior should only be recalibrated after controlled comparison, not by directly copying snapshot values.

Next safe lot: build an **offline calibration evaluation** comparing canonical simulated counts/speeds against the Brussels Mobility snapshot by corridor/time bucket, then tune parameters behind deterministic tests. Do not mix this with vehicle art, police pursuit or main-scene visual changes.

### Other vertical-slice backlog
Still prototype/incomplete: missions, economy, shops/activities, interiors framework, garages/repair, save/load, weather/day-night, spatial audio, UI/HUD, collision coverage, STIB-specific road interactions, accidents/recovery depth, streaming/LOD and rendered performance.

Sequence these behind the current vertical slice rather than creating parallel city-wide breadth: saves + mission state, weather/day-night + lighting, spatial audio, then shops/interiors framework and richer activities.

## 5. Direction / Assistant

### 1. What should be discussed with the user now
No blocking decision is required. Continue autonomously. The only strategic choice worth surfacing later is whether the first realism benchmark should remain Midi → Bourse/Grand-Place or move to a hero Laeken view; recommendation: keep **Midi → Centre as gameplay benchmark** and use **Atomium as visual benchmark**, because they test different failure modes.

### 2. Recommendation
Stop measuring progress by area covered. For the rest of Day 1, optimize for repeatable green integration: one visual benchmark, one runtime-performance benchmark, one authoritative terrain/height promotion path and one stable gameplay slice.

### 3. What can continue autonomously
- rendered main-scene performance baseline;
- photo-match mismatch tracking;
- Ixelles second-source heights + 2 m terrain runtime gate;
- PNJ crossing runtime orchestration;
- traffic calibration evaluation;
- provenance/license audit and branch retirement.

### 4. Single biggest risk
**Specialist production outpacing integration truth.** Large branches can accumulate impressive work while becoming expensive or impossible to merge, creating multiple competing versions of Brussels and core systems.

### 5. Next strategic idea worth testing
Introduce a machine-readable `CELL_READINESS` / evidence manifest that ties each 500 m cell to source hashes, terrain resolution, height confidence, collision coverage, streaming budget, photo-match viewpoints and runtime approval. Expansion should consume only cells that satisfy the same contract.

### 6. Concrete realism action
For the Midi hero corridor and Atomium view, capture fixed 1280×720 in-game screenshots and rank the top 10 mismatches by screen-space impact: silhouette/height, street width, curb/sidewalk geometry, tram/road markings, facade proportions, vegetation masses, furniture/signage, materials/weathering, lighting and clutter. Fix the largest mismatch before adding detail elsewhere.

### 7. Concrete organization action
Keep `main.tscn`, `project.godot`, shared controllers and canonical traffic cores owned only by small integration branches. The new quarantine CI must remain a blocking merge gate for long-lived specialist sources.

### 8. Maturity assessment
- **Prototype:** most visuals, weather/audio/interiors/economy/activities, pursuit depth, city-wide streaming, rendered performance and most Brussels coverage.
- **Stable foundation:** EPSG:31370 convention, UrbIS-first pipeline, provenance habits, Godot CI, Web export, headless performance harness, cell-maturity concept, canonical traffic runtime, modular PNJ response/crossing interfaces, extraction-first branch policy.
- **Production-ready:** nothing yet. No hero area or subsystem currently satisfies realism + provenance + performance + QA simultaneously.

## Branch hygiene alerts

- `zone-laeken-jette`: RED — 337 ahead / 70 behind; non-mergeable; extract only.
- `zone-reste-bruxelles-clean`: RED/AMBER — 79 ahead / 40 behind; non-mergeable; extract only after runtime evidence gates.
- `integration/traffic-canonical-runtime`: superseded/diverged; PR #30 closed, evidence only.
- `vehicles-traffic`: quarantined evidence only; versioned core generations and shared-scene ownership are forbidden integration patterns.
- `zone-reste-bruxelles`: historical contaminated source, do not integrate.
- numerous old agent/performance/recovery branches remain; reuse only after explicit dependency verification.

## Living master backlog

1. Rendered performance baseline + deterministic main-scene screenshot benchmark.
2. Ixelles second-source building-height validation + source-faithful 2 m terrain runtime gate.
3. Atomium mismatch closure + Heysel candidate comparison.
4. Real PNJ crossing orchestration using the integrated bridge.
5. Brussels Mobility traffic calibration evaluation, then tested parameter tuning.
6. Cell evidence/readiness manifest hardening for terrain/heights/collisions/streaming/photo-match/performance.
7. Save/load + mission-state contract for the Midi vertical slice.
8. Weather/day-night + Brussels-specific lighting; then spatial audio.
9. Shops/activities/interiors framework, garages and accident/recovery gameplay.
10. Brussels-wide expansion only when the same cell/integration contract is repeatable.

## Exact handoff

- Current integration head at review start: `809e5b99b80c6807ad777c2fc45f1eefa9abe7f9`.
- Playable Web content corresponds to `f6ced2b0...` and was republished automatically at `39392707...`.
- Integrated during this coordination pass: PR #44 branch quarantine gate (`809e5b99...`).
- Cleaned during this pass: obsolete draft PR #30 closed with a superseded-integration note; branch retained for evidence/history.
- Open specialist drafts: PR #2 Laeken/Jette (non-mergeable) and PR #11 rest of Brussels (non-mergeable).
- Exact next coordinator action: create a current-main rendered-performance/screenshot-baseline lot; keep it free of new geography and gameplay breadth.
- Laeken/Jette next: Atomium mismatch fixes, then Heysel two-view comparison.
- Rest Brussels next: second-source Ixelles heights, then 2 m terrain runtime/seam/collision/streaming validation.
- Systems next: wire real PNJ crossing orchestration and separately evaluate traffic calibration against official snapshot.
