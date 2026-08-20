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

## V3 production path

1. Geometry rebuilds committed/cached UrbIS runtime outputs for buildings, street surfaces, street axes, **tram network**, and train network.
2. OSM environment rebuilds from the committed Jette ODbL cache.
3. Finish materials execute deterministically from the Jette zone profile and existing runtime bindings.
4. `AUTHORED_OVERRIDE > GENERATED_BASE` is hard policy; the authored Jette station brick/stone treatment is preserved.
5. Jette StreetSurfaces stay neutral because current source semantics do not safely isolate sidewalks or asphalt composition.
6. Roof, glass, concrete, generic brick/stone and vegetation-surface families remain explicit `missing_source` skips rather than fabricated output.
7. Life remains `disabled` until an existing ambient system can be parameterized safely by `zone_id`.
8. Final proof reruns hard G1→G6; any hard gate failure returns non-zero.
9. Dedicated CI runs two complete rebuilds and requires byte-identical tracked outputs plus zero diff from the committed nominal outputs.
10. The machine never promotes LABO to JOUABLE; promotion remains human-only.

## Current gates

- **G1** sources / CRS / licence
- **G2** spawn / ground / bounds
- **G3** buildings + streets runtime content
- **G4** Godot runtime finish hooks
- **G5** source-backed OSM environment
- **G6** deterministic finish-material bindings + authored override preservation

G7+ are deliberately not claimed by this lot. Collision, outlier, streaming/performance, generated-file ownership and landmark non-regression gates remain separate implementation work.
