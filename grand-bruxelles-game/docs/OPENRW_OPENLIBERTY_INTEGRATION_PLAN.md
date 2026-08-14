# Grand Bruxelles Game — OpenRW / OpenLiberty integration roadmap

## Objective

Use OpenRW as a gameplay/engine reference and OpenLiberty as a Godot/Redot implementation reference to accelerate generic open-world systems **without replacing Brussels data, assets, gameplay identity, or existing production systems**.

## Non-negotiable boundaries

- `main` remains the production truth.
- Brussels geometry stays sourced from UrbIS / EPSG:31370, with OSM only where already allowed by project policy.
- No GTA maps, models, textures, sounds, missions, scripts, brands, characters or copyrighted game data enter the repository.
- OpenRW is GPLv3: **reference/behavior study only unless a later legal review explicitly approves a compatible isolated use**. Do not copy GPL implementation code into production files.
- OpenLiberty is MIT at repository level, but every imported file/dependency must still be reviewed and provenance recorded before use.
- Every integration is isolated in a branch and must pass Godot 4.7.1 import, Web export, performance, gameplay smoke tests and a player-visible A/B test before merge.

## Phase 0 — Baseline and inventory

Before importing anything external, freeze a measured baseline from current `main`:

- player locomotion and camera
- player vehicle A/B handling
- NPC population / police response
- world streaming / cell loading
- collision counts and collision failures
- Web build size and startup time
- frame-time / NPC / traffic performance budgets

Deliverable: `docs/integration-baseline.md` plus machine-readable benchmark snapshots.

## Phase 1 — File-by-file external audit

### OpenRW

Study architecture only:

- vehicle/pedestrian state separation
- physics responsibilities
- world entity lifecycle
- script/event machine concepts
- collision/world partitioning concepts
- save-game orchestration
- debug tooling

Output only design notes and behavior contracts. No GPL code copied into Grand Bruxelles production.

### OpenLiberty

Audit Godot-facing modules, especially:

- world/map builder
- asset loading and runtime conversion
- model/texture streaming lifecycle
- world node ownership
- render/runtime separation
- cache invalidation

For every candidate file record:

- upstream path + commit SHA
- license
- dependencies
- what problem it solves better than our implementation
- whether to import, adapt, or only reproduce the idea

## Phase 2 — World streaming prototype

Priority: highest architectural value.

Create an isolated `agent/openliberty-streaming-probe` branch.

Goal:

- reproduce OpenLiberty-style lifecycle ideas on **our existing Brussels cells**
- no RenderWare/GTA format support
- keep UrbIS/OSM data loaders unchanged
- test asynchronous/predictive loading around player and driven vehicle
- unload distant heavy visual nodes while keeping mission/state data alive

Acceptance:

- no visible pop regression in Midi → Bourse drive
- lower or equal peak loaded node count
- lower or equal peak memory
- Web build remains functional
- deterministic cell ownership and cleanup

## Phase 3 — Collision streaming / spatial partition

Use OpenRW/OpenLiberty only as references for world partition behavior.

Build a Brussels-native collision streamer:

- high precision collision near player/vehicle
- simplified collision farther away
- hero buildings keep exact runtime-approved collision
- no invisible wall after visual mesh mutation
- PNJ collision remains lightweight

Acceptance:

- player cannot cross sampled official facades
- Bourse/Grand-Place existing collision-sync guards remain green
- collision body count stays inside mobile budget

## Phase 4 — Vehicle architecture upgrade

Do **not** wholesale replace the current vehicle system.

Use lessons from OpenRW entity/vehicle responsibilities plus our validated RigidBody prototype.

Target architecture:

- one shared vehicle interface
- interchangeable human / AI driver input
- RigidBody handling profile for player vehicles
- traffic vehicles retain lightweight simulation where appropriate
- damage, police lights, enter/exit, save state and mission hooks preserved

A/B gate:

- legacy vehicle A vs physical vehicle B in the same route
- braking, cornering, stability, mobile controls, frame time
- merge only when B is clearly better to play and still Web-safe

## Phase 5 — NPC / police orchestration

Keep `NpcBehaviorModel` as game-domain authority.

Use OpenRW as behavioral reference and our validated LimboAI pilot as optional orchestration layer.

Visible target:

- civilians: route → wait → observe → react/flee → recover
- police: patrol → detect → approach → pursue → investigate → return
- no NPCs crossing buildings or each other
- police vehicle and foot response share the same event state

Acceptance:

- first visible scenario at Midi/Bourse must be understandable without debug text
- crowd reaction and police response can be triggered and observed in under 60 seconds

## Phase 6 — Mission/event layer exposure

Do not recreate GTA mission scripts.

Reuse the architectural idea of an event/script machine to expose our existing systems:

- mission triggers
- wanted/police events
- wallet/reward events
- STIB boarding events
- garages/interactions
- save/resume checkpoints

Mobile UI must expose any action currently hidden behind keyboard-only controls.

## Phase 7 — Debug and developer tooling

Borrow concepts, not GPL code, from OpenRW debug workflows:

- entity inspector
- current cell / loaded cells
- collision debug toggle
- NPC state overlay
- traffic path overlay
- mission event log
- streaming/memory overlay

These are development-only and disabled in public builds by default.

## Phase 8 — Integration order into `main`

Merge only small independent PRs in this order:

1. streaming probe if benchmark-positive
2. collision streaming
3. production vehicle B if A/B-positive
4. visible NPC/police pilot
5. mission/event exposure
6. STIB stop/boarding exposure
7. debug tooling

Never merge a whole external framework or a whole laboratory branch.

## Merge gate for every external-derived change

Required before merge:

- source/license entry in provenance registry
- Godot 4.7.1 headless import green
- Web export green
- Game CI green
- performance baseline green
- visual/photo-match guards green where relevant
- existing save/mission/vehicle/NPC contracts preserved
- visible player benefit demonstrated

## What we deliberately keep ours

- Brussels map and coordinates
- UrbIS/OSM/LiDAR/orthophoto pipelines
- Brussels cell maturity and provenance policy
- STIB/police/Brussels-specific identity
- mission content
- character identity
- mobile UX
- economy
- testing / source-faithfulness rules

## First implementation task

Start with **Phase 2: `agent/openliberty-streaming-probe`** because it offers the largest reusable architectural gain while touching the least Brussels-specific gameplay. The probe must be rejected if it does not improve node/memory behavior or if it causes visible pop-in on Web/mobile.
