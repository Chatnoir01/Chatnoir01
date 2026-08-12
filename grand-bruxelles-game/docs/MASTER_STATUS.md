# Grand Bruxelles Game — Master Status

Last coordinated review: 2026-08-12 05:18 Europe/Brussels

This is the live Day-1 integration/direction snapshot. Specialist documentation remains authoritative for implementation details; this file defines current gates, integration order and recovery priorities.

## Current main baseline

- `main`: `767b3f4697842ed7385629abfcb80dce7d2fe7ce` after automatic playable Web republish.
- Latest integrated gameplay merge: `e0485c44000531e341053fcf6386e6c4cf08448d` (`NPC: runtime appearance integration (#21)`).
- Main `Grand Bruxelles Game CI` and `test` succeeded on that gameplay merge; the following bot commit only refreshed `web-preview` outputs.
- Contextual pedestrian behavior, contextual population budgets, deterministic appearance variation, runtime appearance hooks, transit boarding/alighting lifecycle hooks and idle desynchronization are integrated.
- Police vehicle component baseline remains integrated.
- Reproducible performance harness + wall-clock refinement remain integrated; usable headless reference is about 6.90 ms/frame average, 7.22 ms p95, ~145 FPS estimated and ~58.4 MiB static memory. Headless render counters are not production budgets.
- Public GitHub Pages availability remains a deployment/configuration concern separate from game correctness.

## Day-1 maturity check

| Area | State | Direction |
|---|---|---|
| Repository structure | WORKING FOUNDATION | Keep game ownership under `grand-bruxelles-game/`; reduce stale helper branches and integrate via small extraction packages. |
| Branch discipline | ACTIVE REPAIR | Ownership gate works, but #2/#3/#11 are all currently non-mergeable and too large. Historical duplicate/stage branches remain a cleanup risk. |
| EPSG:31370 / Lambert 72 | STABLE FOUNDATION | Preserve deterministic conversion and authoritative geometry ownership. |
| UrbIS / official data pipeline | STABLE FOUNDATION | Strong Day-1 asset; keep source-first provenance, deterministic municipality fetches and exact source resolution. |
| OSM complementary data | WORKING PROTOTYPE | Use where appropriate for traffic/services; preserve ODbL provenance and do not elevate OSM above authoritative geometry. |
| Godot project health | WORKING | Main CI is healthy; specialist heads require deterministic green tests before extraction. |
| Automated tests / CI | WORKING | Main, ownership, specialist and performance workflows exist; regressions are increasingly captured as explicit tests. |
| Web preview | BUILD WORKING / PUBLICATION PARTIAL | Playable Web export refresh works; public Pages configuration remains separate. |
| Performance baseline | USABLE HEADLESS BASELINE | Use for regression comparison only; add rendered benchmark before visual-performance budgets. |
| Asset/license provenance | PARTIAL | Stronger in mapping/photo-match than project-wide; every production/reference asset still needs traceability. |
| Photo-match validation | REAL BUT EARLY | Three lawful-reference viewpoints and deterministic constraints exist; missing captures/high-impact mismatches remain open. |
| First playable vertical slice | INCOMPLETE | Midi → Grand-Place remains integrated gameplay benchmark; must mature before broad city integration. |
| Branch integration health | RED/AMBER | Small PNJ/performance lots integrate well; geographic and traffic branches are accumulating faster than `main` can absorb. |

## Active workstreams

### 1. Main / integration

Latest completed:
- PR #21 runtime PNJ appearance/transit lifecycle/idle desynchronization integrated cleanly;
- post-merge game CI + test green;
- playable Web output republished automatically.

Highest-priority resume:
- create the next integration package from the **current** `main`, not from an old specialist base;
- first candidate remains a minimal rest-of-Brussels data/runtime-index extraction from #11;
- do not merge #2, #3 or #11 wholesale.

Cross-cutting next lots after branch pressure is reduced:
- rendered performance benchmark;
- `cell_manifest.json` / Brussels Cell Definition of Done;
- vertical-slice QA for collisions, streaming and visual regressions.

### 2. Laeken + Jette — PR #2

- Draft, base `main`.
- Head: `5fd098d168c088cc66ecbe6d207fbc4fc540a04a`.
- 269 commits / 159 changed files.
- Currently non-mergeable.
- Latest specialist work added authoritative constraints/validation for the two missing photo-match cameras instead of inventing viewpoints.
- Three lawful reference viewpoints exist; no hero area is realism-complete.
- Palais 5 remains deliberately blocked because available broad UrbIS geometry is insufficient to claim hall-specific geometry.

Hard gate:
- resolve `atomium_ground_oblique_v1` from official pedestrian surfaces + DTM first;
- generate deterministic matching capture;
- then resolve `heysel_stadium_context_v1`;
- rank high screen-space mismatches before materials polish;
- extract a small current-main package instead of rebasing/merging the 269-commit PR wholesale.

### 3. Rest of Brussels — PR #11

- Draft, base `main`.
- Head: `716d5dc8272d0bab8bf560593e413f3fa90ea43f`.
- 31 commits / 139 changed files / 31,492 additions.
- Currently non-mergeable.
- Ownership remains mapping/data/tooling only in the inspected PR scope; no PNJ/police/traffic/shared-scene contamination observed.
- Ixelles remains at a contiguous five-cell block; expansion was correctly paused for relief/building heights.
- Latest checkpoint resolved the exact official Paradigm UrbIS DSM/DTM 2021 archives for required tiles `149168` and `149169` in EPSG:31370. The generated source records explicitly remain `official_archives_resolved_not_yet_downloaded_or_hashed`.

Hard gate:
- do not add another municipality;
- extract the minimum stable data/runtime-index baseline from current `main` for integration;
- on specialist branch, continue Ixelles by downloading + SHA-256 hashing DSM/DTM archives, validating CRS/resolution/extents, then deriving source-backed terrain/building-height statistics before runtime activation.

### 4. PNJ / police / civilians

Integrated on `main`:
- contextual crossings/stops;
- context-sensitive population budgets;
- deterministic appearance variation;
- runtime appearance hooks;
- transport boarding/alighting lifecycle interface;
- desynchronized ambient idle timing.

Next safe lot:
- ambient animation state machine connected to deterministic idle phases;
- queue/boarding behavior through a narrow external STIB interface;
- then police escalation/de-escalation and crowd reactions without geographic ownership leakage.

### 5. Vehicles & traffic — PR #3

- Draft, base `main`.
- Head: `70c023f83eacd3bdf33bae994c470cf5ac5446f0`.
- 152 commits / 70 changed files.
- Currently non-mergeable.
- Functional value remains high, but parallel `traffic_manager_core`, `core_v2` … `core_v9` generations and shared-scene coupling remain unacceptable Day-1 debt.

Hard gate:
- freeze feature breadth;
- consolidate one canonical traffic runtime;
- prove compatibility with dedicated tests;
- extract a fresh small branch from current `main` and run traffic + main + performance suites before integration.

## Living cross-cutting backlog

Main/integration owns modular foundations that do not yet have a clean specialist lane: missions/gameplay framework, economy/shops/activities interfaces, interiors framework, weather/day-night, spatial audio hooks, UI, save/load, world streaming/LOD/occlusion, collision QA, performance/telemetry and common architecture. None should become another monolithic branch.

Near-term ordering:
1. recover integration throughput;
2. rendered benchmark + cell manifest;
3. strengthen Midi → Grand-Place playable slice;
4. integrate one small geographic package;
5. only then broaden shared gameplay systems.

## Direction / Assistant

### 1. What should be discussed with the user now

No blocking decision is required. The only strategic point worth surfacing is that **integration throughput, not feature generation, is now the Day-1 bottleneck**.

### 2. Recommendation

Freeze breadth on #3 and #11, keep #2 on photo-match evidence, and measure progress by small green packages absorbed by `main`. Preserve Midi → Grand-Place as gameplay benchmark and Atomium/Heysel as realism benchmark until both meet stronger quality gates.

### 3. What can continue autonomously without asking

- small current-main extraction from #11;
- Ixelles DSM/DTM hashing + height derivation on the specialist branch;
- Laeken/Jette deterministic photo captures + mismatch reduction;
- traffic runtime consolidation;
- PNJ ambient animation/queue interfaces;
- provenance, CI and branch-ownership tooling;
- rendered performance benchmark and cell-manifest design.

### 4. Single biggest risk to project success

**High-value specialist work becoming progressively unintegrable before the first vertical slice is convincingly realistic and stable.**

### 5. Next strategic idea worth testing

Implement a mandatory per-500 m `cell_manifest.json` with lifecycle `data_ready` → `playable` → `realism_validated`, recording authoritative sources, CRS validation, terrain/heights, collisions, transit, lawful references, open visual mismatches, streaming cost, performance sample and uncertainty flags.

### 6. One concrete action to improve realism

For each hero screenshot, score mismatches by approximate visible screen area and correct silhouette/landmark alignment, building height/roofline and road/sidewalk/curb proportions before small material polish.

### 7. One concrete action to improve project organization

Adopt an extraction-first rule: any package targeting `main` is recreated from current `main`, contains one ownership domain, avoids `main.tscn` unless integration explicitly owns the change, and stays small enough for deterministic review/tests.

Also schedule branch cleanup once no active work depends on them: old `agent/police-ai-gameplay-stage*`, `integration/performance-baseline*`, `systems-npc-police-civilians-rebased` and historical recovery branches should not remain ambiguous integration candidates indefinitely.

### 8. Maturity assessment

- **Prototype:** broad traffic feature set, advanced police/civilian behavior, most facade/material/weather/audio/interior/economy work, public Pages deployment, rendered performance testing.
- **Stable foundation:** EPSG:31370 convention, UrbIS-first policy, deterministic data tooling, healthy main Godot CI, branch ownership gate, Web export and headless performance regression harness.
- **Production-ready:** nothing yet; no geographic hero area or major gameplay subsystem qualifies on Day 1.

## Branch hygiene alerts

- `zone-laeken-jette` / #2: RED/AMBER — 269 commits, non-mergeable; extract only small current-main packages.
- `vehicles-traffic` / #3: RED — 152 commits, non-mergeable, versioned-core debt; consolidate first.
- `zone-reste-bruxelles-clean` / #11: AMBER/RED — ownership clean, but 31 commits / 139 files and non-mergeable; stop breadth and extract.
- `zone-reste-bruxelles` / historical #4: CLOSED + QUARANTINED — never an integration source.
- Several stale staging/rebased/performance branches remain visible and should be pruned after dependency verification.

## Photo-match status

- Three lawful-reference viewpoints exist for Laeken/Heysel.
- Deterministic capture/provenance gates exist.
- Two cameras remain unresolved rather than invented; authoritative constraints are now encoded for both.
- Major open realism gaps still include provisional camera placement, generic facades/street furniture, remaining fallback building heights and incomplete screenshots.
- Palais 5 remains blocked pending sufficiently fine authoritative geometry.
- No hero area is realism-complete.

## Realism definition of done

A hero area is not complete because footprints exist. Required evidence includes authoritative geometry, terrain/elevation, building heights/rooflines, facade proportions/materials, road/lane/sidewalk/curb dimensions, transit infrastructure, signs/lighting/furniture/vegetation, parking/clutter/weathering, contextual traffic/pedestrians, audio/light/weather context, deterministic lawful-reference screenshot comparison, collision integrity, provenance and a recorded performance budget. Unsupported details remain provisional rather than invented.

## Exact next handoff

1. **Main/integration:** create a fresh branch from current `main` for the smallest rest-of-Brussels data/runtime-index extraction; run ownership + mapping + main CI and integrate only if green.
2. **Rest of Brussels / #11:** no new municipality. Continue Ixelles DSM/DTM download/hash/CRS-resolution validation and derive terrain/building-height statistics after the extraction package is isolated.
3. **Laeken/Jette / #2:** resolve `atomium_ground_oblique_v1`, capture it deterministically, then `heysel_stadium_context_v1`; reduce highest-impact mismatches before extraction.
4. **Vehicles/traffic / #3:** no new features; collapse versioned cores into one canonical runtime before any integration attempt.
5. **PNJ/police/civilians:** proceed to ambient animation state machine + queue/boarding interface, then police/crowd reactions, keeping geographic inputs abstract.
6. **Direction/Assistant:** next review must first check whether a small extraction PR appeared, whether any large PR became mergeable/clean, and whether specialist work continued despite its hard gate.
