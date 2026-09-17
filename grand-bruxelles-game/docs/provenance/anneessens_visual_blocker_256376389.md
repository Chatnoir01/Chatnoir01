# Anneessens visual-blocker provenance witness

Status: evidence-only; no geometry, camera, collision, material, placement, promotion, or runtime authorization change.

## Exact repository basis

- live `main`: `8938792700837c6e53bf9661f0c304dfeba84897`
- merged Environment lineage: PR #2173
- measured predecessor head: `62c90e45236b6635aac56d6757e2fba2c90f83ce`
- workflow: `Grand Bruxelles Anneessens Automatic Road Player Witness`
- run: `35162881001`
- artifact: `automatic-road-1382734012-player-witness` (`10473239022`)
- artifact digest: `sha256:fc8a31499d29cef2d269aeae7ee638894cbda22be2966fcb3928919b5121505e`
- capture: `automatic_road_1382734012_player.png`, 1280x720

## Deterministic blocker measurement

The existing frozen player-view witness sampled the right half of the frame without moving the camera or source geometry. Samples `(760,360)` and `(900,360)` were unobstructed. Sample `(1100,360)` hit:

```text
collider_path=/root/@SubViewport@15/Main/BrusselsOSM/GeneratedBuildings/Building_256376389_0
collider_name=Building_256376389_0
collider_class=CSGPolygon3D
owner=
source_path=
road_support_osm_ids=[]
hit=(-289.141,1.695,-198.842)
distance_m=20.626
```

This pins the severe near-field right-side occluder observed in the retained human REJECT to generated BrusselsOSM building node `Building_256376389_0`, 20.626 m from the frozen production camera ray at screen sample `(1100,360)`.

## Canonical source resolution

Independent current-main source/runtime conformance already resolves this generated token exactly. `game/tests/anneessens_osm_building_runtime_conformance_test.gd` binds `TARGET_OSM_ID := 256376389` to `SOURCE_PATH := res://data/osm/vertical_slice_01.game.json`, requires exactly one source building with OSM `256376389`, and requires exactly one generated `CSGPolygon3D` whose name begins `Building_256376389`. It further proves the runtime solid preserves the source-derived five-vertex footprint, 14.0 m height/depth, center `(-285.4966,-185.4604)`, and collision.

Therefore the blocker identity is now source-resolved as OSM `256376389` from `data/osm/vertical_slice_01.game.json`; source identity proven=true. This resolution is identity/provenance evidence only. It does not authorize changing that source geometry or its collision to rescue the rejected frame.

## Ownership boundary

The measured collider still exposes no `grand_bruxelles_owner`, `source_path`/`grand_bruxelles_source_path`, or `road_support_osm_ids` metadata. Those missing runtime metadata fields must not be fabricated. Canonical identity comes from the independent source/runtime conformance contract above, not from interpreting the generated node token in isolation.

Do not move/delete/resize this building, change the camera/FOV, alter culling, lower a visual threshold, or assign synthetic provenance to make the Anneessens frame pass. Any future geometry/material correction must first respect the canonical OSM source and route through the appropriate source/Environment ownership boundary.

## Authorization

- `geometry_change_authorized=false`
- `visual_acceptance=false`
- `destination_advertisable=false`
- `jouable_authorized=false`

This receipt is provenance/QA evidence only and has zero production render/runtime cost.
