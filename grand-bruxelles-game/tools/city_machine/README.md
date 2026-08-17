# Grand Bruxelles City Machine

`city_machine` is the fail-closed production orchestrator above the existing CityGen and zone data pipes. A successful build produces **LABO_DATA_READY** evidence only. It never edits `playable_zone_catalog.json` and never promotes `LABO` to `JOUABLE`.

## Rebuild Jette

From the repository root:

```bash
python3 grand-bruxelles-game/tools/city_machine/city_machine.py build --zone jette
```

Read-only preflight:

```bash
python3 grand-bruxelles-game/tools/city_machine/city_machine.py build --zone jette --dry-run
```

A full success ends with `CITY_MACHINE_OK zone=jette mode=build result=LABO_DATA_READY ... promotion=false` and writes a deterministic receipt under:

`grand-bruxelles-game/artifacts/city_machine/jette/build-<digest>.json`

The receipt records the source contract, fixed layer list, gate results, runtime output paths/counts/SHA256, disabled layers and `promotion_performed: false`. The build ID contains no wall-clock time: identical inputs produce the same receipt name and bytes.

## Fixed Jette pipeline — registry v1

`registry.json` is execution order, not documentation-only metadata. Every row records `layer_id`, script, inputs, outputs, gate and enabled zones.

1. resolve `jette` from `data/qa/playable_zone_catalog.json`
2. replay cached `buildings.geojson` through the existing Lambert72→game converter
3. replay cached `street_surfaces.geojson`
4. replay cached `street_axes.geojson`
5. replay cached `train_network.geojson`
6. **G1** run the existing Jette validator: source CRS/provenance/licence, manifest parity and required layers
7. **G2** prove the catalogue spawn lies inside the runtime ground footprint derived from the manifest EPSG:31370 bbox/game origin, with sane vertical clearance
8. **G3** prove rebuilt buildings and street surfaces are non-empty
9. **G4** prove the existing Jette Godot runtime still exposes materials, ground and official-geometry finish hooks

Any hard gate fails with a non-zero exit code. There is no “continue anyway” path.

## Real production evidence

The CI job `.github/workflows/grand-bruxelles-city-machine.yml` runs unit/fail-closed tests, a real Jette dry-run, then **two full Jette rebuilds**. It requires:

- G1: 12,648 buildings, 4,458 street surfaces, 1,314 street axes, 204 train features, plus the committed ancillary layers
- G2: Jette spawn inside the source-derived runtime ground bounds
- G3: 12,648 rebuilt buildings and 4,458 rebuilt street surfaces
- G4: runtime materials + ground + geometry hooks present
- same deterministic receipt after the second run
- `git diff --exit-code` for all four regenerated `.game.json` outputs

The first integrated proof produced `build-2a241c55e0169113.json` twice with the same SHA256 and no tracked runtime diff.

## Before / after

**Before:** 19 callable `tools/citygen/` scripts, 5 deterministic `tools/city_generation/` candidate/QA scripts, durable autonomous cell state, Jette-specific UrbIS fetch/validate/convert tools and a loadable Jette runtime existed, but rebuilding a zone required knowing which tool to call and in what order.

**After:** the nominal Jette data-ready rebuild is one command. Layer order, inputs, outputs and gates are machine-readable; CI proves it is idempotent. An agent is no longer the production scheduler for this path.

## Deliberately outside the machine

- hero/landmark art and subjective visual polish
- human `LABO` → `JOUABLE` approval
- LLM/NPC dialogue/content
- Godot streaming/engine redesign
- live WFS refresh in the nominal reproducible path
- facade candidates until they have a real runtime application contract

A machine PASS means **data-ready LABO**, not “looks finished to a player”.

## Add a layer

1. Prefer a wrapper around an existing deterministic tool; do not rewrite the pipe.
2. Add one ordered `registry.json` row with real script, inputs, outputs, gate and `enabled_zones`.
3. If the existing `kind` dispatcher fits, reuse it. A new `kind` requires an explicit fail-closed handler in `city_machine.py`.
4. Add a measurable gate or explicitly keep the layer disabled with `disabled_reason`; never fake success.
5. Add a unit/failure case and include the layer in the CI rebuild/idempotence proof.
6. Keep paths project-relative and outputs deterministic. A nominal rebuild must not require secrets or mutate the catalogue.

## Next layer

**OSM environment by zone bbox, trees first.** The repo already queries/projects `tree`, `street_lamp` and `bollard`, but that pipe is currently bound to the central corridor anchors. The next machine increment should adapt those existing functions to a catalogue-zone bbox/runtime output contract, then enable the layer for Jette only after its own gate is real.
