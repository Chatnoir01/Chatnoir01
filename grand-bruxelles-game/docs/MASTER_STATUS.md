# Grand Bruxelles Game — Master Status

Last coordinated review: 2026-08-12 13:25 Europe/Brussels

`main` plus small current-base extraction PRs define integration truth. Long-lived specialist branches are evidence/workspaces only and are never merge units.

## Current main baseline

- `main`: `abf7d9546a7c19d4aa43e4ea3fc0e289b5d6ee2c` (`web: publish playable Grand Bruxelles build [skip ci]`) after clean merge #76.
- Newly completed since the previous snapshot:
  - #74 live civilian routine restoration after incidents, including transit queue ownership recovery;
  - #75 versioned Midi → Centre mission state export/restore contract;
  - #76 versioned JSON persistence store with integrity validation, rollback-safe promotion, size limits and dedicated CI coverage.
- #76 was merged only after Branch Hygiene, Game CI, general tests, Photo Match QA and Performance Baseline were green.
- Web export remains healthy; public GitHub Pages still needs initial repository-side activation if that URL is desired.
- Open long-lived specialist drafts: #2 Laeken/Jette and #11 rest of Brussels. Both remain extraction-only and non-mergeable.

## DAY-1 MATURITY CHECK

| Foundation | State | Day-1 direction |
|---|---|---|
| Repository structure | AMBER | Domain folders/workflows are usable, but branch inventory and unrelated repository-root history remain large. Keep integration path-scoped and small. |
| Branch discipline | RED/AMBER | Current-main integration lots are strongly gated. Specialist branches still grow too quickly and must never become merge units. |
| Authoritative data pipeline | STRONG FOUNDATION | UrbIS-first discovery, source hashing, EPSG validation, DTM/DSM evidence and official Ixelles 3D proof exist. Per-building approval remains pending. |
| Coordinate system integrity | STABLE FOUNDATION | EPSG:31370 / Belgian Lambert 72 remains authoritative source truth; local Godot metres derive from it. |
| Godot project health | STRONG FOUNDATION | Godot 4.7 main scene, canonical traffic, PNJ runtime, rendered checks and Web export function in CI. |
| Automated tests | STRONG FOUNDATION | General, domain, NPC, traffic, branch-hygiene, provenance, save integrity, rendered-performance and photo-match gates are active. City-scale stress remains missing. |
| Web preview | BUILD GREEN / PUBLICATION SETTING BLOCKER | Build works; initial Pages activation is external repository configuration. |
| Performance baseline | AMBER | Deterministic rendered regression exists, but real GPU budgets, streaming/LOD and city-scale load are not production-proven. |
| Asset/license provenance | STABLE FOUNDATION | Existing binary assets are registered and unregistered binary assets are rejected in CI. The art library is still mostly placeholder-level. |
| First playable vertical slice | PLAYABLE PROTOTYPE | Midi → Centre runs with traffic, PNJ and a mission. Save foundations now exist, but Bourse/Centre remains visibly generic and fails realism completion. |
| Branch integration health | RED/AMBER | Clean lots integrate well; specialist production still outruns integration truth. |

## Branch hygiene alerts

### PR #2 — `zone-laeken-jette`
- draft, base `main`, non-mergeable;
- current repository snapshot: **470 commits / 205 changed files**;
- valuable Atomium/Heysel/Palais 5/Jette source-backed work exists, but the branch is far too large to merge economically;
- **never merge/rebase wholesale**. Extract one source-backed hero/data/runtime lot onto current `main`.

### PR #11 — `zone-reste-bruxelles-clean`
- draft, base `main`, non-mergeable;
- current repository snapshot: **106 commits / 463 changed files**;
- broad municipality expansion has continued beyond the Day-1 freeze and now materially raises recovery cost;
- **do not add more broad geography on this base**. Treat it as an evidence store and extract only small current-main Ixelles/cell contracts.

## 1. Main / integration

### Stable enough to build on
- canonical traffic manager/vehicle runtime and official Brussels Mobility density evidence;
- PNJ population/crossing integration;
- police response/de-escalation/custody/patrol foundations;
- civilian post-incident recovery with exact walking/ambient/transit routine restoration;
- branch quarantine and strict current-main gate;
- asset provenance gate;
- deterministic rendered performance/visual regression;
- Bourse/Atomium/Miroir photo-match registry and serious-mismatch evidence gate;
- official Ixelles UrbIS 3D second-source discovery;
- mission state snapshot contract + durable versioned persistence store.

### Re-evaluated highest priority
The interrupted PNJ handoff is complete (#74) and the save foundation advanced through #75/#76. The highest-value blocker is now **Bourse source-backed geometry/photo-match**.

A new structural finding changes the first Bourse step: the committed OSM runtime slice is generated with a global `--max-buildings 140` selection, and `osm_city_builder.gd` only adds facade detail within 300 m of the Midi anchor. Bourse-area buildings are present in the slice, but they are largely generic extrusions/default heights and there is no Centre-specific authoritative runtime layer equivalent to `UrbISMidiExact`.

**Do not solve this by adding hand-authored generic decoration.** First identify the Palais de la Bourse footprint/massing from authoritative UrbIS/UrbIS 3D evidence, verify current slice coverage/height mismatch, then integrate one small source-backed landmark/forecourt lot and rerun the fixed CC0 capture.

Also add a regression/selection contract so future compact runtime slices cannot silently starve a hero anchor under a global building cap.

## 2. Laeken + Jette

Continue specialist source-backed photo-match discrepancy reduction only where it creates extractable evidence. Prioritize one hero component: Palais 5 or Atomium ground-oblique. Do not add another specialist Web pipeline or broad unrelated workflow.

**Next integration:** one tiny current-main extraction containing source/provenance + one hero component + deterministic test/capture.

## 3. Rest of Brussels / Ixelles

The broad specialist branch is quarantined and should no longer drive expansion sequencing.

**Next safe lot from current `main`:** spatially match current Ixelles building candidates to official UrbIS 3D `BuildingFaces`, derive ground/roof evidence + uncertainty, publish mismatch/outlier distributions, and only then promote reliable buildings/cells. Keep `runtime_approved=false` until thresholds and tests pass.

Then generate/validate the 2 m DTM terrain package for the same cells: seams, normals, collisions, rendered cost and streaming cost. 1 m remains a hero fallback only when photo-match proves it necessary.

## 4. PNJ / police / civilians

Completed foundation:
- crowd response + memory;
- police response/de-escalation/custody;
- foot-patrol planning and live patrol runtime;
- civilian gradual recovery and precise walking/ambient/transit routine restoration.

**Next safe PNJ lot:** inspect `NpcDailySchedule` and add a dedicated red regression proving a civilian interrupted during a scheduled ambient/shop/leisure/work phase resumes the exact scheduled activity contract. Do not create shop/map ownership in the NPC branch. Keep transit BOARDING/vehicle-capacity restoration separate because it requires live vehicle ownership.

Then proceed to varied pedestrian speeds, curb dwell/pacing, crowd spacing and deadlock recovery.

## 5. Vehicles / traffic / gameplay

Traffic foundation includes cars, scooters/motorcycles, routing, crossings, right-priority, parking, deliveries and wreck/tow lifecycle plus official-density evidence.

**Next traffic lot:** offline corridor/time-bucket evaluation against official Brussels Mobility evidence; then separate small lots for STIB road interaction, intersection behavior, parking/garage behavior and accident/recovery depth.

Gameplay persistence advanced materially:
- #75 mission state can export/restore a versioned snapshot;
- #76 provides durable JSON persistence with integrity/rollback protections;
- **next gameplay save lot:** bind the mission snapshot to the persistence store end-to-end with a restart/restore smoke test. Keep global multi-system save orchestration for a later contract.

Still prototype/incomplete: economy, shops/activities, interiors, garages/repair gameplay, weather/day-night, Brussels lighting, spatial audio, UI polish, broad collision coverage and city-wide streaming/LOD.

## 6. Direction / Assistant

1. **Discuss with user now:** no gameplay/design decision blocks progress. Optional only: activate the initial GitHub Pages site if a stable public GitHub Pages URL is wanted.
2. **Recommendation:** keep broad expansion frozen. Make Bourse the main visual truth test now that PNJ recovery and save foundations have moved forward.
3. **Can continue autonomously:** Bourse authoritative geometry/photo-match, Ixelles per-building 3D comparison, one Laeken hero extraction, scheduled-activity PNJ recovery, traffic calibration, end-to-end mission persistence, cell readiness and branch cleanup.
4. **Single biggest risk:** specialist production outpacing integration truth. PR #2 at 470 commits and PR #11 at 463 changed files make future extraction increasingly expensive.
5. **Strategic idea worth testing:** hero-anchor-aware compact slice promotion: runtime selection must guarantee minimum source-verified coverage around every declared hero viewpoint before global budget filling, then feed the existing 500 m cell state machine `candidate → source_verified → runtime_validated → photo_matched → runtime_approved`.
6. **Concrete realism action:** identify and import source-backed Palais de la Bourse footprint/height/roofline evidence, then rerun the fixed CC0 camera before adding micro-detail.
7. **Concrete organization action:** add a deterministic runtime-slice coverage test reporting per-anchor buildings/roads/source status; fail if a hero anchor becomes under-covered because of global caps.
8. **Maturity:** prototype = visible art outside source-backed slices, broad gameplay, interiors/economy/weather/audio, city streaming. Stable foundation = coordinates, source pipeline, CI, traffic runtime, PNJ core, save primitives, photo-match, performance regression, provenance, extraction workflow. Production-ready = nothing yet.

## Living master backlog

1. Bourse authoritative footprint/height/roofline audit + current-runtime coverage diagnosis; then one source-backed landmark/forecourt correction and fixed photo-match capture.
2. Add hero-anchor-aware runtime-slice coverage regression so compact budgets cannot silently erase a benchmark area.
3. Ixelles per-building UrbIS 3D comparison → confidence/outlier gate → runtime height approval only for proven cases.
4. Ixelles 2 m terrain runtime package: seams, normals, collisions, streaming/render cost.
5. Extract one source-backed Palais 5/Atomium hero package from Laeken onto current main.
6. PNJ `NpcDailySchedule` scheduled-activity interruption/recovery regression and wiring.
7. Traffic official calibration evaluation, then STIB/intersection/parking/garage/accident lots.
8. Bind mission state snapshot to the versioned persistence store with restart/restore smoke coverage.
9. Cell-readiness promotion state machine + hero-anchor source coverage manifest.
10. Weather/day-night + Brussels lighting → spatial audio → shops/activities/interiors/garages; Brussels-wide expansion only after repeatable cell promotion.

## Exact handoff

- Current integration truth before this docs lot: `abf7d9546a7c19d4aa43e4ea3fc0e289b5d6ee2c`, automatic Web publication after merged #76.
- #74 merged exact live civilian routine recovery, including re-acquisition of lost transit stop→door ownership through the existing transit interface.
- #75 merged the versioned Midi → Centre mission export/restore contract.
- #76 merged a versioned JSON persistence store after Branch Hygiene, Game CI, general test, Photo Match QA and Performance Baseline all passed; merge commit `f7f9956154362fc39ce4d5bea33b203611a856b0`.
- Open unsafe drafts: #2 and #11; both base `main`, draft, non-mergeable and extraction-only.
- PR #2: 470 commits / 205 changed files. PR #11: 106 commits / 463 changed files.
- Bourse photo-match remains RED: no recognizable source-faithful Palais silhouette and current Centre frontage is generic.
- New Bourse structural finding: compact OSM generation globally limits buildings to 140 and runtime facade detail is Midi-only; Bourse neighborhood geometry exists but lacks a Centre-specific authoritative source-backed rendering layer.
- Exact next coordinator action: start a fresh current-main Bourse evidence lot that identifies authoritative UrbIS/UrbIS3D Palais geometry and adds a deterministic hero-anchor coverage regression before any cosmetic geometry patch. If a newer clean interrupted handoff appears first, recover it before starting that lot.
