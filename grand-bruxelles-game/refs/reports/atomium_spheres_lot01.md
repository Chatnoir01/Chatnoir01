# Atomium spheres — lot 01

## Objective
Make the nine existing Atomium spheres read less like smooth generic metal and more like the source-described stainless triangular cladding, without changing hero topology or unresolved architecture.

## Source boundary
Existing repository evidence only:
- official Atomium restoration source: stainless-steel skin; triangular cladding panels; 15 smaller triangles with false joints;
- official Atomium construction source: 48 equal spherical triangles per sphere;
- exact contemporary seam coordinates remain unresolved.

Hard invariant:
- `sphere_panel_exact_runtime_layout_resolved=false`
- `no_invented_panel_seams_without_layout_source=true`

Therefore the runtime cue is explicitly **semantics-only**. Its UV placement is authored presentation and is not a surveyed facade seam map.

## Diagnostic — max 3 gaps
1. Sphere skin currently reads as a smooth generic metallic ball at gameplay distance.
2. Source-resolved triangular cladding semantics are not readable in the current material.
3. Exact seam coordinates and hublot placement are not source-resolved and must not be invented in this lot.

## Single correction
Apply one generated triangular panel-semantics cue texture to the existing shared stainless sphere material. Do not move or replace spheres, tubes, terrain, supports, pavilion, park, roads or transit.

## Witness
Deterministic CI captures:
- BEFORE: PR base SHA
- AFTER: PR head SHA
- same capture harness
- same Atomium DTM
- same reflection environment
- same camera transform
- same FOV 43°
- same resolution 1280×720
- no player/NPC/traffic in the witness

CI rejects:
- invisible visual delta;
- global/background-dominant delta;
- diff escaping the Atomium-dominant central frame.

## Gate 3s
PENDING until the generated BEFORE/AFTER artifact is inspected by a human.

PASS only if the spheres read more architecturally in the normal witness without becoming a generic sci-fi grid.
FAIL if the cue is too weak, too strong, misleading, or the visible gain is not immediate.

## Remaining risk
The cue communicates sourced panel semantics but is not an exact seam map. Supports, pavilion height/detail, exact global yaw, hublot layout and photo-matched lighting remain unresolved and outside this lot.

## Next lot if PASS
Atomium #2 — immediate base/pavilion/ground only, source-gated separately.
