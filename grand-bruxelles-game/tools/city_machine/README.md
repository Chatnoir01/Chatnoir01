# Grand Bruxelles City Machine

`city_machine` is the fail-closed production orchestrator above the existing CityGen and zone data pipes. A successful build produces **LABO_DATA_READY** evidence only. It never edits `playable_zone_catalog.json` and never promotes `LABO` to `JOUABLE`.

## Rebuild Jette

Exact OSM projection uses PROJ through pyproj:

```bash
python3 -m pip install "pyproj>=3.7,<4"
python3 grand-bruxelles-game/tools/city_machine/city_machine.py build --zone jette
```

Preflight: `python3 grand-bruxelles-game/tools/city_machine/city_machine.py build --zone jette --dry-run`.

A success ends with `LABO_DATA_READY ... promotion=false` and writes a deterministic receipt under `grand-bruxelles-game/artifacts/city_machine/jette/`.

## Fixed Jette pipeline — registry v2

1. resolve Jette from the playable-zone catalogue
2. replay cached UrbIS buildings, street surfaces, street axes and train network to runtime JSON
3. replay committed OSM environment cache to exact EPSG:31370-aligned runtime points
4. **G1** source CRS/provenance/licence + existing Jette validator
5. **G2** catalogue spawn inside source-derived ground footprint
6. **G3** buildings + street surfaces non-empty
7. **G4** existing Godot materials/ground/official-geometry finish hooks present
8. **G5** OSM cache/runtime digest, ODbL source, EPSG:31370 projection, supported semantics, non-zero trees and ≤2 m bbox tolerance

Any hard gate fails non-zero. There is no “continue anyway” path.

## OSM environment contract

Committed source: `data/osm/zones/jette/environment.raw.json`. Machine output: `data/osm/zones/jette/environment.game.json`. Current evidence contains **3,832 trees, 603 street lamps and 149 bollards (4,584 points)**.

Only explicit OSM tags `natural=tree`, `highway=street_lamp` and `barrier=bollard` are carried forward. Jette points are projected **WGS84 → EPSG:31370 with PROJ → game axes** using the Jette manifest origin. Live evidence bounds are `[-2969.44,-5761.07,-168.12,-3460.32]`, within the hard 2 m reprojection tolerance of the UrbIS footprint.

**Nominal builds never call Overpass.** Live refresh is a separate disabled registry layer; production consumes the committed normalized ODbL cache.

## Production proof

`.github/workflows/grand-bruxelles-city-machine.yml` runs registry/unit/failure tests, dry-run, then two complete rebuilds. It requires identical receipt SHA on pass two and `git diff --exit-code` for the four UrbIS runtime outputs plus `environment.game.json`.

The dedicated OSM-cache workflow independently regenerates `environment.game.json` from the committed cache and byte-compares it with production. Both workflows are read-only.

## Product boundary

Outside the machine on purpose: hero art, subjective visual approval, human `LABO`→`JOUABLE`, LLM/NPC content, engine/streaming redesign, live WFS/Overpass in the nominal path, and facade candidates without a runtime application contract. A machine PASS means **data-ready LABO**, not visible polish.

## Add a layer

Prefer wrappers over existing deterministic tools. Add one ordered registry row with real inputs/outputs/gate/zones; new `kind` values require an explicit fail-closed handler. Add positive + negative tests and include the output in idempotence proof. Keep paths relative, outputs deterministic, no secrets and no catalogue mutation.

## Next machine increment

**Generic runtime environment renderer.** Consume the machine-produced `tree/street_lamp/bollard` artifact through one reusable Godot layer, not a Jette-specific art lot, then prove Jette loads it without changing `LABO` quality.
