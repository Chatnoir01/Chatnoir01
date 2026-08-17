# Grand Bruxelles — Production Capability Gaps

Observed production baseline: `b5f2f427be789067a5f94712bb485d96dedc4e2f`.

This document is a strategic capability backlog. It does **not** replace `docs/PRODUCTION_WALL.md`, does not claim ownership of active visual/gameplay PRs, and does not auto-promote any LABO zone. Before starting any implementation, re-read live `main`, open PRs and the Production Wall.

## Verified corrections to the broad audit

The broad diagnosis is directionally correct, but several details are already partially implemented and must not be redone blindly:

- The playable catalogue contains exactly 7 zones: Midi, Anneessens, Bourse, Grand-Place, Ixelles, Atomium/Heysel and Jette.
- The standardized City Machine registry currently enables only `jette`.
- The City Machine CLI currently supports `build --zone <id>` only; there is no merged `--all`/multi-zone orchestration.
- The standardized `data/osm/zones/<zone>/` environment contract currently exists only for Jette.
- Anneessens is **not zero-OSM**: production already contains a small source-backed `anneessens_environment_points.game.json` plus an OSM furniture runtime/visual gate. The missing capability is standardization/coverage, not total absence.
- Continuity already has repository-side parsing/validation for exported SIGNALER reports and complete sync snapshots. The incomplete part is the end-to-end player export → committed/CI-ingested production loop; do not rebuild the parser from scratch.
- Web first-load weight has already been reduced substantially by recent production work; the old ~100 MB PCK figure is historical, not the current baseline. Streaming/budget remains a product concern, but future work must re-measure current main before acting.
- Player melee feel is actively owned by the current Midi gameplay stream; do not open a competing combat implementation.
- Asset provenance already has CI support; the remaining legal gap is a clearer consolidated licence board and disciplined intake for new open assets, not absence of provenance tooling.

## Capability matrix

| Capability | Current production truth | Gap to close |
|---|---|---|
| UrbIS anchor geometry | Strong on several anchors | Broaden deterministic coverage without duplicating hero-specific work |
| OSM environment | Jette standardized; Anneessens partial bespoke; corridor slices exist | Standard zone contract across all 7 catalogue zones |
| City Machine | Fail-closed, deterministic, Jette-only | Multi-zone registry + `--all` + aggregate receipt |
| Terrain/DTM | Ixelles and Atomium have serious evidence/runtime work | Catalogue-wide terrain policy and source coverage |
| Heights/roofs | Hero/selected LoD2 and DSM work exist | Systematic roof/height application with confidence policy |
| Landcover/green surface | Some Atomium candidate work | Reusable parks/grass/water surface family with source contracts |
| POI/addresses | Sparse runtime consumption | Neighbourhood identity data layer |
| STIB/transit identity | Rail/tram geometry exists in places | Stops/lines/route identity and Belgian transit presentation |
| Mobility snapshot | Builder/data exists | Runtime density/flow adapter with measurable effect |
| Materials | Multiple reusable families exist | Consistent application policy across catalogue zones |
| Props | Some trees/lamps/bollards | Densified source-backed street furniture and FR/NL identity props |
| NPC/gameplay | Multiple systems/branches exist | Shippable combat response, vehicle interaction, police/wanted and missions |
| SIGNALER/continuity | Parser/sync logic exists; player export stream exists separately | End-to-end repo ingestion and automated oldest-open routing |
| Publish | Web/Pages publish works | Deterministic data-build → validated playable publish coupling |
| Audio | No production-wide ambience layer established | CC0/licence-clean ambient street/tram/rain/foule layer |
| Licence governance | Provenance workflow exists | One human-readable asset/data licence board for every imported pack |

## P0 sequence — do not parallelize all six

The following order is the production plan. A later lot may start only when it does not overlap an active owner and its prerequisite is real on `main`.

### P0.1 — Standard OSM environment contract for all catalogue zones

Goal: every catalogue zone has a deterministic `data/osm/zones/<zone>/environment.raw.json` + `environment.game.json` contract, or an explicit `disabled` status with a documented source reason.

Rules:
- cache-first; nominal CI never depends on live Overpass;
- ODbL provenance and source digest mandatory;
- no invented trees/lamps/bollards/POI;
- reuse existing Anneessens/Jette/corridor evidence instead of duplicating runtimes;
- roll out one zone at a time, then close with a catalogue coverage gate.

Suggested first non-overlapping extraction: normalize existing Anneessens evidence into the standard zone contract **without** replacing its already-shipped furniture runtime.

### P0.2 — City Machine multi-zone + aggregate proof

After at least two zone profiles are real, add `build --all` (or equivalent explicit multi-zone command) and an aggregate receipt.

Acceptance:
- exact catalogue/profile coverage printed;
- enabled zones build deterministically;
- disabled zones are explicit, never silently skipped;
- one failing zone fails the aggregate command;
- no automatic LABO→JOUABLE promotion.

### P0.3 — Data build → playable publish loop

Couple a successful, changed runtime-data build to the normal Web validation/publish path.

Acceptance:
- no publish when generated data is byte-identical;
- no publish on a failed data gate;
- Web + Game CI + relevant performance gate on the same substantive SHA;
- Pages only after the playable artifact is validated.

### P0.4 — Systematic roofs/heights pilot on Midi

Do not invent heights. Reuse UrbIS LoD2 / validated DSM-DTM confidence policy and apply it to one bounded Midi building batch.

Acceptance:
- explicit confidence/source per building;
- uncertain height remains unresolved;
- no geometry drift in official footprint;
- visual 3-second improvement plus Web/PC/performance proof.

### P0.5 — One licence-clean gameplay kit integration

Do not import a giant asset pack. Pick exactly one narrow capability after current Midi melee ownership resolves: either vehicle enter/exit reliability or NPC defensive combat response.

Acceptance:
- exact upstream licence/version pinned;
- only necessary files vendored;
- provenance board updated;
- measurable player gate in Midi;
- no parallel rewrite of existing controller architecture.

### P0.6 — STIB stops/lines on the played corridor

Start with transit identity, not a full simulator.

Acceptance:
- source/licence documented;
- stops/line IDs tied to existing played corridor coordinates;
- visible stop/line identity in-game;
- no fabricated timetable accuracy;
- rail/tram geometry owners remain separate.

## Wave 2

Only after P0 closes enough of the data→runtime→visible loop:

- broader DTM/terrain coverage;
- landcover/parks/water;
- POI/addresses/commercial identity;
- generic life adapter backed by mobility density;
- wanted/police and mission expansion;
- save/progression hardening;
- mobile-specific performance budget;
- CC0 ambient audio;
- night-lighting option;
- region-wide remaining-Brussels cell expansion.

## Hard production rules

1. `main` remains the only shipped truth.
2. One defect/capability has one active implementation owner.
3. Existing partial implementations must be generalized or reused, not recreated under a new name.
4. No source-backed claim may be upgraded from presentation convention to measurement without evidence.
5. No threshold lowering to rescue a visual/runtime lot.
6. Every player-facing lot needs an in-game proof; every data-only lot needs deterministic receipts and negative tests.
7. Open-source/gameplay asset reuse is allowed only with pinned provenance, licence compatibility and minimal vendoring.
8. Do not use this roadmap as justification to interrupt a current exact-head release blocker or an already-owned Midi/Grand-Place lot.
