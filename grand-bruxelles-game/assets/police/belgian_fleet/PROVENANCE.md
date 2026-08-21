# Belgian police fleet — source inventory and integration gate

Integration base: `main@20dc44a6ce5e67fda6a4c876abfcab0a86f52d08`

This lot turns five existing Midi traffic/parked visual slots into a Belgian police fleet **without changing physics, collision, traffic motion, roads, UrbIS, OSM, or geography**. The runtime uses project-original procedural reference bodies and the existing project-original police decal/light API. Exact third-party geometry is fail-closed unless a lawful, Godot-importable authored asset is present.

## Uploaded source inventory

| Slot | User-supplied source | SHA-256 | Format inspection | Repository decision |
| --- | --- | --- | --- | --- |
| POL-BE-01 | `Sans+titre.zip` | `999cb77cf6bad64c69a357df1d3a2fba4a32b01a5ee99d0f3d1df2d701dd0583` | ZIP contains `model.dae`; DAE identifies `Ford_Mondeo_2006`, `Police`, `Bruxelles_CAPITA...`, author metadata `Alex101` | Reference only until explicit redistribution/license evidence is recorded. Runtime uses a project-original sedan silhouette. |
| POL-BE-02 | `4f990d-Belgian Police Skoda Octavia VRS Break.rar` | `9a56fca40caa1143dfea810de059d5558bf2eec521bfc046483d44fe49a2985a` | GTA V `.yft/.ytd` variants for GENT and SCHAERBEEK | **Do not commit or convert for production** without compatible rights to all source geometry/textures. Runtime uses a project-original estate silhouette. |
| POL-BE-03 | `Volvo XC60 Bredene-De Haan Police ELS.rar` | `f9fb467bfe9bb8115fcde34791580700a4256883bf01df2b53c7fca68d76680d` | GTA V `police3.yft/.ytd` + ELS XML | **Do not commit or convert for production** until redistribution/derivative rights are proven. Runtime uses a project-original SUV silhouette. |
| POL-BE-04 | `Lokale+politie+-+patrouillewagen+4.skp` | `e29c8efd94ba0efdaf4004925789570fddfeddaf2d387e9e0ace9dee570b1cc6` | SketchUp `.skp`, not directly importable by Godot | Reference only pending conversion path and license evidence. Runtime uses a project-original patrol/hatch silhouette. |
| POL-BE-05 | `generic_sport_coupe_car.glb` | `5c3d5836d19b12347d9ab8e044fe9593b15255d211282ffa374f140e58d9eabd` | Godot-compatible GLB; MMC Works generic sport coupé | Licensed generic base may be mounted later at `res://assets/vehicles/mmc_generic_sport_coupe/generic_sport_coupe.glb`; runtime falls back safely when bytes are absent. |

Additional supplied files inspected in the same intake:

- `generic_sedan_car(1).glb` — SHA-256 `a021faaf6427bebae58c9f380502d901d33415130772f4010c64bf4a2d84f1e2`; MMC Works generic sedan candidate, optional authored base path `res://assets/vehicles/mmc_generic_sedan/generic_sedan.glb`.
- `2_free_low_poly_cars.glb` — SHA-256 `4fa02d83a8dbe45e9ca73d0ff39ce15b0c74f48c224bb9b5cff23481908d601a`; two civilian low-poly cars. The surfaced Fab listing confirms the pack is free and provides GLB/glTF, but it does not expose a concrete license term, so it is not redistributed by this PR.

## Runtime fleet delivered by this branch

1. `brussels_capitale_sedan` — Bruxelles-Capitale marked sedan reference.
2. `skoda_octavia_break_reference` — local-police estate/break reference.
3. `volvo_xc60_bredene_de_haan_reference` — local-police SUV reference.
4. `lokale_politie_patrouillewagen_reference` — local patrol/hatch reference.
5. `brussels_rapid_response_coupe` — rapid-response coupé using a procedural body now, with an optional MMC authored-base mount when that licensed GLB is present.

The first three profiles replace parked Midi visual slots; the last two replace existing moving ambient-traffic **visuals only**. Their original Midi movement remains authoritative.

## Non-negotiable gates

- No GTA `.yft/.ytd` bytes in the repository.
- No conversion of GTA-derived geometry merely to bypass its source format.
- No `.skp`/DAE redistribution until source license is explicit.
- No police gameplay, collision, physics, driving, dispatch, road, UrbIS, OSM, or geography mutation in this lot.
- Original `ProductionVisual` remains recoverable through the runtime A/B visibility method.
- Exact authored third-party geometry is **not** marked production-authorized by this runtime.
- Web/PC performance and 2m/5m/8m visual owner review remain required before an authored high-detail base is promoted.
