# Grand Bruxelles City Machine

`city_machine` is the fail-closed production orchestrator above the existing CityGen and zone data pipes. A successful build produces **LABO_DATA_READY** evidence only. It never edits `playable_zone_catalog.json` and never promotes `LABO` to `JOUABLE`.

## Rebuild a registered zone

Exact OSM projection uses PROJ through pyproj:

```bash
python3 -m pip install "pyproj>=3.7,<4"
python3 grand-bruxelles-game/tools/city_machine/city_machine.py build --zone jette
```

Preflight: `python3 grand-bruxelles-game/tools/city_machine/city_machine.py build --zone jette --dry-run`.

A success ends with `LABO_DATA_READY ... promotion=false` and writes a deterministic receipt under `grand-bruxelles-game/artifacts/city_machine/<zone>/`.

## Profile-driven pipeline — registry v4

The execution graph is now regional and zone-agnostic. Core layers use `enabled_zones: ["*"]`; a municipality becomes executable only when it has an explicit `zone_profiles.<id>` contract. The profile supplies the zone-specific facts while the orchestrator stays generic:

- `source_root` — committed authoritative source bundle;
- `validator_script` — existing source validator for that bundle;
- `runtime_script` — existing Godot zone renderer/finish contract;
- `materialized_slugs` — deterministic geometry products;
- `ground_contract` and `content_minimums`;
- `osm_environment.cache` and `osm_environment.runtime`.

For every registered profile the same ordered machine runs:

1. resolve the zone from the playable-zone catalogue;
2. replay cached UrbIS buildings, street surfaces, street axes and train network to runtime JSON;
3. replay the committed OSM environment cache to exact EPSG:31370-aligned runtime points;
4. **G1** source CRS/provenance/licence + the profile validator;
5. **G2** catalogue spawn inside source-derived ground footprint;
6. **G3** buildings + street surfaces non-empty;
7. **G4** the profile Godot runtime exposes materials/ground/official-geometry finish hooks;
8. **G5** OSM cache/runtime digest, ODbL source, EPSG:31370 projection, supported semantics, non-zero trees and bounded reprojection tolerance;
9. regenerate `data/runtime/runtime_environment_index.json` from all validated City Machine profiles.

Any hard gate fails non-zero. A catalogue zone without a City Machine profile also fails closed. There is no `continue anyway` path.

## Current registered profile: Jette

Jette remains the first complete profile and therefore the regression witness for the regional architecture.

Committed source: `data/osm/zones/jette/environment.raw.json`. Machine output: `data/osm/zones/jette/environment.game.json`. Current evidence contains **3,832 trees, 603 street lamps and 149 bollards (4,584 points)**.

Only explicit OSM tags `natural=tree`, `highway=street_lamp` and `barrier=bollard` are carried forward. Jette points are projected **WGS84 → EPSG:31370 with PROJ → game axes** using the source manifest origin. Evidence bounds are `[-2969.44,-5761.07,-168.12,-3460.32]`, within the hard 2 m reprojection tolerance of the UrbIS footprint.

**Nominal builds never call Overpass.** Live refresh is a separate disabled registry layer; production consumes committed normalized ODbL caches.

## Automatic runtime environment bridge

`build_runtime_environment_index.py` creates a small deterministic discovery index from every City Machine zone profile that owns a validated `osm_environment.runtime` artifact. The index is **visual-only** and explicitly cannot authorize promotion, collision, or gameplay truth.

`brussels_city_machine_environment_runtime.gd` is loaded automatically through the existing runtime-module bootstrap. It reads only the deterministic index, revalidates each artifact, and mounts/unmounts the reusable `BrusselsOsmEnvironmentRuntime` according to the player position with hysteresis. It performs no runtime directory scan and contains no municipality-specific rendering logic.

Adding the next municipality therefore means adding a real profile and its complete evidence bundle, not another orchestration or renderer implementation.

## Ineligible partial environment views

Existing `data/osm/zones/anneessens/environment.game.json` and `data/osm/zones/bourse/environment.game.json` are useful local presentation subsets, but they explicitly have `coverage_complete=false` and do not carry the full EPSG:31370/bounds/source-digest contract required by the City Machine regional profile. They are **not** silently converted into municipality profiles and cannot authorize regional runtime discovery.

They can be onboarded only after a complete authoritative source root, stable spawn/ground contract, profile validator/runtime, committed full-zone OSM cache, exact projection and all G1–G5 evidence exist.

## Production proof

`.github/workflows/grand-bruxelles-city-machine.yml` runs registry/unit/failure tests, the regional-onboarding regression, runtime-environment index checks and Jette as the complete-profile witness. It dry-runs and performs two complete Jette rebuilds, requires identical receipt SHA on pass two, and requires `git diff --exit-code` for the four UrbIS runtime outputs, `environment.game.json`, and `runtime_environment_index.json`.

The workflow path filters now cover regional UrbIS/OSM/zone changes so future profiles cannot bypass this machine accidentally.

## Product boundary

Outside the machine on purpose: hero art, subjective visual approval, human `LABO`→`JOUABLE`, LLM/NPC content, live WFS/Overpass in the nominal path, and facade candidates without a runtime application contract. A machine PASS means **data-ready LABO**, not visible polish.

## Add a profile

1. keep the zone in `playable_zone_catalog.json` with honest quality;
2. add one `zone_profiles.<zone>` object with real paths only;
3. prove all source files and scripts exist;
4. provide committed full-zone OSM cache + exact EPSG:31370 runtime output;
5. run the unchanged wildcard pipeline and all G1–G5 gates;
6. include all generated outputs in deterministic/idempotence proof;
7. keep LABO→JOUABLE human-controlled.

Do not create a profile from a partial visual subset merely to increase coverage numbers.

## Next machine increment

**First additional full regional profile.** Select the next municipality only when its complete UrbIS source/root, stable catalogue spawn/ground contract and committed full-zone OSM evidence are present. Until then, continue producing/validating those source bundles rather than weakening the v4 contract.
