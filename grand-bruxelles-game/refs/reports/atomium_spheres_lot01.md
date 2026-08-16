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
1. Sphere skin previously read as a smooth generic metallic ball at gameplay distance.
2. Source-resolved triangular cladding semantics were not readable in the current material.
3. Exact seam coordinates and hublot placement remain unresolved and are intentionally not invented in this lot.

## Single correction
Apply one generated triangular panel-semantics cue texture to the existing shared stainless sphere material. Do not move or replace spheres, tubes, terrain, supports, pavilion, park, roads or transit.

## Red proof
Initial test revision failed exactly because the smooth `main` material had no panel-semantics surface cue:
- workflow: `Grand Bruxelles Atomium Hero Ground Oblique`
- failure: `ATOMIUM_SPHERE_SKIN_SEMANTICS_FAIL: panel-semantics surface cue texture missing`

## Green proof
After the correction:
- source-bounded sphere skin semantics test: PASS;
- Atomium hero ground-oblique capture: PASS;
- direct playable Atomium spawn: PASS;
- general Grand Bruxelles Game CI: PASS;
- deterministic sphere-skin BEFORE/AFTER workflow: PASS.

## Witness
Deterministic CI captures:
- BEFORE: PR base SHA
- AFTER: tested head `b6b41bbde40806c3dd942f4b6d543222ba1510bf`
- same capture harness
- same Atomium DTM
- same reflection environment
- same camera transform
- same FOV 43°
- same resolution 1280×720
- no player/NPC/traffic in the witness

Final A/B metrics:
- changed pixels: `0.5716%`
- changed pixels outside Atomium-dominant frame: `0.00%`
- changed bounding box: `460x484`

The first visual attempt was rejected by the human gate because the seams read as an overly strong geodesic grid. The same lot was corrected by removing the vertical grid read and softening the joint cue before the final witness.

## Gate 3s
**PASS**

Reason: the final AFTER gives the larger spheres a visible triangular-cladding read without overpowering the stainless form or looking like the rejected generic sci-fi grid. The improvement is localized to the Atomium and is visible at the normal deterministic witness distance.

## Remaining risk
The cue communicates sourced panel semantics but is not an exact seam map. Supports, pavilion height/detail, exact global yaw, hublot layout and photo-matched lighting remain unresolved and outside this lot.

## Next lot
Atomium #2 — immediate base/pavilion/ground only, source-gated separately.
