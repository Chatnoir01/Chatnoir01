# Grand Bruxelles Game — Master Status

Last coordinated review: 2026-08-12 12:30 Europe/Brussels

`main` plus small current-base extraction PRs define integration truth. Long-lived specialist branches are evidence/workspaces only and are never merge units.

## Current main baseline

- `main`: `ffcb4dea30ab0108c6eb1b19f92a7072c06a9acc` (`web: publish playable Grand Bruxelles build [skip ci]`), automatically published immediately after #71.
- Recent clean integrations since the previous master snapshot:
  - #67 asset provenance coverage + CI gate;
  - #68 live police foot-patrol runtime consumption;
  - #70 evidence required before resolved major/blocker photo-match mismatches can be cleared;
  - #71 immutable pre-incident civilian routine snapshot contract, produced by a deliberate red→green NPC realism regression.
- Web export remains healthy; public GitHub Pages still needs initial repository-side activation if that public URL is desired.
- Open long-lived specialist drafts: #2 Laeken/Jette and #11 rest of Brussels. Both are extraction-only.

## DAY-1 MATURITY CHECK

| Foundation | State | Day-1 direction |
|---|---|---|
| Repository structure | AMBER | Domain folders/workflows are usable, but branch inventory and unrelated repository-root history remain large. Keep integration path-scoped. |
| Branch discipline | RED/AMBER | Small integration lots are now strongly gated. Specialist work continues to diverge too fast and must not be merged wholesale. |
| Authoritative data pipeline | STRONG FOUNDATION | UrbIS-first discovery, source hashing, EPSG validation, DTM/DSM evidence and official Ixelles 3D proof exist. Per-building approval is still pending. |
| Coordinate system integrity | STABLE FOUNDATION | EPSG:31370 / Belgian Lambert 72 remains authoritative source truth; local Godot metres derive from it. |
| Godot project health | STRONG FOUNDATION | Godot 4.7 main scene, canonical traffic, PNJ runtime, rendered checks and Web export are functioning in CI. |
| Automated tests | STRONG FOUNDATION | General, domain, NPC, traffic, branch-hygiene, asset-provenance, rendered-performance and photo-match gates are active. City-scale stress remains missing. |
| Web preview | BUILD GREEN / PUBLICATION SETTING BLOCKER | Build works; initial Pages activation is external repository configuration. |
| Performance baseline | AMBER | Deterministic rendered regression exists, but real GPU budgets, streaming/LOD and city-scale load are not production-proven. |
| Asset/license provenance | STABLE FOUNDATION | Existing binary assets are registered and unregistered binary assets are now rejected in CI. The library is still mostly placeholder-level art. |
| First playable vertical slice | PLAYABLE PROTOTYPE | Midi → Centre runs with traffic and PNJ systems. Bourse/Centre remains visibly generic and fails realism completion. |
| Branch integration health | RED/AMBER | Clean lots integrate well; specialist production still outruns integration truth. |

## Branch hygiene alerts

### PR #2 — `zone-laeken-jette`
- draft, base `main`, non-mergeable;
- current measured drift: **442 ahead / 142 behind `main`**;
- 442 commits, 202 changed files;
- contains valuable Atomium/Heysel/Palais 5/Jette data, photo-match, DTM/DSM, trees and scene work, but also dozens of workflows and a separate Web build;
- **never merge/rebase wholesale**. Extract one source-backed hero/data/runtime lot onto current `main`.

### PR #11 — `zone-reste-bruxelles-clean`
- draft, base `main`, non-mergeable;
- current measured drift: **105 ahead / 112 behind `main`**;
- 105 commits, **462 changed files**;
- branch has continued broad municipality expansion even though the Day-1 plan called for stopping it;
- **do not add more broad geography on this base**. Treat it as an evidence store and extract only small current-main Ixelles/cell contracts.

## 1. Main / integration

### Stable enough to build on
- canonical traffic manager/vehicle runtime and official Brussels Mobility density evidence;
- PNJ population/crossing integration;
- police de-escalation/custody/patrol foundations;
- civilian recovery timing + exact routine snapshot contract;
- branch quarantine and strict current-main gate;
- asset provenance gate;
- deterministic rendered performance/visual regression;
- Bourse/Atomium/Miroir photo-match registry and serious-mismatch evidence gate;
- official Ixelles UrbIS 3D second-source discovery.

### Highest-priority resume rule
The interrupted handoff from #68 was resumed first and #71 now provides the model contract for exact civilian routine recovery. **The next PNJ lot is runtime wiring**: `NpcAgent.begin_civilian_recovery()` must capture real pre-incident activity and `update_civilian_recovery()` must restore transit waiting/queue state, ambient idle/social state or walking destination without creating a second transit system.

After that small handoff, the highest-value visual lot remains **Bourse geometry mismatch closure**.

## 2. Laeken + Jette

Continue specialist source-backed photo-match discrepancy reduction only where it creates extractable evidence. Prioritize one hero component: Palais 5 or Atomium ground-oblique. Do not add another specialist Web pipeline or broad unrelated workflow.

**Next integration:** one tiny current-main extraction containing source/provenance + one hero component + deterministic test/capture.

## 3. Rest of Brussels / Ixelles

The broad specialist branch has grown too large and should no longer drive expansion sequencing.

**Next safe lot from current `main`:** spatially match current Ixelles building candidates to official UrbIS 3D `BuildingFaces`, derive ground/roof evidence + uncertainty, publish mismatch/outlier distributions, and only then promote reliable buildings/cells. Keep `runtime_approved=false` until thresholds and tests pass.

Then generate/validate the 2 m DTM terrain package for the same cells: seams, normals, collisions, rendered cost and streaming cost. 1 m remains a justified hero fallback only when photo-match proves it necessary.

## 4. PNJ / police / civilians

Completed foundation:
- crowd response + memory;
- police response/de-escalation/custody;
- foot-patrol planning and live patrol runtime;
- civilian gradual recovery and pre-incident routine snapshot contract.

**Exact next safe lot:** wire the snapshot into real `NpcAgent` activity restoration, with deterministic tests for:
1. normal walking destination;
2. ambient idle/check-phone/social state + sequence progress;
3. transit waiting/queue state without duplicating or corrupting the existing transit queue ownership.

Then proceed to varied pedestrian speeds, curb dwell/pacing, crowd spacing and deadlock recovery.

## 5. Vehicles / traffic / gameplay

Traffic foundation includes cars, scooters/motorcycles, routing, crossings, right-priority, parking, deliveries and wreck/tow lifecycle plus official-density evidence.

**Next traffic lot:** offline corridor/time-bucket evaluation against official Brussels Mobility evidence; then separate small lots for STIB road interaction, intersection behavior, parking/garage behavior and accident/recovery depth.

Still prototype/incomplete: save/load, mission-state depth, economy, shops/activities, interiors, garages/repair gameplay, weather/day-night, Brussels lighting, spatial audio, UI polish, collision coverage and city-wide streaming/LOD.

Preferred playable-game sequence after current realism/evidence blockers: save + mission-state contract → weather/day-night/lighting → spatial audio → shops/interiors framework → richer activities/garages.

## 6. Direction / Assistant

1. **Discuss with user now:** no gameplay decision blocks progress. Optional only: activate the initial GitHub Pages site if a stable public GitHub Pages URL is wanted.
2. **Recommendation:** keep broad expansion frozen. Close integration/reality gaps before more coverage: exact civilian routine restoration, Bourse visual mismatch, Ixelles building-level heights, one clean Laeken hero extraction.
3. **Can continue autonomously:** PNJ recovery wiring, Bourse authoritative geometry/photo-match, Ixelles 3D comparison, Laeken hero extraction, traffic calibration, cell readiness and branch cleanup.
4. **Single biggest risk:** specialist production outpacing integration truth. PR #11 reaching 462 changed files is now as serious an example as PR #2.
5. **Strategic idea worth testing:** enforce a 500 m cell promotion state machine: `candidate → source_verified → runtime_validated → photo_matched → runtime_approved`; broad expansion consumes only approved cells.
6. **Concrete realism action:** replace the generic Palais de la Bourse silhouette/roofline and frontage massing, then rerun the fixed real-reference capture before micro-detail.
7. **Concrete organization action:** prohibit new broad commits on quarantined specialist branches once a domain enters extraction-only status; future geographic production should start from a fresh cell/hero branch based on current `main`.
8. **Maturity:** prototype = most visible art, broad gameplay, interiors/economy/weather/audio, city streaming. Stable foundation = coordinates, source pipeline, CI, traffic runtime, PNJ core, photo-match, performance regression, provenance, extraction workflow. Production-ready = nothing yet.

## Living master backlog

1. Wire exact civilian routine snapshot into live `NpcAgent` restoration (walking + ambient + transit) with red→green tests.
2. Bourse source-backed silhouette/frontage/street geometry correction + fixed photo-match comparison.
3. Ixelles per-building UrbIS 3D comparison → confidence/outlier gate → runtime height approval only for proven cases.
4. Ixelles 2 m terrain runtime package: seams, normals, collisions, streaming/render cost.
5. Extract one source-backed Palais 5/Atomium hero package from Laeken onto current main.
6. PNJ movement/crowd realism: walk-speed variance, curb dwell, spacing, deadlock/recovery.
7. Traffic official calibration evaluation, then STIB/intersection/parking/garage/accident lots.
8. Cell-readiness promotion state machine and evidence manifest.
9. Save/load + mission-state contract; then weather/day-night + lighting and spatial audio.
10. Shops/activities/interiors/garages framework; Brussels-wide expansion only after repeatable cell promotion.

## Exact handoff

- Current integration head at this review: `ffcb4dea30ab0108c6eb1b19f92a7072c06a9acc`, the automatic Web publication immediately after #71.
- #71 merged after confirmed RED `Grand Bruxelles NPC Realism` on the new snapshot regression, then GREEN NPC Realism, NPC Systems, Game CI, Branch Hygiene, general tests, Photo Match QA and Performance Baseline.
- #71 changed only `npc_civilian_recovery.gd` and `npc_civilian_recovery_test.gd`.
- #72 was intentionally closed unmerged because the automatic Web publication advanced `main` after its branch was created; this status update is its clean current-main reconstruction.
- Open unsafe drafts: #2 and #11; both non-mergeable and extraction-only.
- PR #2 drift: 442 ahead / 142 behind.
- PR #11 drift: 105 ahead / 112 behind and 462 changed files; broad work on it should stop.
- Exact next coordinator action: wire the new recovery snapshot contract into live `NpcAgent` behavior on a fresh current-main NPC-only branch; if another workstream leaves a newer clean interrupted handoff first, recover that instead.
- After PNJ wiring, resume Bourse geometry/photo-match as the main visual priority.
