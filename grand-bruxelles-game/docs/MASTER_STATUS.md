# Grand Bruxelles Game — Master Status

Last coordinated review: 2026-08-12

This file is the integration/direction snapshot for the project. It does not replace specialist documentation; it records what is safe to continue, what is blocked, and the next integration order.

## Current main baseline

- Main head observed after the latest playable web publish: `fc4b3cc11f4df97c67d967f96062d156fac1464e`.
- Isolated NPC / police / civilian baseline is integrated.
- Isolated police-vehicle component set is integrated.
- Main Godot/test workflows observed green after the police-vehicle integration.
- Police vehicle bodies and markings remain **functional prototypes**, not photo-match-complete final assets.

## Day-1 maturity check

| Area | State | Direction |
|---|---|---|
| Repository / branch ownership | PARTIAL | Specialist branches exist, but drift must be controlled and every new branch needs explicit ownership/PR. |
| EPSG:31370 / Lambert 72 integrity | STABLE FOUNDATION | Keep as the official geometry reference. |
| UrbIS / WFS pipeline | STABLE FOUNDATION | Continue source-first reconstruction; do not replace authoritative geometry with guessed art. |
| OSM complementary traffic data | WORKING PROTOTYPE | Keep ODbL provenance and isolate traffic runtime data from visual city geometry. |
| Godot project health | WORKING | Main tests are green; specialist branches still need synchronization gates. |
| Automated tests / CI | WORKING | CI exists; roadmap documentation must stay synchronized with reality. |
| Web preview | WORKING PROTOTYPE | Useful for smoke validation, not proof of final visual fidelity. |
| Performance baseline | MISSING HARD METRIC | Record first reproducible FPS/CPU/GPU benchmark before city scale increases further. |
| Asset / license provenance | PARTIAL | Registry exists for current assets; every external production asset must remain traceable. |
| Photo-match validation | EARLY | Structural realism tests exist, but deterministic real-reference ↔ in-game viewpoint scoring is not yet complete. |
| First complete vertical slice | INCOMPLETE | Midi → Grand-Place remains the primary gameplay/integration slice. |

## Active specialist workstreams

### 1. Vehicles & traffic — PR #3

Observed state: large functional traffic slice with road graph, controls and intersection AI.

Branch drift snapshot vs current `main`:
- ahead: 59 commits;
- behind: 4 commits;
- PR currently non-mergeable at the reviewed snapshot;
- branch modifies `game/main.tscn` and the shared `grand-bruxelles-game.yml` workflow.

**Gate:** stop feature breadth until the branch is synchronized with `main` and shared-scene/workflow conflicts are isolated. The next safe integration target is the traffic component/runtime API, not a blind merge of all branch history.

After synchronization: pedestrians at crossings → time/area density → scooters/motorcycles → STIB behavior → parking/deliveries → accidents/damage/towing/garages.

### 2. Laeken + Jette — PR #2

Observed state: official UrbIS geometry, Laeken/Jette standalone scenes, Atomium hero pass, DTM/orthophoto work and extensive zone validation.

Branch drift snapshot vs current `main`:
- ahead: 131 commits;
- behind: 20 commits;
- PR remained mergeable at the reviewed snapshot, but the historical divergence is now large.

**Gate:** do not declare the hero zone realism-complete and do not prioritize wider geographic breadth before establishing at least three deterministic real-reference ↔ in-game viewpoints around the Atomium/Heysel approach. Record camera position, eye height, FOV and mismatch notes for silhouette/roofline, heights, streets/curbs, furniture, vegetation, materials, lighting and major clutter.

Recommended branch action: finish the current coherent realism benchmark lot, then synchronize/isolate an integration-ready zone package rather than letting the branch diverge indefinitely.

### 3. Rest of Brussels — PR #4

Observed state: clean geographic/data ownership with Anderlecht and Molenbeek materialization work, UrbIS cells, runtime index and orthophoto references.

Branch drift snapshot vs current `main`:
- ahead: 95 commits;
- behind: 4 commits;
- PR currently mergeable at the reviewed snapshot;
- branch still modifies `game/main.tscn`, so integration conflict risk exists despite otherwise clean geographic ownership.

**Gate:** finish the current Molenbeek seed/cell lot, then synchronize with `main` before opening another commune wave. Keep geographic expansion subordinate to streaming/performance budgets and a proven visual-quality pipeline.

### 4. NPC / police / civilians

Baseline component is integrated in `main`.

Next safe lot: connect population schedules, alerts and police/civilian reactions to the actual traffic/world interfaces without coupling the systems to one geographic branch.

### 5. Direction / assistant

Current decision: no user decision is required to continue foundations.

Immediate direction:
1. repair/synchronize PR #3 before adding more traffic features;
2. make Atomium/Heysel the first deterministic photo-match benchmark;
3. finish the current Molenbeek geographic seed, then sync PR #4;
4. measure a real performance baseline before multiplying active cells;
5. keep Midi → Grand-Place as the primary integrated vertical slice.

## Branch hygiene alerts

- `agent/police-gameplay-realism` is superseded by the clean police-vehicle integration path and must not receive new work.
- `systems-npc-police-civilians` and `systems-police-vehicles` are already integrated baselines; new work should branch from current `main` unless a specialist branch intentionally continues them.
- `agent/police-ai-gameplay` exists without an open PR/ownership record in the reviewed snapshot. Treat it as **quarantined**: inspect its ancestry/diff before adding work or integrating anything from it.
- Any specialist branch that touches `game/main.tscn` or shared CI must explicitly isolate those changes before integration.

## Realism definition of done

A Brussels hero area is not complete merely because coordinates and footprints are correct. Final validation must cover:

- authoritative geometry and scale;
- terrain/elevation where relevant;
- correct building heights and roof silhouettes;
- façade proportions and neighborhood-specific materials;
- road, lane, sidewalk and curb proportions;
- tram/rail/public-transport infrastructure;
- signs, lighting, street furniture and vegetation;
- believable parking, clutter, aging and road wear;
- pedestrian/traffic behavior appropriate to the place/time;
- audio/light/weather context;
- deterministic screenshot comparison against lawful real references;
- performance within a recorded budget.

Unsupported details stay marked provisional rather than being invented.

## Highest project risk

The largest current risk is **production velocity outrunning integration and validation**: hundreds of specialist commits can create apparent progress while branch drift, missing performance budgets and weak photo-match validation make the result expensive to integrate or visually generic.

## Next strategic experiment

Build one reference-quality benchmark around the Atomium/Heysel approach and one gameplay benchmark on Midi → Grand-Place. Use the same measurable checklist for both: geometry error, visual mismatch list, FPS/CPU/GPU, draw/instance budgets, collisions, traffic/pedestrian behavior and provenance. If this pipeline is reproducible, apply it commune-by-commune across Brussels.

## Exact next handoff

1. `vehicles-traffic`: sync to current `main`, resolve `main.tscn`/workflow conflicts, rerun all traffic + main smoke tests, expose traffic through a narrow integration API.
2. `zone-laeken-jette`: finish 3 fixed photo-match viewpoints before wider art expansion.
3. `zone-reste-bruxelles`: finish current Molenbeek seed, then sync to `main` before next commune wave.
4. `main`: record first reproducible performance baseline and keep the playable web build green.
5. inspect/quarantine `agent/police-ai-gameplay` until its purpose, ancestry and diff are explicit.
