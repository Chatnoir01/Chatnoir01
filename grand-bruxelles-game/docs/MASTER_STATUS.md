# Grand Bruxelles Game — Master Status

Last coordinated review: 2026-08-12 06:18 Europe/Brussels

This is the live Day-1 integration/direction snapshot. Specialist documentation remains authoritative for implementation details; this file defines current gates, integration order and recovery priorities.

## Current main baseline

- `main`: `ad09d4e3525125f619ba084e445724eac61ca7c0` (`data: integrate authoritative Ixelles seed cell (#23)`).
- Latest integrated PNJ lot: `04c38318c53c276167b19562a45969d4befc13e1` (`NPC: ambient state machine and transit queue behavior (#22)`).
- Main `Grand Bruxelles Game CI` and `test` succeeded on `ad09d4e3…`.
- One authoritative Ixelles 500 m seed cell is now data-ready in `main`; it is not yet playable or realism-validated.
- Contextual pedestrians, population budgets, deterministic appearance, runtime appearance hooks, transit lifecycle, ambient state machine and deterministic transit queues are integrated.
- Reproducible headless performance baseline remains usable for regression comparison: about 6.90 ms/frame average, 7.22 ms p95, ~145 FPS estimated and ~58.4 MiB static memory. Render counters remain unavailable in headless and are not production budgets.
- Automatic playable Web export/publish machinery works; public Pages availability remains a deployment/configuration concern separate from game correctness.

## Day-1 maturity check

| Area | State | Direction |
|---|---|---|
| Repository structure | WORKING FOUNDATION | Keep game ownership under `grand-bruxelles-game/`; remove ambiguity from stale helper branches and keep integration packages short. |
| Branch discipline | ACTIVE REPAIR | Ownership separation is working, but specialist branches remain long-lived and heavily diverged. Mergeability alone is not permission to merge wholesale. |
| EPSG:31370 / Lambert 72 | STABLE FOUNDATION | Preserve deterministic conversion and authoritative geometry ownership. |
| UrbIS / official data pipeline | STABLE FOUNDATION | Strong Day-1 asset; exact source resolution, deterministic fetches and provenance are now proven on multiple lanes. |
| OSM complementary data | WORKING PROTOTYPE | Keep it secondary to authoritative geometry and preserve ODbL provenance. |
| Godot project health | WORKING | Main CI is green; specialist heads require their own green gates before extraction. |
| Automated tests / CI | WORKING | Main, ownership, mapping, PNJ and performance suites exist and are catching real regressions. |
| Web preview | BUILD WORKING / PUBLICATION PARTIAL | Export refresh works; public Pages status remains separate. |
| Performance baseline | USABLE HEADLESS BASELINE | Good regression guard; rendered benchmark still required before visual-performance budgets. |
| Asset/license provenance | PARTIAL | Strong in mapping/photo-match, incomplete project-wide. Every production/reference asset still needs traceability. |
| Photo-match validation | REAL BUT EARLY | Three lawful-reference viewpoints exist; deterministic candidate audit exists; required final captures and mismatch reduction remain open. |
| First playable vertical slice | INCOMPLETE | Midi → Grand-Place remains the gameplay benchmark. It must become coherent and visually convincing before Brussels-wide gameplay breadth. |
| Branch integration health | AMBER | Small extraction packages now integrate successfully (#22, #23), but #2/#3/#11 remain too large and highly diverged. |

## Active workstreams

### 1. Main / integration

Latest completed:
- PR #22 PNJ ambient states + transit queues integrated cleanly;
- Web build republished;
- PR #23 integrated the first authoritative Ixelles seed cell as data-only, deliberately excluding heuristic building heights/runtime activation.

Highest-priority resume:
- do not duplicate #23; the next mapping integration should wait for a small source-backed height/terrain evidence package from the Ixelles specialist lane;
- establish a machine-readable `cell_manifest.json` / Brussels Cell Definition of Done before many more cells enter `main`;
- add a rendered performance benchmark and visual regression capture before large scene integrations.

Cross-cutting backlog owned here: missions/gameplay framework, economy/shops/activities interfaces, interiors framework, weather/day-night, spatial audio hooks, UI, saves, world streaming/LOD/occlusion, collision QA, telemetry and shared architecture. Keep each modular and short-lived.

### 2. Laeken + Jette — PR #2

- Draft, base `main`.
- Head: `3141e2b79822bbda090b85b528121505675d63d4` (bot refresh after `a2cef211…`).
- 274 commits; compare vs current `main`: **274 ahead / 41 behind**.
- GitHub currently reports the PR technically mergeable, but this is still a long-lived specialist branch and must not be merged wholesale.
- Latest substantive work: authoritative candidate audit for `atomium_ground_oblique_v1`; 31 valid candidates were found before shortlist limiting, using UrbIS surfaces/buildings + official DTM extent + Atomium anchor rather than invented camera placement.
- Three lawful-reference viewpoints exist; no hero area is realism-complete.
- Palais 5 remains deliberately blocked because broad UrbIS geometry is not sufficiently hall-specific.

Hard gate:
- select the ground-oblique camera only from source-constrained candidates;
- derive exact DTM eye elevation and generate deterministic 1280×720 capture;
- record mismatch ranking by screen-space impact;
- then resolve `heysel_stadium_context_v1`;
- after photo evidence, extract a small current-main package rather than syncing the entire 274-commit branch.

### 3. Rest of Brussels — PR #11

- Draft, base `main`.
- Head: `1fbbbce6136f401b0d0af83baebe5709469ce890`.
- 54 commits; compare vs current `main`: **54 ahead / 11 behind**.
- GitHub currently reports the PR non-mergeable; ownership remains mapping/data/tooling only in the inspected diff.
- Ixelles expansion remains paused at five contiguous materialized cells.
- Four official DSM/DTM archives for tiles `149168` and `149169` have now been downloaded/hashed/validated in CI; DSM and DTM align at 2000×2000, 0.5 m/pixel, EPSG:31370 provenance preserved.
- Per-building DSM−DTM evidence covers 3,652 cell memberships / 3,498 unique UrbIS buildings: 3,556 high-confidence, 72 medium, 24 insufficient. No runtime height has been selected yet.
- The first authoritative Ixelles seed cell from this workstream has already been extracted and integrated separately via #23.

Hard gate:
- no new municipality and no coverage breadth;
- define/test a conservative runtime height-selection policy from p50/p75/p90 evidence, keeping the 24 insufficient cases explicit;
- derive DTM terrain for the same five cells with measurable error/LOD policy;
- only then extract the next small current-main package, preferably evidence/runtime for one cell before expanding.

### 4. PNJ / police / civilians

Integrated on `main`:
- contextual crossings/stops;
- contextual population budgets;
- deterministic appearance and runtime hooks;
- boarding/alighting lifecycle;
- idle desynchronization;
- deterministic ambient state machine;
- transit stop queue slots and boarding-order interface.

Next safe lot:
- external stop/station orchestration for multiple doors/queues and vehicle capacity without direct traffic-engine coupling;
- movement toward assigned queue slots and varied waiting behavior;
- then crowd reactions and police escalation/de-escalation through narrow interfaces.

### 5. Vehicles & traffic — PR #3

- Draft, base `main`.
- Head: `70c023f83eacd3bdf33bae994c470cf5ac5446f0`.
- 152 commits; compare vs current `main`: **152 ahead / 25 behind**.
- GitHub currently reports it technically mergeable, but the diff still modifies shared `game/main.tscn`, `vehicle_controller.gd`, main CI and contains `traffic_manager_core.gd` plus `core_v2` … `core_v9`, as well as multiple `traffic_vehicle_core_v*` generations.
- Functional value is high (roads, priority, crossings, density, parking, crashes, recovery, garages/services), but versioned-core layering is unacceptable Day-1 debt.

Hard gate:
- freeze feature breadth even though GitHub says mergeable;
- consolidate exactly one canonical traffic manager runtime and one canonical traffic vehicle core;
- isolate adapters/tests from shared scene changes;
- recreate a small current-main branch and prove traffic + vehicle + main + performance suites before any integration.

## Living master backlog

- main/integration: branch throughput, cell manifests, rendered benchmark, vertical-slice QA;
- Laeken+Jette: photo-match captures, terrain/heights, landmark/street mismatch reduction, provenance;
- rest of Brussels: Ixelles height policy + terrain, then contiguous expansion only after quality gate;
- PNJ/police/civilians: stop/station orchestration, crowd reactions, escalation/de-escalation;
- vehicles/traffic: canonicalize runtime, then STIB road behavior, intersections, parking, garages, accidents;
- missions/gameplay: strengthen Midi → Grand-Place mission loop before broad mission breadth;
- economy/shops/activities: interfaces first, source-backed locations later;
- interiors: modular portal/interior streaming framework, then hero interiors;
- weather/day-night: Brussels-like variation with measured lighting targets;
- audio: spatial hooks + location-specific ambience capture/provenance;
- UI/saves: stable schemas, accessibility, save compatibility;
- optimization: cell streaming, LOD, occlusion, collision budgets and rendered telemetry;
- QA/licenses: deterministic regression captures, provenance completeness, branch ownership;
- Direction/Assistant: re-evaluate sequencing every pass and stop breadth when integration or realism evidence falls behind.

## Branch hygiene alerts

- `zone-laeken-jette` / #2: RED/AMBER — 274 ahead / 41 behind. Technically mergeable now, but far too large. Extract only.
- `vehicles-traffic` / #3: RED — 152 ahead / 25 behind. Technically mergeable now, but shared-scene edits + versioned-core debt make wholesale merge unsafe.
- `zone-reste-bruxelles-clean` / #11: AMBER/RED — 54 ahead / 11 behind, non-mergeable. Ownership clean; continue specialist quality work and extract small packages.
- `zone-reste-bruxelles` / historical #4: CLOSED + QUARANTINED — never an integration source.
- Stale/ambiguous branches still visible: `agent/police-ai-gameplay*`, `integration/performance-baseline*`, `systems-npc-police-civilians-rebased`, recovery/checkpoint branches and merged extraction branches. Do not use them as sources without dependency verification; prune later once safe.

## Photo-match status

- Three lawful-reference viewpoints exist for Laeken/Heysel.
- `atomium_ground_oblique_v1` now has an authoritative candidate audit instead of arbitrary placement.
- Final deterministic ground-oblique capture remains open; Heysel/stadium context follows.
- Major open gaps: generic facades/street furniture, remaining fallback heights, final camera elevation/selection, missing reference-matched screenshots and Palais 5 fine geometry.
- No hero area is realism-complete.

## Direction / Assistant

### 1. What should be discussed with the user now
No blocking decision is required. The only useful strategic point is that technical mergeability is no longer a sufficient signal: #2 and #3 are mergeable according to GitHub but remain unsafe units of integration because of size/drift/debt.

### 2. Recommendation
Continue the extraction-first strategy. Prioritize quality evidence on existing cells/hero viewpoints over new Brussels coverage. Treat `main` absorption rate, not specialist commit count, as the primary Day-1 progress metric.

### 3. What can continue autonomously without asking
- Ixelles height policy + DTM terrain derivation;
- Atomium ground-oblique deterministic capture + mismatch ranking;
- PNJ multi-door stop/station orchestration;
- traffic core consolidation only, no new breadth;
- cell manifest + rendered benchmark + provenance tooling;
- stale branch inventory/cleanup planning.

### 4. Single biggest risk to project success
**Specialist branches becoming more sophisticated than the integrated game, creating an ever-growing gap between impressive isolated work and a coherent, stable playable Brussels.**

### 5. Next strategic idea worth testing
Make `cell_manifest.json` mandatory for every 500 m cell with lifecycle `data_ready` → `playable` → `realism_validated`, authoritative source hashes, CRS, terrain/height coverage, uncertainty flags, collision status, transit, photo references, open mismatches, streaming cost and performance sample. CI should reject invalid lifecycle promotions.

### 6. One concrete action to improve realism
For Atomium/Heysel and Midi hero views, score visual mismatches by visible screen area and fix the biggest geometry errors first: landmark alignment, silhouette/rooflines, street width, curb/sidewalk geometry and major vegetation/furniture masses before material polish.

### 7. One concrete action to improve project organization
Add a branch-age/divergence report to CI or coordination tooling that flags specialist branches over configurable thresholds (for example >50 commits ahead, >15 behind, or touching shared-scene files) and forces extraction rather than direct merge.

### 8. Maturity assessment
- **Prototype:** broad traffic feature set, advanced police/crowd systems, most facades/material/weather/audio/interior/economy breadth, public Pages deployment, rendered performance testing.
- **Stable foundation:** EPSG:31370 convention, UrbIS-first policy, deterministic data tooling, main Godot CI, branch ownership gate, Web export, headless performance harness, first authoritative Ixelles data cell.
- **Production-ready:** nothing yet; no geographic hero area or major gameplay subsystem meets the full realism + provenance + QA + performance definition of done.

## Realism definition of done

A hero area is not complete because footprints exist. Required evidence includes authoritative geometry, terrain/elevation, building heights/rooflines, facade proportions/materials, road/lane/sidewalk/curb dimensions, transit infrastructure, signs/lighting/furniture/vegetation, parking/clutter/weathering, contextual traffic/pedestrians, audio/light/weather context, deterministic lawful-reference screenshot comparison, collision integrity, provenance and a recorded performance budget. Unsupported details remain provisional rather than invented.

## Exact next handoff

1. **Main/integration:** create `cell_manifest.json` schema + validation as the next small shared foundation; do not integrate another large geographic block first.
2. **Rest of Brussels / #11:** resume exactly where stopped: conservative runtime height policy, then DTM terrain/error/LOD for the same five Ixelles cells; no new municipality.
3. **Laeken/Jette / #2:** finalize `atomium_ground_oblique_v1` from audited candidates + DTM eye elevation, capture deterministically, rank mismatches, then process `heysel_stadium_context_v1`.
4. **Vehicles/traffic / #3:** consolidate versioned cores; no new traffic features until one canonical runtime exists and a small current-main extraction passes all suites.
5. **PNJ/police/civilians:** multi-door stop/station orchestration, queue movement and varied waiting; then crowd/police reactions.
6. **Direction/Assistant:** next pass must verify whether `main` advanced, whether #2/#3 are still falsely tempting because they are technically mergeable, whether #11 resolved height/terrain, and whether any stale branch was accidentally reused.