# Grand Bruxelles Game — Master Status

Last coordinated review: 2026-08-12 10:38 Europe/Brussels

This is the live Day-1 integration/direction snapshot. `main` plus small current-base extraction PRs define integration truth. Long-lived specialist branches are evidence/workspaces only and are never merge units.

## Current main baseline

- `main`: `bae8b7ba8bc5849515b62a9f968c584ea838ec9d` (`data(ixelles): recover clean UrbIS 3D second-source proof (#57)`).
- Recovered and merged this pass: PR #56 position-aware Brussels location HUD and PR #57 clean Ixelles UrbIS 3D second-source proof.
- Recent foundation integrations also include branch quarantine, rendered performance/visual-regression tooling, Bourse photo-match capture, official Brussels Mobility density evidence, real PNJ crossing runtime and canonical traffic.
- GitHub Web export remains healthy. Public GitHub Pages publication is blocked by repository-side initial Pages activation: the workflow reaches `Configure GitHub Pages`, but the token cannot create the first Pages site (`Resource not accessible by integration`). This is an external repository setting, not a Godot export failure.
- Open long-lived specialist drafts remain PR #2 (Laeken/Jette) and PR #11 (rest of Brussels). Neither is a safe integration unit.

## DAY-1 MATURITY CHECK

| Foundation | State | Day-1 direction |
|---|---|---|
| Repository structure | AMBER | Game folders and domain workflows are clear, but the repository also carries unrelated root content and a very large branch inventory. Keep game ownership path-scoped and integrate only small lots. |
| Branch discipline | RED/AMBER | Quarantine CI is working, but specialist branches continue to diverge rapidly. PR #2 is hundreds of commits away from main; PR #11 is also heavily diverged. Extract only. |
| Authoritative data pipeline | STRONG FOUNDATION | UrbIS-first discovery, hashing, EPSG checks and evidence-only artifacts are working. Ixelles official 3D source is now proven; building-level height approval is still pending. |
| Coordinate system integrity | STABLE FOUNDATION | EPSG:31370 / Belgian Lambert 72 remains authoritative source truth. Local Godot metres must always derive from it. |
| Godot project health | STRONG FOUNDATION | Godot 4.7 main scene loads in CI with canonical traffic, PNJ integration, real rendered checks and Web export. |
| Automated tests | STRONG FOUNDATION | General, domain, integration, branch-hygiene, rendered-performance and photo-match gates are active. City-scale streaming/GPU stress is still missing. |
| Web preview | BUILD GREEN / PUBLICATION BLOCKED | Web export and HTTP servability are green; GitHub Pages needs initial repository activation by an admin/user. |
| Performance baseline | AMBER | Deterministic rendered baseline exists and catches regressions. Real GPU budgets, LOD/streaming and city-scale stress are not production-proven. |
| Asset/license provenance | RED/AMBER | Mapping, source and photo-match metadata are comparatively strong, but `assets/LICENSE_REGISTRY.tsv` is still only a header. Global asset provenance must be enforced before asset volume grows. |
| First playable vertical slice | PLAYABLE PROTOTYPE | Midi → Centre runs with traffic and PNJ crossing systems, but Bourse/centre geometry and many visuals remain visibly placeholder/generic. |
| Branch integration health | RED/AMBER | Small clean PRs integrate well; specialist production still outruns integration and must be continuously extracted/recovered. |

## 1. Main / integration

### Stable enough to build on
- canonical unversioned traffic manager/vehicle runtime with cars, scooters, motorcycles, controls, crossings, parking, deliveries, wreck/tow lifecycle and official-density evidence;
- PNJ population/runtime integration and real traffic crossing bridge;
- branch-quarantine and general CI gates;
- deterministic rendered performance + visual regression baseline;
- repeatable Bourse photo-match capture contract;
- position-aware Brussels location HUD instead of hard-coded Midi presentation state;
- clean official Ixelles UrbIS 3D second-source discovery/inspection pipeline.

### Highest-priority next lot
**Bourse geometry mismatch closure from current `main`.** The capture infrastructure is already done. Do not add another benchmark framework. Audit authoritative Bourse/Place de la Bourse geometry and replace the largest visible generic mismatch first: Palais de la Bourse silhouette/roofline, then frontage massing and street/sidewalk proportions. Keep this a small centre-geometry/visual lot with deterministic before/after capture.

### Do not do yet
- no wholesale specialist-branch merges;
- no new versioned traffic cores;
- no Brussels-wide expansion before cell promotion/evidence is repeatable;
- no claim that a Web build or an UrbIS package alone proves realism/runtime readiness.

## 2. Laeken + Jette — PR #2

- Branch: `zone-laeken-jette`.
- PR: draft, base `main`, non-mergeable.
- Latest measured drift this review: **426 commits ahead / 123 behind `main`**.
- Branch is still ACTIVE: latest observed work is Palais 5 façade/photo-match capture and terrain/light anchoring.
- The branch mixes a very large number of workflows, source inventories, DTM/DSM/orthophoto data, zone scripts, captures and a separate Web build. It is valuable evidence but structurally unsafe as a merge unit.
- Existing strengths include official UrbIS geometry, terrain/height evidence, trees, orthophoto provenance, Atomium tooling, Palais 5 work and deterministic captures.

**Resume next:** continue source-backed Palais 5 / Atomium photo-match discrepancy reduction inside the specialist workspace, but the next integration must be a tiny extraction from current `main`: one hero component/evidence package with no specialist Web build or unrelated workflows.

**Integration rule:** never rebase/merge PR #2 wholesale. Extract one coherent hero/data/runtime lot at a time.

## 3. Rest of Brussels — PR #11 + Ixelles

- Branch: `zone-reste-bruxelles-clean`.
- PR: draft, base `main`, non-mergeable.
- Last measured drift before the current two merges was roughly **90 commits ahead / 85 behind** and has only worsened as `main` advanced.
- Latest observed branch work stopped around Etterbeek/Schaerbeek expansion and workflow cleanup. Do not resume broad municipality expansion from this base.
- Ixelles DTM evidence still supports **2 m** as the current runtime terrain candidate, with finer resolution reserved for hero fallback where justified.
- The interrupted second-source handoff was recovered onto clean PR #57 and merged.

### New official Ixelles 3D evidence
The clean CI proof selected the latest official Ixelles package:
`UrbISBuildings3D_31370_GPKG_21009_20260808.zip`.

Evidence from the green run:
- official package date: `20260808`;
- ZIP SHA-256: `090f4a6aada5c7c19609860d7ee3956ce0f06379c991533975bcf1ddb848dfaa`;
- extracted GeoPackage size: 144,527,360 bytes;
- observed CRS: EPSG:31370 only;
- usable 3D candidate layers: `EngineeringWorkFaces` and `BuildingFaces`;
- `BuildingFaces`: 330,949 features, sampled Z approximately 52.20–95.53 m.

This proves a usable second authoritative 3D source exists. It **does not** yet prove the current per-building height candidates or authorize runtime heights.

**Resume next:** build a current-main, building-level Ixelles comparison tool that spatially matches current building footprints/candidates to `BuildingFaces`, derives ground/roof evidence and uncertainty, reports mismatch/outlier distributions, and only promotes buildings/cells when thresholds are explicit and tested. Then validate the 2 m terrain runtime package for seams, normals, collision and rendered/streaming cost.

## 4. Systems / gameplay

### PNJ / police / civilians
Foundation is integrated: population/runtime coordination, deterministic appearance hooks, local reactions, police response/de-escalation, and real traffic-crossing orchestration are available.

**Next safe lot:** improve pedestrian believability inside the Midi vertical slice: varied walk speeds, curb dwell/pacing, destination recovery and crowd spacing, with deadlock/regression tests. Keep arrest/pursuit work separate from traffic ownership.

### Vehicles / traffic
Canonical traffic remains integration truth. Official Brussels Mobility calibration evidence is integrated. Cars/scooters/motorcycles, routing, controls/right-priority, crossings, time-of-day density, parking, deliveries, disabled/wreck/tow lifecycle are foundation-level systems.

**Next safe lot:** controlled offline evaluation/tuning against official counts/speeds by corridor/time bucket, then small Brussels-specific road-behaviour lots: STIB interactions, parking/garage behaviour, intersections and accident/recovery depth. Do not mix vehicle art, police pursuit and shared-scene changes in one PR.

### Other playable-game backlog
Still prototype/incomplete: mission depth, economy, shops/activities, interiors, garages/repair gameplay, saves, weather/day-night, spatial audio, UI polish, collision coverage, city-wide LOD/streaming and production QA.

Preferred sequence after the current realism/evidence blockers: save + mission-state contract; weather/day-night + Brussels lighting; spatial audio; shops/interiors framework; richer activities/garages; then broader geography under the same cell-readiness contract.

## 5. Direction / Assistant

### 1. What should be discussed with the user now
No gameplay/design decision blocks progress. One optional repository-admin action is worth surfacing: enable the repository's initial GitHub Pages site if a stable public GitHub Pages URL is desired. Development should continue regardless.

### 2. Recommendation
Freeze broad geographic expansion temporarily. Use Day 1 to close three concrete evidence/quality gaps: Bourse visible geometry, Ixelles building-level heights, and one clean Laeken hero extraction. This gives one centre realism gate, one authoritative elevation gate and one specialist-to-main integration pattern.

### 3. What can continue autonomously
- Bourse authoritative geometry/photo-match correction;
- Ixelles per-building 3D height comparison and 2 m terrain runtime gate;
- extraction of one Palais 5/Atomium hero evidence package;
- PNJ movement/crowd realism;
- deterministic traffic calibration and small STIB/intersection/parking lots;
- asset provenance enforcement and branch-inventory cleanup policy.

### 4. Single biggest risk
**Specialist production outpacing integration truth.** PR #2 already demonstrates the failure mode: hundreds of valuable commits can become too mixed and divergent to integrate economically.

### 5. Next strategic idea worth testing
Make the 500 m cell contract a promotion state machine: `candidate → source_verified → runtime_validated → photo_matched → runtime_approved`. Require source hashes, EPSG, terrain/height confidence, collision status, streaming/render budget and reference viewpoints before a cell can be consumed by broad expansion.

### 6. Concrete realism action
At Bourse, replace generic centre massing with source-backed Palais de la Bourse silhouette/roofline and frontage proportions, then rerun the fixed CC0 reference capture. Judge silhouette, building height, street width, sidewalk/curb geometry and major clutter before touching micro-detail.

### 7. Concrete organization action
Add a branch-retention/ownership policy: `main.tscn`, `project.godot`, shared controllers and canonical traffic are integration-owned; specialist branches publish extraction manifests/evidence, not alternate Web builds or shared-main rewrites. Retire merged integration branches after a defined retention period.

### 8. Maturity assessment
- **Prototype:** most visible architecture/materials outside source-backed slices, economy/interiors/activities, weather/audio depth, mission breadth, city-wide streaming, pursuit/accident depth.
- **Stable foundation:** EPSG:31370, UrbIS-first source discovery, evidence hashing, Godot CI/Web export, canonical traffic, PNJ crossing integration, rendered performance regression, photo-match harness, branch quarantine, clean extraction workflow.
- **Production-ready:** nothing yet. No full hero area or subsystem simultaneously passes realism, provenance, performance, gameplay and QA at production level.

## Branch hygiene alerts

- `zone-laeken-jette` / PR #2: **RED** — ~426 ahead / 123 behind, active, non-mergeable, huge mixed branch; extraction only.
- `zone-reste-bruxelles-clean` / PR #11: **RED** — heavily diverged and currently stopped; no new broad work on this base; extraction only.
- historical/versioned traffic and recovery branches: evidence only unless dependency-tested and re-extracted from current `main`.
- branch inventory remains too large for Day 1. Quarantine protects merges but does not replace branch lifecycle/ownership discipline.

## Living master backlog

1. Bourse source-backed silhouette/frontage/street geometry correction + fixed photo-match comparison.
2. Ixelles per-building UrbIS 3D comparison → confidence/outlier gate → only then runtime height approval.
3. Ixelles 2 m terrain runtime package: seams, normals, collisions, streaming/render cost.
4. Extract one source-backed Palais 5/Atomium hero package from the Laeken specialist branch onto current main.
5. PNJ movement/crowd realism and recovery/deadlock tests.
6. Traffic official calibration evaluation, then small STIB/intersection/parking/garage/accident lots.
7. Cell-readiness promotion state machine and evidence manifest.
8. Asset/license registry enforcement before external art volume grows.
9. Save/load + mission-state contract; then weather/day-night + lighting and spatial audio.
10. Shops/activities/interiors/garages framework; Brussels-wide expansion only after the same cell contract is repeatable.

## Exact handoff

- Integration head at this review: `bae8b7ba8bc5849515b62a9f968c584ea838ec9d`.
- Merged during this coordination pass: PR #56 (`a09ca1cb...`) and PR #57 (`bae8b7ba...`).
- PR #56 resolved the global hard-coded Midi HUD contamination seen in the Bourse capture; Bourse geometry blockers remain open.
- PR #57 proved the current official Ixelles EPSG:31370 3D GeoPackage and real Z layers but deliberately did not approve runtime heights.
- Public Pages blocker: initial GitHub Pages site is not enabled and Actions cannot create it with the current token permissions; Web export itself is healthy.
- Open unsafe specialist drafts: PR #2 Laeken/Jette and PR #11 rest of Brussels; both extraction-only.
- Exact next coordinator action: create a small current-main Bourse geometry/photo-match correction lot unless a newly stopped clean handoff appears first.
- Rest Brussels next: building-level Ixelles `BuildingFaces` comparison, then 2 m terrain runtime validation.
- Laeken/Jette next: continue Palais 5/Atomium photo-match work, but integrate only one clean hero/evidence extraction.
- Systems next: PNJ pacing/recovery realism and separately traffic calibration/STIB-intersection realism.
