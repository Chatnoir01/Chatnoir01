# Grand Bruxelles City Machine

`city_machine` is the production orchestrator being built above the existing CityGen and zone-specific data pipes. Its contract is fail-closed: a successful build may produce **LABO_DATA_READY** evidence, but it never edits `playable_zone_catalog.json` and never promotes a zone to `JOUABLE`.

## Phase 0 — cold map

Pilot zone: **Jette**, because production already has a complete cached UrbIS phase, a validator, a Lambert72→game converter, a loadable Godot runtime and a catalogue LABO spawn.

Source contract: `data/urbis/laeken_jette/jette_phase2/manifest.json` declares EPSG:31370, the project game origin, provenance/licence, and these current counts: 12,648 buildings, 4,458 street surfaces, 1,314 street axes, 204 tram features, 204 train features, 6 bridges and 3 tunnels.

Runtime contract: `game/zones/laeken_jette/jette_phase2_zone.gd` loads the `.game.json` layers, builds a collision ground covering the source bbox, creates buildings/roads/rail geometry, and applies its existing materials. Midi is read-only reference and is not touched by this machine.

## Existing tool park before the machine

`tools/citygen/` contains 19 callable production scripts covering the regional grid, 500 m UrbIS cell materialization, durable autonomous scheduling, DSM/DTM resolution and validation, height candidates, terrain LOD, quarantine/frontier evidence and maturity. The exact inventory is frozen in `registry.json`.

`tools/city_generation/` contains 5 callable facade/candidate QA scripts. They explicitly do not mutate runtime, so they are not treated as a finished-zone layer in Jette v0.

Jette already has `fetch_urbis_jette_phase2.py`, `validate_jette_phase2_data.py` and `lambert72_to_game_geojson.py`; what is missing is one ordered executor above them.

## Fixed Jette order in registry v1

1. resolve catalogue zone
2. materialize cached buildings → runtime JSON
3. materialize cached street surfaces → runtime JSON
4. materialize cached street axes → runtime JSON
5. materialize cached train network → runtime JSON
6. G1 source/CRS/provenance validator
7. G2 catalogue spawn inside the converted runtime ground footprint
8. G3 buildings and street surfaces non-empty
9. G4 existing Godot finish contract (materials + ground + official geometry hooks)

Every layer row records `layer_id`, script, inputs, outputs, gate and enabled zones. Order is data, not agent memory.

## Deliberately disabled in v0

- **OSM environment/trees:** the repository already queries/projects `tree`, `street_lamp` and `bollard`, but the current runtime-slice contract is tied to the central corridor bbox/anchors. There is no Jette zone-bbox adapter yet.
- **Facade candidate pipeline:** deterministic and useful, but candidate/QA-only and wired to `remaining_brussels` cells rather than Jette phase2 runtime artifacts.
- **Live UrbIS refresh:** available, but not a nominal rebuild dependency. Nominal builds must be reproducible from committed/cached authoritative raw data.

## Product boundary

Outside the machine on purpose: hero art, subjective visual approval, LABO→JOUABLE promotion, LLM/NPC content, and engine/streaming redesign. A machine PASS is not a human quality promotion.

Phase 1 adds the stable CLI executor over this registry. The next global layer after the executor/gates is the zone-bbox OSM environment adapter, starting with trees.
