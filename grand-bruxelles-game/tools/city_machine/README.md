# Grand Bruxelles City Machine

`city_machine` is the fail-closed production orchestrator above the existing CityGen and zone data pipes. A successful build produces **LABO_DATA_READY** evidence only. It never edits `playable_zone_catalog.json` and never promotes `LABO` to `JOUABLE`.

## Rebuild Jette

The exact OSM zone projection requires PROJ through pyproj:

```bash
python3 -m pip install "pyproj>=3.7,<4"
python3 grand-bruxelles-game/tools/city_machine/city_machine.py build --zone jette
```

Read-only preflight:

```bash
python3 grand-bruxelles-game/tools/city_machine/city_machine.py build --zone jette --dry-run
```

A full success ends with `CITY_MACHINE_OK zone=jette mode=build result=LABO_DATA_READY ... promotion=false` and writes a deterministic receipt under `grand-bruxelles-game/artifacts/city_machine/jette/build-<digest>.json`.

## Fixed Jette pipeline — registry v2

`registry.json` is execution order, not documentation-only metadata.

1. resolve Jette from the playable-zone catalogue
2. replay cached UrbIS buildings → runtime JSON
3. replay cached street surfaces → runtime JSON
4. replay cached street axes → runtime JSON
5. replay cached train network → runtime JSON
6. replay the committed OSM environment cache → exact EPSG:31370-aligned runtime points
7. **G1** source CRS/provenance/licence + Jette validator
8. **G2** catalogue spawn inside source-derived ground footprint
9. **G3** buildings + street surfaces non-empty
10. **G4** existing Godot materials/ground/official-geometry finish hooks present
11. **G5** OSM cache/runtime digest, ODbL source, EPSG:31370 projection, supported semantics, non-zero trees and ≤2 m bbox tolerance

Any hard gate fails non-zero. There is no “continue anyway” path.

## OSM environment contract

The source cache is `data/osm/zones/jette/environment.raw.json`; the machine output is `data/osm/zones/jette/environment.game.json`. The committed bootstrap evidence contains **3,832 trees, 603 street lamps and 149 bollards (4,584 points)**. Only explicit OSM tags `natural=tree`, `highway=street_lamp` and `barrier=bollard` are carried forward.

The projection is not the old central-corridor tangent approximation. Jette points are transformed **WGS84 → EPSG:31370 with PROJ**, then into the existing game axes `X=east`, `Z=south` using the Jette manifest origin. The live evidence bounds are `[-2969.44,-5761.07,-168.12,-3460.32]`, matching the Jette UrbIS footprint within the hard 2 m reprojection tolerance.

**Nominal builds never call Overpass.** Live refresh is a separate disabled registry layer; the production command consumes the committed normalized ODbL cache. This keeps rebuilds deterministic and network-independent.

## Production proof

`.github/workflows/grand-bruxelles-city-machine.yml` runs registry/unit/failure tests, a Jette dry-run, then two complete rebuilds. It requires identical receipt SHA on pass two and `git diff --exit-code` for the four UrbIS runtime outputs **plus** `environment.game.json`.

The focused OSM-cache workflow independently regenerates `environment.game.json` from the committed cache and byte-compares it with the committed runtime artifact. Both workflows are read-only.

## Before / after

**Before v2:** OSM already knew how to query trees/lamp posts/bollards, but selection/projection was bound to the Midi→Centre corridor. Reusing it for Jette would have introduced a material spatial offset.

**After v2:** the same source semantics are wrapped by a zone-bbox adapter, projected against the exact Jette CRS contract, cached once, rebuilt locally and hard-gated. An agent is no longer required to decide where Jette vegetation/furniture data belongs.

## Deliberately outside the machine

- hero/landmark art and subjective visual polish
- human `LABO` → `JOUABLE` approval
- LLM/NPC dialogue/content
- Godot streaming/engine redesign
- live WFS/Overpass refresh in the nominal reproducible path
- facade candidates until they have a real runtime application contract

A machine PASS means **data-ready LABO**, not “looks finished to a player”. This increment does not claim the new OSM points are rendered in Godot yet.

## Add a layer

1. Prefer a wrapper around an existing deterministic tool; do not rewrite the pipe.
2. Add one ordered registry row with real script, inputs, outputs, gate and `enabled_zones`.
3. New `kind` values require explicit fail-closed handling in `city_machine.py`.
4. Add a measurable gate or keep the layer disabled with a reason; never fake success.
5. Add positive + negative tests and include the output in idempotence proof.
6. Keep paths project-relative, outputs deterministic, no secrets, no catalogue mutation.

## Next machine increment

**Generic runtime environment renderer.** Consume the machine-produced zone artifact (`tree`, `street_lamp`, `bollard`) through one reusable Godot layer instead of a Jette-specific art lot, then prove Jette loads it without changing `LABO` quality. The renderer must remain data-driven so the same artifact contract can expand to other zones.
