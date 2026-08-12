# Grand Bruxelles Game — Master Status

Last coordinated review: 2026-08-12 04:20 Europe/Brussels

This is the live Day-1 integration/direction snapshot. Specialist documentation remains authoritative for implementation details; this file defines current gates, integration order and recovery priorities.

## Current main baseline

- `main`: `d412c96d33c435bb0158d2eddffc6eeb5fcd255f` after automatic `web-preview` republish.
- Contextual pedestrian behavior, contextual population budgets and deterministic appearance variation are integrated on `main`.
- Police vehicle component baseline is integrated on `main`.
- Reproducible performance harness is integrated and the wall-clock refinement has been merged; the usable headless reference is about 6.90 ms/frame average, 7.22 ms p95, ~145 FPS estimated and ~58.4 MiB static memory. Headless render counters are not treated as production budgets.
- Main `Grand Bruxelles Game CI` and playable Web build are green on the latest gameplay merge; the bot republish that followed changes only `web-preview` outputs.
- Public GitHub Pages availability remains a deployment/configuration concern separate from game correctness.

## Day-1 maturity check

| Area | State | Direction |
|---|---|---|
| Repository structure | WORKING FOUNDATION | Keep the project under `grand-bruxelles-game/`; integrate specialist work only through small extraction packages. |
| Branch discipline | ACTIVE REPAIR | Ownership gate works, but #2/#3/#11 are now too large or non-mergeable. PR #4 is closed/quarantined. |
| EPSG:31370 / Lambert 72 | STABLE FOUNDATION | Preserve deterministic conversion and authoritative geometry ownership. |
| UrbIS / official data pipeline | STABLE FOUNDATION | Strong Day-1 asset; keep source-first provenance and deterministic fetches. |
| OSM complementary data | WORKING PROTOTYPE | Use for traffic/services where appropriate; preserve ODbL provenance. |
| Godot project health | WORKING | Main CI is healthy; specialist heads require green deterministic tests before extraction. |
| Automated tests / CI | WORKING | Main, ownership, specialist and performance workflows exist; keep turning regressions into tests. |
| Web preview | BUILD WORKING / PUBLICATION PARTIAL | Build refresh is green; public Pages remains configuration-dependent. |
| Performance baseline | USABLE HEADLESS BASELINE | Wall-clock average/p95 + memory are usable for regression comparison; real rendered budgets still require non-headless capture. |
| Asset/license provenance | PARTIAL | Provenance exists in several pipelines but is not yet complete project-wide. |
| Photo-match validation | REAL BUT EARLY | Laeken/Jette has lawful-reference gates; obvious mismatches and missing captures remain blockers. |
| First playable vertical slice | INCOMPLETE | Midi → Grand-Place remains the integrated gameplay benchmark and must mature before broad integration. |
| Branch integration health | RED/AMBER | Small PNJ/performance lots integrate well; geographic/traffic branches still accumulate faster than main can absorb. |

## Active workstreams

### 1. Main / integration

Completed since the previous status:
- wall-clock performance refinement integrated;
- contextual PNJ population/appearance lot integrated after fixing the enum compile regression;
- main CI and Web export passed after that integration;
- historical contaminated rest-of-Brussels PR #4 closed and explicitly quarantined.

Next gate:
- do not merge any current large specialist PR wholesale;
- require a small extraction package from current `main` for the next integration;
- highest-value candidate is a minimal data-only rest-of-Brussels baseline, followed by a similarly small Laeken/Jette zone package.

### 2. Laeken + Jette — PR #2

- Draft, base `main`.
- Head: `e65390294edbed59053042ff2e4c5ef5b00f42dd`.
- 267 commits / 159 changed files.
- Currently non-mergeable as a whole.
- Valuable current work includes UrbIS geometry, terrain/heights, three-view photo-match framework and explicit mismatch tracking.
- Palais 5 remains deliberately unresolved because the broad UrbIS polygon is not precise enough to claim hall-specific geometry.

Hard gate:
- no additional integration breadth until the missing deterministic hero captures are finished;
- rank photo-match mismatches by screen-space impact;
- then create a fresh small extraction branch from current `main` containing only the stable Laeken/Jette package needed for integration.

### 3. Rest of Brussels — PR #11

- Draft, base `main`.
- Head: `259dde7949f2cf13478b2e1a53050327d7d8adf1`.
- 23 commits / 130 changed files / ~30.9k additions.
- Currently non-mergeable.
- Ownership remains mapping/data/tooling only; no shared gameplay contamination observed in the declared scope.
- Ixelles has progressed to a contiguous five-cell source-backed block and the UrbIS boundary fetch was made deterministic by removing volatile GeoServer transport IDs only.

Hard gate:
- stop adding new municipality breadth to this PR;
- extract the smallest useful data-only baseline from current `main` rather than repairing all 23 commits in-place;
- after integration, resume Ixelles with relief + building-height coverage before further geographic expansion.

### 4. PNJ / police / civilians

- Contextual crossing/stop behavior integrated.
- Context-sensitive population budgets integrated.
- Deterministic appearance variation integrated after regression fix.

Next safe lot:
- runtime application of appearance profiles to agents;
- boarding/alighting lifecycle and de-synchronized idle/crowd timing;
- keep map-specific density inputs behind narrow interfaces and do not couple to geographic branch ownership.

### 5. Vehicles & traffic — PR #3

- Draft, base `main`.
- Head: `70c023f83eacd3bdf33bae994c470cf5ac5446f0`.
- 152 commits / 70 changed files.
- Currently non-mergeable.
- Functional value is high, but parallel `traffic_manager_core`, `core_v2`…`core_v9` generations and shared-scene coupling remain unacceptable Day-1 debt.

Hard gate:
- freeze feature breadth;
- consolidate one canonical traffic runtime;
- keep only compatibility code proved necessary by tests;
- extract a fresh small branch from current `main`, then run traffic + main + performance suites before integration.

## Cross-cutting backlog ownership

Main/integration owns modular foundations that currently have no clean dedicated branch: missions/gameplay framework, economy/shops/activity interfaces, interiors framework, weather/day-night, spatial audio hooks, UI, save/load, streaming/LOD, performance and QA. These must remain interface-first and should not be allowed to grow into another monolithic branch.

## Direction / Assistant

### What should be discussed with the user now

No blocking decision is required. The only strategic point worth surfacing is that specialist branches are still expanding faster than integration capacity, so visible progress should now be measured by validated playable quality rather than commit count or map coverage.

### Recommendation

1. Freeze breadth on #3 and #11 until each produces a small extraction package.
2. Keep #2 focused on photo-match evidence and extract only after hero-view gates are credible.
3. Use the headless performance baseline for regression detection but establish a rendered benchmark before setting visual-performance budgets.
4. Keep Midi → Grand-Place as the gameplay vertical slice and Atomium/Heysel as the visual-realism benchmark.
5. Implement the machine-readable Brussels Cell Definition of Done before broad municipality expansion resumes.

### What can continue autonomously

- clean extraction of mapping data from #11;
- Laeken/Jette photo-match mismatch reduction;
- traffic core consolidation;
- PNJ runtime appearance/boarding/idles behind clean interfaces;
- provenance, branch-ownership and QA tooling;
- rendered performance benchmark design.

### Single biggest risk

**Valuable specialist work becoming practically unintegrable before the first vertical slice reaches convincing quality.** This would create large apparent coverage while realism, performance and regression control remain weak.

### Next strategic idea worth testing

Introduce a mandatory `cell_manifest.json` schema for each 500 m Brussels cell with stages `data_ready`, `playable`, `realism_validated`. Track authoritative sources, coordinate validation, terrain/height coverage, collisions, photo-match references and open mismatches, streaming cost, performance sample IDs and uncertainty flags.

### One concrete realism action

For hero viewpoints, score mismatches by approximate screen-space impact and fix silhouette/landmark alignment, rooflines/heights and street/sidewalk proportions before small material polish.

### One concrete organization action

Adopt an extraction-first integration rule: specialist branches may be long-lived, but any package targeting `main` should normally be recreated from current `main`, contain one coherent ownership domain, avoid shared `main.tscn` changes unless integration owns them, and remain small enough to review/test independently.

### Maturity assessment

- **Prototype:** broad traffic feature set, advanced police/civilian behavior, most facades/material/weather/audio/interior/economy systems, public Pages deployment and rendered performance testing.
- **Stable foundation:** EPSG:31370 convention, UrbIS-first policy, deterministic data tooling, main Godot health, ownership checks, baseline CI, Web export and headless performance regression harness.
- **Production-ready:** nothing yet. No area or subsystem should be labelled production-ready on Day 1.

## Branch hygiene alerts

- `zone-laeken-jette` / #2: RED/AMBER — 267 commits, non-mergeable; extract clean packages only.
- `vehicles-traffic` / #3: RED — 152 commits, non-mergeable, versioned-core debt; consolidation required.
- `zone-reste-bruxelles-clean` / #11: AMBER/RED — ownership is clean but scope grew to 23 commits / 130 files and is non-mergeable; stop breadth and extract.
- `zone-reste-bruxelles` / #4: CLOSED + QUARANTINED — audit/recovery only, never an integration source.
- PNJ lots: integrated successfully; future lots must remain narrow.

## Photo-match status

- Three lawful-reference viewpoints exist in the Laeken/Heysel benchmark framework.
- Deterministic capture/provenance gates exist.
- Obvious mismatches remain open, including provisional camera constraints, generic facades/street furniture, remaining fallback building heights and incomplete captures.
- Palais 5 geometry is explicitly blocked pending sufficiently fine authoritative geometry; this is preferable to accepting a false match.
- No hero area is realism-complete.

## Realism definition of done

A hero area is not complete because footprints exist. Required evidence includes authoritative geometry, terrain/elevation, building heights/rooflines, facade proportions/materials, road/lane/sidewalk/curb dimensions, transit infrastructure, signs/lighting/furniture/vegetation, parking/clutter/weathering, contextual traffic/pedestrians, audio/light/weather context, deterministic lawful-reference screenshot comparison, collision integrity, provenance and a recorded performance budget. Unsupported details remain provisional rather than invented.

## Exact next handoff

1. `zone-reste-bruxelles-clean` / #11: create a fresh current-main extraction containing the minimum stable authoritative data/runtime-index baseline; run ownership, mapping and main CI; integrate only if green. Do not add another municipality first.
2. `zone-laeken-jette` / #2: finish the missing deterministic photo-match captures and highest-impact mismatch audit; then create a small current-main extraction package.
3. `vehicles-traffic` / #3: no new features; collapse the versioned cores into one canonical runtime and prove compatibility with dedicated tests before extraction.
4. PNJ/police/civilians: continue runtime appearance + boarding/alighting + idle desynchronization behind clean interfaces only after main remains green.
5. Main/integration: design a rendered performance benchmark and `cell_manifest.json` schema while avoiding new shared-scene coupling.
