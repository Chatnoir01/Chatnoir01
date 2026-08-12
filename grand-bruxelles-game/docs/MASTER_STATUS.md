# Grand Bruxelles Game — Master Status

Last coordinated review: 2026-08-12 Europe/Brussels

`main` plus small branches created from the exact current `main` define integration truth. Long-lived specialist branches are evidence/workspaces only; never merge them wholesale.

## Current main baseline

- Current integrated `main`: `b3d7dc1587fdad3ff5e0e34adbd781fe2738bad1` (`web: publish playable Grand Bruxelles build [skip ci]`) after merged PR #93.
- Recent clean integrations now include:
  - #82 hardened transactional multi-domain save coordinator;
  - #83 required Bourse hero footprint preserved in the 140-building playable budget;
  - #84 machine-readable Bourse hero evidence/runtime-approval contract;
  - #86 live Ixelles UrbIS 3D `BuildingFaces` schema profiling;
  - #87 authoritative Bourse UrbIS 3D LoD2 silhouette, 645 semantic faces / 1,818 triangles / 40.1553 m source-backed vertical extent;
  - #89 deterministic civilian walking-pace variation consumed by runtime;
  - #92 mathematically correct horizontal-to-vertical Bourse photo-match FOV conversion;
  - #93 contextual Bourse streetscape detail zone enabling the existing sidewalk/facade-context pass around Place de la Bourse.
- Open long-lived specialist drafts: #2 Laeken/Jette and #11 rest of Brussels. Both are extraction-only and currently non-mergeable.
- Web export and automatic publication are healthy.

## DAY-1 MATURITY CHECK

| Foundation | State | Day-1 direction |
|---|---|---|
| Repository structure | AMBER | Domain folders/workflows are usable; branch inventory and repository-root history remain large. |
| Branch discipline | RED/AMBER | New integration lots are small/current-main and strongly gated. Specialist branches remain too large and divergent. |
| Authoritative data pipeline | STRONG FOUNDATION | UrbIS-first discovery, source hashing, EPSG validation, DSM/DTM evidence, official UrbIS 3D hero extraction and Ixelles 3D schema proof exist. |
| Coordinate integrity | STABLE FOUNDATION | EPSG:31370 / Belgian Lambert 72 remains source truth; local Godot metres derive from it. |
| Godot project health | STRONG FOUNDATION | Godot 4.7.1 main scene, traffic, PNJ, saves, rendered QA and Web export function in CI. |
| Automated tests | STRONG FOUNDATION | General, domain, PNJ, traffic, save, branch-hygiene, provenance, performance, photo-match and Bourse detail gates are active. City-scale stress remains missing. |
| Web preview | GREEN | Automatic playable Web publication runs after integrations. |
| Performance baseline | AMBER | Deterministic regression exists; real GPU, LOD/streaming and whole-city budgets are not proven. |
| Asset/license provenance | STABLE FOUNDATION | Binary asset provenance is gated; many visible assets remain prototype quality. |
| First playable vertical slice | PLAYABLE PROTOTYPE | Midi→Centre is playable with traffic, PNJ, mission/save foundations and a source-backed Bourse hero, but Centre realism is not complete. |
| Branch integration health | RED/AMBER | Small PRs integrate well; specialist production still outruns clean extraction. |

## Branch hygiene alerts

### PR #2 — `zone-laeken-jette`
- draft, base `main`, currently non-mergeable;
- 519 commits / 209 changed files in the PR snapshot;
- valuable Atomium/Heysel/Palais 5/Jette geometry, terrain, photo-match and provenance work;
- **workspace/evidence store only**: never merge or rebase wholesale. Extract one source-backed hero/data/runtime lot onto a fresh current-main branch.

### PR #11 — `zone-reste-bruxelles-clean`
- draft, base `main`, currently non-mergeable;
- 112 commits / 502 changed files in the PR snapshot;
- useful Ixelles/terrain/municipality evidence, but far too broad for an integration unit;
- **workspace/evidence store only**: do not resume broad Brussels expansion on this base.

## 1. Main / integration

Stable enough to build on:
- canonical traffic manager and vehicle runtime;
- PNJ population/crossing/recovery foundations;
- police de-escalation/custody/foot-patrol foundations;
- mission state + atomic/versioned saves + transactional multi-domain coordinator;
- branch quarantine/current-main gates;
- asset provenance gate;
- deterministic rendered performance and photo-match QA;
- official UrbIS 3D Bourse hero extraction/runtime path;
- official Ixelles UrbIS 3D schema evidence.

The next integration priority is visual/source truth rather than another generic framework layer.

## 2. Centre / Bourse

Completed evidence/runtime improvements:
1. real Bourse footprint retained in the playable compact slice (#83);
2. component-level runtime-approval evidence gate (#84);
3. official UrbIS 3D LoD2 hero silhouette/roof/height in runtime (#87);
4. corrected photo-match FOV axis (#92);
5. contextual sidewalks/facade-window/shopfront detail enabled around Bourse (#93).

Open photo-match blockers remain:
- surrounding frontage/building rhythm is still generic/provisional;
- forecourt, street width and curb/sidewalk proportions are not yet authoritatively validated;
- Bourse facade articulation, columns/openings and materials remain generic;
- neighboring massing/materials/clutter still need Brussels-specific evidence;
- final camera pose and eleven-dimension scoring remain pending.

**Precise next Centre lot:** measure/validate immediate Place de la Bourse forecourt + street + sidewalk geometry from authoritative UrbIS/orthophoto evidence, correct one major mismatch only, then rerender the exact fixed photo-match viewpoint. Do not broaden Centre coverage first.

## 3. Laeken + Jette

PR #2 remains extraction-only. Next integration should be one tiny current-main hero package (Atomium ground-oblique or Palais 5) containing provenance, one bounded source-backed component, deterministic test and repeatable capture. Do not import its standalone Web pipeline or branch history.

## 4. Rest of Brussels / Ixelles

#86 proved the live official `BuildingFaces` schema without inventing semantics. Next safe lot:
- use observed stable identifiers or explicit spatial matching to compare one Ixelles cell against corrected DSM-DTM building-height candidates;
- derive ground/roof evidence, uncertainty and outliers;
- approve only proven heights; uncertain cases remain `runtime_approved=false`.

Then validate the 2 m DTM terrain candidate for the same cells: seams, normals, collisions, visual quality, render and streaming cost. Keep 1 m only as justified hero/photo-match fallback.

## 5. PNJ / police / civilians

Stable foundation includes exact routine recovery, daily-schedule recovery and deterministic civilian pace variation consumed by runtime. Next realism lot: bounded curb dwell/re-evaluation at crossings without weakening traffic safe-gap ownership, then crowd spacing/avoidance and deadlock recovery.

## 6. Vehicles / traffic

Core cars/scooters/routing/crossings/priority/density/parking/collision metadata are foundations. Next safe lot remains offline corridor/time-bucket calibration against official Brussels Mobility evidence, then separate STIB/intersection/parking-garage/accident-recovery lots.

## 7. Gameplay / economy / interiors / environment

Stable foundations: first Midi→Centre mission, mission state, atomic save store, mission-save coordinator and transactional multi-domain game-state coordinator.

Still prototype/missing: save UI/autosave/checkpoint policy, richer mission chains, economy, shops, activities, garages, interiors, weather/day-night, Brussels lighting, spatial audio, UI polish, broad collision coverage and city-wide streaming/LOD.

Do not let these systems displace the current Bourse visual/source blocker.

## 8. Direction / Assistant

1. **Discuss with user now:** no gameplay decision blocks progress.
2. **Recommendation:** hold the expansion freeze and convert the Bourse photo-match from monument-only correctness to correct immediate urban proportions.
3. **Can continue autonomously:** Bourse forecourt/street evidence, Ixelles per-building validation, one Laeken hero extraction, PNJ curb dwell, traffic calibration and cell-readiness tooling.
4. **Single biggest risk:** long-lived specialist workspaces accumulating hundreds of commits/files faster than current-main extraction can absorb them.
5. **Strategic idea worth testing:** enforce geographic promotion `candidate → source_verified → runtime_validated → photo_matched → runtime_approved`; only promoted cells/heroes count as completed coverage.
6. **Concrete realism action:** validate Place de la Bourse forecourt, carriageway and sidewalk dimensions from authoritative geometry, correct the largest mismatch, then rerender the fixed reference.
7. **Concrete organization action:** treat quarantined specialist branches as immutable evidence stores for integration purposes; every new deliverable starts from current `main` and owns one narrow component/cell.
8. **Maturity:** prototype = visible art, broad gameplay depth, interiors/economy/weather/audio, streaming and most city coverage. Stable = coordinates, source pipeline, CI, traffic core, PNJ core, save core, provenance, performance/photo-match and Bourse LoD2. Production-ready = nothing yet.

## Living master backlog

1. Bourse authoritative forecourt/street/sidewalk geometry + exact photo-match rerender.
2. Bourse frontage/façade articulation/materials after geometry proportions are validated.
3. Ixelles per-building UrbIS 3D cross-check → confidence/outlier gate → selective runtime height approval.
4. Ixelles 2 m terrain runtime validation: seams, normals, collisions, streaming/render cost.
5. Extract one current-main Atomium/Palais 5 hero package from Laeken evidence.
6. PNJ curb dwell/re-evaluation, crowd spacing and deadlock recovery.
7. Traffic official calibration, then STIB/intersection/parking-garage/accident lots.
8. Cell-readiness promotion state machine and hero-anchor coverage contract.
9. Weather/day-night + Brussels lighting and spatial audio.
10. Shops/activities/interiors/garages framework; Brussels-wide expansion only after repeatable cell promotion.

## Exact handoff

- Current `main`: `b3d7dc1587fdad3ff5e0e34adbd781fe2738bad1` after automatic Web publication following merged #93.
- #93 complete: Bourse now receives the existing contextual sidewalk/facade detail pass inside a bounded 180 m zone; dedicated Bourse Context Detail, Branch Hygiene, Game CI, general tests, Photo Match QA and Performance Baseline were green before merge.
- Bourse `realism_complete=false`; the remaining blocker is authoritative surrounding frontage/forecourt/street proportions plus final camera alignment.
- Open quarantined specialists: #2 and #11, both draft/non-mergeable/extraction-only.
- Precise next coordinator action: create one small current-main Centre branch that records authoritative forecourt/street/sidewalk evidence around the Bourse, adds a deterministic regression for the selected dimension, changes only the proven geometry, and reruns the exact photo-match viewpoint before any broader expansion.
