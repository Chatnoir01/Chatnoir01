# Grand Bruxelles Game — Master Status

Last coordinated review: 2026-08-12 02:22 Europe/Brussels

This is the live integration/direction snapshot. It records what is safe to continue, what is blocked, and the next integration order. Specialist documentation remains authoritative for implementation details.

## Current main baseline

- `main`: `0dec005059aa0e19a6e82885c285cd881756e5df`.
- Isolated NPC / police / civilian baseline is integrated.
- Isolated police-vehicle component set is integrated.
- General `test` workflow on the current main head is green.
- Grand Bruxelles Game CI was green on the immediately preceding master-status head and on the police-vehicle integration; no new gameplay code was added by the two later branch-ownership/Pages commits.
- GitHub Pages deployment is **blocked/failing** by repository/Pages integration permissions/configuration; the Godot web build itself exists in `web-preview`.
- Police vehicle bodies/markings remain functional prototypes, not realism-complete production assets.

## Day-1 maturity check

| Area | State | Direction |
|---|---|---|
| Repository structure | WORKING FOUNDATION | Keep project isolated under `grand-bruxelles-game/`; avoid more duplicate runtime generations. |
| Branch discipline | RED / ACTIVE REPAIR | Ownership gate exists on `main`, but specialist branches have already accumulated large drift and one mapping branch is contaminated. |
| EPSG:31370 / Lambert 72 | STABLE FOUNDATION | Preserve as geometry reference; local Godot conversion must remain deterministic. |
| UrbIS / WFS / official data pipeline | STABLE FOUNDATION | Strongest Day-1 asset; keep provenance and source-first policy. |
| OSM complementary data | WORKING PROTOTYPE | Useful for traffic/services; keep ODbL provenance and never let it override official geometry without reason. |
| Godot project health | WORKING | Main baseline is healthy; specialist heads must each be green before integration. |
| Automated tests / CI | WORKING BUT UNEVEN | Main healthy; latest NPC specialist head failed before a parser fix now under validation. |
| Web preview | BUILD EXISTS / PUBLICATION BLOCKED | `web-preview` exists; public Pages deployment remains blocked by GitHub repository configuration/permissions. |
| Performance baseline | MISSING HARD METRIC | Highest missing foundation metric. Record repeatable FPS/frame-time/draw-call/instance/memory numbers before city expansion accelerates. |
| Asset/license provenance | PARTIAL | Registry/provenance exists; continue requiring traceability for every external production asset. |
| Photo-match validation | EARLY BUT REAL | Laeken now has one deterministic provisional Atomium view; gate requires at least three fixed views with matching captures/mismatch tracking. |
| First complete vertical slice | INCOMPLETE | Midi → Grand-Place remains the primary gameplay integration benchmark. |

## Active workstreams

### 1. Main / integration

Current direction: **integration freeze on large specialist PRs until cleanup**.

Safe work on `main`:
- performance benchmark harness;
- branch/ownership QA;
- web/publication diagnostics;
- narrow interfaces required by clean specialist extraction;
- documentation/provenance maintenance.

Do not merge PR #2/#3/#4 wholesale in their current state.

### 2. Vehicles & traffic — PR #3

Current head observed: `4d494bac0c29444259249f3d752bf48a044d3c2d`.

Fresh drift vs `main`:
- **148 commits ahead / 8 behind**;
- PR draft, currently mergeable as GitHub computes it, but historical drift is excessive;
- modifies shared `game/main.tscn`, `vehicle_controller.gd` and main CI;
- contains `traffic_manager_core.gd` plus `core_v2` … `core_v8`, and several `traffic_vehicle_core_v*` layers.

Functional value is high: road graph, signals, priority, crossings, density, mixed cars/scooters/motorcycles, parking/deliveries, damage/recovery/services and tested OSM metadata.

**Hard gate:** freeze feature breadth. Consolidate versioned runtime cores into one canonical implementation, keep only proven compatibility shims, expose a narrow traffic API, sync to `main`, then rerun traffic + vehicle + main suites. Only then resume accidents/STIB/extra breadth.

### 3. Laeken + Jette — PR #2

Current head observed: `16f7dcc79d964437d568de4892fca024875972a9`.

Fresh drift vs `main`:
- **182 commits ahead / 24 behind**;
- PR draft and currently mergeable;
- official UrbIS geometry, DTM/DSM/orthophoto, building-height work, official trees, captures and standalone web build exist.

Photo-match progress:
- `photo_match_views.json` exists;
- currently **1** benchmark view: `atomium_approach_south_v1`;
- 1.7 m eye height, 50° FOV, 1280×720 recorded;
- reference is CC0/public-domain as stated by source;
- viewpoint remains explicitly provisional, not survey-geolocated.

**Hard gate:** finish at least 3 deterministic real-reference ↔ in-game views with captures and mismatch records before more hero-area breadth. Then create/sync an integration-ready zone package; do not let the branch continue drifting indefinitely.

### 4. Rest of Brussels — PR #4

Current head observed: `f9de179c4dded6801fbfbe46253dff0f39cd8d60`.

Fresh drift vs `main`:
- **161 commits ahead / 8 behind**;
- PR draft and currently **non-mergeable**;
- useful UrbIS cell/coverage/orthophoto work spans Anderlecht, Molenbeek, Ixelles, Evere and additional municipality grids;
- branch is **contaminated** by unrelated police/gameplay assets/scripts and shared player/vehicle/main-scene edits.

Contamination confirmed in compare: police decals/vehicles, `police_dispatch.gd`, `wanted_system.gd`, police scenes/tests, `player_controller.gd`, `vehicle_controller.gd`, and `game/main.tscn` are present alongside mapping work.

**Hard gate:** freeze new commune breadth. Preserve all geographic data/pipelines, remove/isolate already-integrated police/gameplay material, reduce the branch to mapping + required streaming ownership, sync to current `main`, rerun mapping/ownership gates, then resume contiguous expansion.

### 5. NPC / police / civilians

Branch: `systems-npc-police-civilians`.

Fresh drift before latest fix: 3 commits ahead / 2 behind; only pedestrian-context script/test/CI changes beyond the integrated baseline.

Detected blocker:
- latest CI head `ac4e07e8…` failed specifically in `npc_pedestrian_context_test.gd`;
- import and baseline behavior smoke test passed;
- failure was a GDScript parser/type-resolution failure around `NpcPedestrianContext` enum signatures.

Coordinator action taken:
- commit `d052c7b05a17e219afa6ae6b44e3a0b55d8f9819` changes enum-typed method signatures to Godot-safe integer signatures while preserving enum constants/behavior;
- validation workflow is running on that fix at this snapshot.

**Gate:** do not add new NPC features until this run is green. If green, next safe lot is wiring contextual pedestrian intent through a narrow traffic/world interface without coupling to a geographic branch.

## Direction / Assistant

### What should be discussed with the user now

No blocking user decision is required. The project should continue autonomously, but the strategic message is important: Day-1 velocity is already outrunning integration discipline, so coverage speed is intentionally being throttled until quality gates catch up.

### Recommendation

For the next foundation cycle, prioritize in this exact order:
1. make the NPC specialist head green;
2. stop new breadth on PR #3/#4 and clean them;
3. finish the three-view Atomium photo-match benchmark;
4. establish hard performance budgets on `main`;
5. keep Midi → Grand-Place as the integrated gameplay vertical slice.

### What can continue autonomously

- PNJ parser fix validation and narrow pedestrian interface work after green CI;
- Laeken deterministic photo-match viewpoints/captures;
- traffic core consolidation without adding features;
- rest-of-Brussels branch cleanup without losing geographic commits;
- main performance harness and Pages diagnostics.

### Single biggest risk

**Production velocity outrunning integration and validation.** The project can accumulate hundreds of technically useful commits while becoming harder to merge, harder to benchmark and visually generic.

### Next strategic idea worth testing

Create a reusable **Brussels Cell Definition of Done** that every 500 m cell must satisfy before being promoted from data-ready → playable → realism-ready: authoritative geometry, terrain/heights, collisions, provenance, visual reference set, photo-match scorecard, streaming budget, draw/instance budget, traffic/pedestrian hooks and regression capture.

### One concrete realism action

Complete two additional Atomium/Heysel deterministic viewpoints and record explicit mismatches against the current capture, prioritizing silhouette/height, approach-axis proportions, tree line, curb/sidewalk geometry, furniture rhythm and visual clutter.

### One concrete organization action

Introduce a mandatory integration staging rule: any specialist PR over ~30 commits of drift or touching shared `main.tscn`/core CI must produce a small clean integration branch/package instead of being merged wholesale.

### Maturity assessment

- **Prototype:** traffic runtime breadth, contextual PNJ behavior, police vehicle visuals, web publication, most art/material/facade detail, photo-match scoring.
- **Stable foundation:** EPSG:31370 convention, UrbIS-first geometry policy, major source/provenance pipelines, main Godot baseline, branch ownership checks.
- **Production-ready:** nothing yet; Day 1 should not label any city area or gameplay subsystem production-ready.

## Branch hygiene alerts

- `zone-reste-bruxelles`: RED — contaminated and non-mergeable; clean before expansion.
- `vehicles-traffic`: AMBER/RED — functionally valuable but excessive runtime-version debt and shared-file coupling.
- `zone-laeken-jette`: AMBER — strong source-backed progress but extreme drift; finish benchmark then package/sync.
- `systems-npc-police-civilians`: AMBER — small clean diff, but latest CI failed; fix is under validation.
- `systems-police-vehicles`: baseline already integrated; avoid parallel reimplementation.
- Superseded/unknown agent branches remain quarantined unless ancestry/diff is explicitly reviewed.

## Realism definition of done

A hero area is not complete merely because coordinates/footprints are correct. Validation must cover authoritative geometry, terrain/elevation, building heights/rooflines, facade proportions/materials, road/lane/sidewalk/curb dimensions, public-transport infrastructure, signs/lighting/furniture/vegetation, parking/clutter/weathering, contextual traffic/pedestrians, audio/light/weather context, deterministic lawful-reference screenshot comparison, collision integrity, provenance and a recorded performance budget.

Unsupported details stay provisional rather than invented.

## Exact next handoff

1. `systems-npc-police-civilians`: wait for/inspect CI on `d052c7b…`; if green, resume narrow runtime integration; if red, reproduce next parser/runtime failure and fix before feature work.
2. `vehicles-traffic`: consolidate `core_v*` layers and shared-file coupling; no feature expansion.
3. `zone-laeken-jette`: add two more fixed photo-match views + captures/mismatch records, then package/sync.
4. `zone-reste-bruxelles`: remove police/gameplay contamination, preserve mapping data, sync, validate ownership, then resume contiguous cells.
5. `main`: add reproducible performance benchmark and keep public-web deployment issue isolated from game-health status.
