# City Machine finish pipeline pilot

## Pilot choice

1. Midi is JOUABLE, but current `main` still does not prove a zone-scoped machine rebuild from Midi buildings + streets inputs.
2. Jette has committed UrbIS phase2 buildings + street surfaces + street axes + tram + train data and an existing deterministic machine path.
3. Therefore the campaign pilot remains **Jette** under the fixed selection law.
4. The pilot is locked for this campaign; no mid-run zone switch is allowed.
5. Missing optional layers log `SKIP` / `missing_source` and never invent source geometry.

## Rebuild in one command

```bash
python3 grand-bruxelles-game/tools/city_machine/finish_pipeline.py build --zone jette
```

From inside `grand-bruxelles-game/`:

```bash
python3 tools/city_machine/finish_pipeline.py build --zone jette
```

To require production readiness instead of accepting a LABO rebuild with explicit blockers:

```bash
python3 tools/city_machine/finish_pipeline.py build --zone jette --require-ready
```

`--require-ready` is fail-closed: any G7-G12 `BLOCKED` result returns non-zero and never promotes the zone automatically.

## V3 production path

1. Geometry rebuilds committed/cached UrbIS runtime outputs for buildings, street surfaces, street axes, **tram network**, and train network.
2. OSM environment rebuilds from the committed Jette ODbL cache.
3. Finish materials execute deterministically from the Jette zone profile and existing runtime bindings.
4. `AUTHORED_OVERRIDE > GENERATED_BASE` is hard policy; the authored Jette station brick/stone treatment is preserved.
5. Jette StreetSurfaces stay neutral because current source semantics do not safely isolate sidewalks or asphalt composition.
6. Roof, glass, concrete, generic brick/stone and vegetation-surface families remain explicit `missing_source` skips rather than fabricated output.
7. Life remains `disabled` until an existing ambient system can be parameterized safely by `zone_id`.
8. Final deterministic proof reruns hard G1→G6; any hard gate failure returns non-zero.
9. Production-readiness audit then runs G7→G12. Missing production evidence is `BLOCKED`, structural corruption is a hard failure.
10. Dedicated CI runs two complete rebuilds and requires byte-identical tracked outputs plus zero diff from the committed nominal outputs.
11. The machine never promotes LABO to JOUABLE; promotion remains human-only.

## Deterministic rebuild gates G1-G6

- **G1** sources / CRS / licence
- **G2** spawn / ground / bounds
- **G3** buildings + streets runtime content
- **G4** Godot runtime finish hooks
- **G5** source-backed OSM environment
- **G6** deterministic finish-material bindings + authored override preservation

## Production-readiness gates G7-G12

This numbering is introduced by this lot; no previous branch had a canonical G7-G12 mapping.

- **G7 generated-file ownership** — every nominal generated `data/` output has one producer and authored runtime files are never claimed as generated output.
- **G8 landmark non-regression** — registered authored landmark selectors/owners must still exist in the Jette runtime; currently guards `JetteStationOfficialFootprintHero` and `JetteStationStoneBand`.
- **G9 collision solidity** — ground collision plus building solidity must be proven. Current Jette runtime proves the reference-ground collision but does **not** prove building collision, so this gate is intentionally `BLOCKED` and the Laeken/Jette runtime owner remains untouched by this factory PR.
- **G10 geometry outliers** — scans every materialized runtime coordinate for non-finite values and gross CRS/origin-scale outliers. Valid long WFS features may cross the query bbox; only city-scale transform disasters are rejected.
- **G11 streaming mount** — requires an actually wired/authorized bounded runtime mount. Current profile is `contract_only` / unauthorized, so this gate is intentionally `BLOCKED`.
- **G12 performance evidence** — requires measured Web p95 frame-time evidence and an explicit budget. Current Jette profile has no such measurement, so this gate is intentionally `BLOCKED` rather than inferred from feature counts.

### Current expected Jette readiness

- G7: PASS
- G8: PASS
- G9: BLOCKED — building collision not proven in owned runtime
- G10: PASS
- G11: BLOCKED — streaming contract only
- G12: BLOCKED — measured Web budget absent

A normal rebuild may still finish as `LABO_DATA_READY` while showing these blockers. A `--require-ready` rebuild must fail until all production-readiness blockers are resolved.
