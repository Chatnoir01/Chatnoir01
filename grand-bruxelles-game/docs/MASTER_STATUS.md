# Grand Bruxelles Game — Master Status

Last coordinated review: 2026-08-12 03:22 Europe/Brussels

This is the live Day-1 integration/direction snapshot. Specialist documentation remains authoritative for implementation details; this file defines current gates, integration order and recovery priorities.

## Current main baseline

- `main`: `5d7dc99db923e1fab671f5646ec73d97c2711bc1` after the automatic `web-preview` republish.
- Contextual NPC/pedestrian baseline is integrated on `main`.
- Police vehicle component baseline is integrated on `main`.
- Reproducible performance harness is integrated via PR #13; all four PR checks were green before merge.
- First captured headless artifact: ~77.36 FPS monitor average, ~58.40 MiB static memory, but zero render counters and an internally inconsistent `TIME_PROCESS` value. Therefore no hard performance budget is accepted yet.
- Follow-up PR #15 measures direct wall-clock frame average/p95 and explicitly flags unavailable render metrics. It is the current highest-priority integration follow-up.
- Godot web build exists in `web-preview`; the workflow automatically republishes after game changes. Public GitHub Pages availability is still a separate deployment/configuration concern and must not be confused with game health.

## Day-1 maturity check

| Area | State | Direction |
|---|---|---|
| Repository structure | WORKING FOUNDATION | Keep the game isolated under `grand-bruxelles-game/`; split large specialist histories into small integration packages. |
| Branch discipline | ACTIVE REPAIR | Ownership gate is useful, but PR #2/#3/#4 remain too large or non-mergeable. No wholesale merges. |
| EPSG:31370 / Lambert 72 | STABLE FOUNDATION | Preserve deterministic conversion and authoritative geometry ownership. |
| UrbIS / official data pipeline | STABLE FOUNDATION | Strong Day-1 asset; keep source-first provenance. |
| OSM complementary data | WORKING PROTOTYPE | Useful for traffic/services only where appropriate; preserve ODbL provenance. |
| Godot project health | WORKING | Main CI is healthy; specialist heads must be green and clean before extraction/integration. |
| Automated tests / CI | WORKING | Main, branch hygiene and performance workflows exist; keep converting regressions into explicit tests. |
| Web preview | BUILD WORKING / PUBLICATION PARTIAL | `web-preview` is refreshed automatically; public Pages configuration remains separate. |
| Performance baseline | HARNESS STABLE / METRICS UNDER CALIBRATION | PR #13 integrated; PR #15 fixes headless measurement reliability before budgets are set. |
| Asset/license provenance | PARTIAL | Require traceability for every external production/reference asset. |
| Photo-match validation | REAL BUT EARLY | Laeken/Jette has a real benchmark workflow; obvious mismatches remain blockers. |
| First playable vertical slice | INCOMPLETE | Midi → Grand-Place remains the integrated gameplay benchmark and must mature before broad city integration. |
| Branch integration health | RED/AMBER | Small integration lots work; huge specialist branches still carry excessive drift/debt. |

## Active workstreams

### 1. Main / integration

Current direction: integrate only small, green, ownership-clean lots.

Completed this cycle:
- PR #13 merged as `cc134a301a1d4a96c17d1bff6581d225fd60499e` (`qa: add reproducible Godot performance baseline`).
- Automatic web republish advanced `main` to `5d7dc99d…` without gameplay changes.
- The first artifact exposed a calibration problem rather than being accepted blindly.
- PR #15 was recreated from the latest `main` with a one-file wall-clock timing fix after the first attempt (#14) drifted behind the automatic web commit.

Next gate:
- make PR #15 green, inspect its artifact, then merge if wall-clock average/p95 are coherent.
- only after that define provisional Day-1 performance budgets.

### 2. Laeken + Jette — PR #2

- Draft, base `main`, current head observed `fbb687afb1d3e727a0f36fd1c93d62a58cc83df0`.
- 257 commits / 160 changed files at latest inspection.
- Currently non-mergeable as a whole.
- Source-backed UrbIS/terrain/height/photo-match work is valuable, but the branch is too large for direct integration.

Hard gate:
- stop treating the entire branch as an integration unit.
- finish the photo-match evidence for the selected hero area, then extract a small clean Laeken/Jette integration package from current `main` containing only stable zone data/scenes/provenance needed by the first playable package.

### 3. Rest of Brussels — PR #11 replaces contaminated PR #4

- PR #11 is the clean recovery path: 1 commit, 54 mapping/data files, no shared gameplay changes.
- Base `main`, head `cc830d36d18f87a7f214343afb6fbdeb4bd1d544`.
- Currently non-mergeable because `main` advanced after creation, not because the recovered content is cross-workstream contaminated.
- PR #4 remains quarantined historical work and must not be merged wholesale.

Hard gate:
- recreate/sync the clean baseline from current `main`, validate ownership, integrate it as a small data-only checkpoint, then resume interrupted Ixelles work before starting more communes.

### 4. PNJ / police / civilians

- Contextual pedestrian baseline is integrated on `main`.
- The previous enum/parser regression was fixed before integration.
- No geographic or traffic branch coupling should be introduced.

Next safe lot:
- population-flow profiles behind narrow interfaces (stop/station/commercial/residential + time-of-day), with deterministic tests and no map ownership leakage.

### 5. Vehicles & traffic — PR #3

- Draft, base `main`, latest inspected head `70c023f83eacd3bdf33bae994c470cf5ac5446f0`.
- 152 commits / 70 changed files.
- Currently non-mergeable.
- Functional value is high, but `traffic_manager_core.gd` plus `core_v2`…`core_v9` style accumulation and shared-scene coupling are unacceptable Day-1 debt.

Hard gate:
- freeze feature breadth.
- consolidate one canonical traffic core, preserve only proven compatibility shims, extract a small clean integration branch from current `main`, then rerun traffic/main/performance suites before adding STIB/accident breadth.

## Direction / Assistant

### What should be discussed with the user now

No blocking user decision is required. The important strategic message is that the project must optimize for validated integration velocity, not commit count or map coverage.

### Recommendation

1. Calibrate and merge PR #15 performance timing.
2. Recreate PR #11 cleanly on current `main` and integrate the authoritative mapping baseline.
3. Require PR #2/#3 to produce small extraction packages rather than trying to repair hundreds of commits in-place.
4. Keep Midi → Grand-Place as the playable integration slice while Laeken/Heysel serves as the visual/photo-match benchmark.
5. Do not expand municipality count until the Cell Definition of Done and performance budgets are measurable.

### What can continue autonomously

- performance calibration and provisional budgets;
- clean rest-of-Brussels baseline resync;
- Laeken/Jette photo-match mismatch reduction and extraction packaging;
- traffic core consolidation;
- PNJ context-flow profiles behind clean interfaces;
- provenance/QA/branch ownership tooling.

### Single biggest risk

**Specialist branches accumulating valuable but practically unintegrable work faster than `main` can absorb it.** This creates a false sense of progress and makes realism/performance regressions expensive to detect.

### Next strategic idea worth testing

Implement a machine-readable `cell_manifest.json` schema for every 500 m Brussels cell with explicit stages: `data_ready`, `playable`, `realism_validated`. Required fields should include authoritative sources, coordinate validation, terrain/heights coverage, collisions, photo-match references/mismatches, runtime streaming cost and performance sample IDs.

### One concrete realism action

For the next hero-area pass, rank photo-match mismatches by screen-space impact (silhouette/landmark alignment, roofline/height, street/sidewalk proportions first) instead of polishing small materials before major geometry is correct.

### One concrete organization action

Adopt a hard integration-size rule: specialist histories may be long, but any package targeting `main` should normally be <= ~30 commits and avoid shared `main.tscn` changes unless integration explicitly owns them. If not, recreate a clean extraction branch from current `main`.

### Maturity assessment

- **Prototype:** broad traffic feature set, richer civilian flows, police visuals, most art/facades/material/weather/audio, public web publication, photo-match scoring.
- **Stable foundation:** EPSG:31370 convention, UrbIS-first policy, main Godot health, branch ownership checks, baseline CI, reproducible performance harness structure.
- **Production-ready:** nothing yet. No area or subsystem should be labelled production-ready on Day 1.

## Branch hygiene alerts

- `zone-laeken-jette`: RED/AMBER — 257 commits and currently non-mergeable; extract clean packages, do not merge wholesale.
- `vehicles-traffic`: RED — 152 commits, non-mergeable, versioned-core debt; consolidation required.
- `zone-reste-bruxelles-clean`: AMBER — content ownership is clean, but it must be recreated/synced from current `main` before integration.
- `zone-reste-bruxelles` / PR #4: RED — contaminated historical branch; quarantine only.
- PNJ baseline: integrated; future PNJ lots must stay narrow.
- integration/performance branches: keep one-file/small-lot discipline and recreate immediately when the web bot advances `main` into a non-mergeable state.

## Realism definition of done

A hero area is not complete because footprints exist. Required evidence includes authoritative geometry, terrain/elevation, building heights/rooflines, facade proportions/materials, road/lane/sidewalk/curb dimensions, transit infrastructure, signs/lighting/furniture/vegetation, parking/clutter/weathering, contextual traffic/pedestrians, audio/light/weather context, deterministic lawful-reference screenshot comparison, collision integrity, provenance and a recorded performance budget. Unsupported details remain provisional rather than invented.

## Exact next handoff

1. `integration/performance-baseline-wallclock-v2` / PR #15: inspect four CI runs; if green, download artifact, verify wall-clock average/p95 + memory coherence, mark ready and squash-merge; if red, reproduce/fix before any new integration work.
2. `zone-reste-bruxelles-clean`: recreate from the then-current `main`, transplant only the 54 clean mapping/data files, rerun ownership/main CI, integrate if green, then resume Ixelles.
3. `vehicles-traffic`: no new features; consolidate canonical runtime and create a small extraction package from current `main`.
4. `zone-laeken-jette`: finish photo-match evidence/mismatch priorities, then extract a small integration package instead of repairing the entire 257-commit PR.
5. PNJ/police/civilians: continue population-flow realism only after main integration work above remains green.
