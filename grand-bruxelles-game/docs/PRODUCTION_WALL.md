# Production Wall

## Main
- observed_main_before_this_edit: `213a7a851c24866fef91e9efa0e011786b197ca8`
- last_verified: `2026-08-18T23:10Z`
- rule: `main` is the sole production truth. Re-read live main, open PRs, changed-file ownership and this wall before every branch, merge, rejection or production claim.
- six-point campaign status: **6/6 merged**.
- latest production QA truth: **#833 Atomium anchor semantics**.
- latest substantive zone visual change before #833: **#819 Ixelles LABO facade articulation**.

## Atomium / Heysel — current truth
- Production direct arrival remains current Atomium anchor + `120 m` X offset, FOV `69`, pitch `20°`, spring `4.9 m`. No camera rescue.
- Production mounts accepted DTM + official `LandCover.1038`. #806 basin component is shipped but intentionally unmounted (`runtime_approved=false`, `realism_complete=false`).
- **#814 CLOSED WITHOUT MERGE**: mounted basin technical PASS but player-eye human FAIL. Do not move basin/camera or lower its gate.
- **#817 CLOSED evidence-only**: official StreetSurface coverage exists strongly around the legitimate arrival.
- **#820 CLOSED WITHOUT MERGE**: 160 m DTM-draped neutral StreetSurface treatment technical/source PASS but numerical + human player-eye FAIL. Do not retry with stronger colour, wider radius, moved geometry/camera or lower thresholds.
- **#833 SHIPPED QA**: production DTM `atomium_reference=[148093.22038698208,176091.76722726133]` resolves exactly to the Atomium ticket-shop POI witness `node/13156161818`, not to a proven architectural centre. Dedicated run `32192754697` PASS: `ticket_error_m=0.000000`; separate monument-relation position witness projects at EPSG `148084.276,176064.182`, `28.999 m` away; official-ortho separation `144.916 px` at `0.2 m/px`.
- #833 hard status is authoritative: `current_reference_semantically_valid_as_architectural_center=false`, `replacement_anchor_approved=false`, `runtime_move_authorized=false`, `support_pillar_geometry_authorized=false`, `realism_complete=false`.
- **#836 CLOSED WITHOUT MERGE** after #833 advanced main. Its frozen Hough yaw fit also independently failed its source gate (`side_rms_m=0.848411 > 0.75 m`). Never loosen that threshold or reuse its best triad as accepted centre/yaw evidence.
- Historical UrbIS3D building `1651628` is not automatically the circular structural base: its official ground envelope is roughly `40x27 m`, not the documented 26 m circular plan. Do not rename it as the replacement centre without new evidence.
- #585 remains an orthophoto evidence bank only. #2 remains a long-lived Laeken/Jette specialist. Never merge either wholesale.
- Old #2 support feet (`centre ± (8 m,5 m)`, 2.4 m tubes) are provisional/invented visualization and must never be promoted as source truth.

## Active Atomium centre-discovery contract
- Current workspace: `qa/atomium-base-pavilion-footprint-213a7a8`, evidence-only; no runtime ownership.
- Pinned official source: specialist commit `5525ad370ff4ddc1d34b02ab82cc3fbba3f56cb7`, `urbis:BuildingFootprint`, exact Git blob `517c6f0aa6823bcc0cd76ca0cd43e77a709c89f9`, 9,518 features. Long-lived specialist branch remains non-mergeable wholesale.
- Authoritative plan fact retained from urban.brussels: base sphere rests on a **circular pavilion 26 m in diameter**.
- Frozen discovery filters before first result: centroid within `80 m` of the independent monument-relation position witness; equivalent-circle diameter `22.1..29.9 m`; bbox aspect ratio `<=1.25`; bbox max span `<=32 m`; circularity `4πA/P² >=0.75`.
- Zero candidates is a valid fail-closed evidence result. Multiple candidates are ambiguous. Exactly one candidate remains only a candidate until a separate registration against the frozen official 2024 orthophoto with explicit uncertainty.
- Never loosen the filters after seeing results. `replacement_anchor_approved=false`, `runtime_move_authorized=false`, `support_pillar_geometry_authorized=false`, `yaw_authorized=false` remain hard until separate evidence gates pass.

## Grand-Place — retained production truths
- Canonical camera #753/#711: `[319.01,1.72,-535.20]` → `[321.91,11.8,-485.66]`, FOV `62`, 1280×720.
- Correct Hôtel de Ville owner = UrbIS building `1655673`.
- **#783 SHIPPED** right-gallery B1500 fidelity correction; human PASS.
- #790/#792/#794/#797 are evidence/source chain only; no automatic motif transfer.
- Maison des Brasseurs same-building retry path remains closed by #755/#758 screen-space upper bound.

## Active ownership / stale workspaces
- Always re-read open PRs because concurrent agents move quickly.
- Atomium centre discovery owns only its contract/scanner/workflow/wall. It does **not** own runtime relocation, yaw or supports.
- #823 owns civilian vehicle visuals. #841/#824 family owns current Town Hall details. #835 owns generic OSM glazing but must satisfy exact-current-main policy before integration.
- #813/#812 and older #652/#643/#596/#592 are stale historical workspaces unless rebuilt from live main.
- #2/#11 long-lived geography specialists: never merge wholesale; extract one coherent exact-current-main lot only.
- Closed evidence/source workspaces own nothing.

## Important rejected paths — do not repeat
- Atomium basin #814 and neutral StreetSurface #820: player-visible FAIL; no cosmetic rescue.
- Atomium support feet from #2: invented provisional geometry; forbidden as truth.
- #836 failed Hough triad: do not lower RMS thresholds or manually choose the same triad.
- Maison des Brasseurs same-building, #781 unsupported arches, #787 off-camera face, #773 road markings, #738 generic roofs, old Fonsny micro-proxies, raw Maison du Roi LoD2, Ducs blind LoD2, Roi d'Espagne primitive proxy and La Brouette generic windows remain rejected paths.

## Important invariants
- Green CI alone does not authorize a visual merge; human full-frame verdict overrides numeric PASS.
- Exact-current-main is mandatory; live `behind > 0` is an integration blocker.
- One defect may have only one active implementation owner.
- UrbIS owns official geometry. Heritage/orthophoto/OSM evidence may constrain presentation only after explicit registration and uncertainty.
- Source acquisition, candidate discovery, registration, metric conversion and runtime implementation are separate decisions.
- No threshold reduction, camera rescue or geometry displacement after a visual FAIL.
- **Atomium specifically:** do not move hero, spawn, terrain reference, basin or supports until a replacement architectural centre is separately resolved and approved. Do not build bipods until centre + yaw + support-foot evidence are all resolved.

## NOW / NEXT / LATER
- **NOW Atomium:** discover whether the pinned official UrbIS BuildingFootprint slice contains a source-bounded 26 m circular-pavilion candidate under the predeclared filters. Evidence-only; no runtime.
- **NEXT Atomium if unique candidate:** register that exact official footprint against the frozen 2024 orthophoto with explicit uncertainty. The OSM relation position remains only a witness. No runtime movement in the registration lot.
- **NEXT Atomium if none/multiple:** keep centre unresolved and seek a different authoritative footprint/base source; do not loosen filters or pick by eye.
- **LATER Atomium:** independently rebuild yaw from live main under frozen source gates; only after centre + yaw are resolved may support-foot evidence begin. Bipod runtime comes last.

## Shift handoff
- What changed: #833 shipped QA proof that the production DTM Atomium reference is semantically the ticket-shop point, not a proven monument centre. #836 was closed stale and its Hough yaw fit also failed its own RMS gate.
- What is proven: current anchor semantics are invalid for an architectural-centre claim; the relation witness is ~29 m away; no replacement is approved.
- What is being tested now: official BuildingFootprint candidate discovery under a documented 26 m circular-plan constraint and frozen geometry filters.
- What is NOT proven: correct replacement centre, global yaw/parity, bipod feet, support geometry or any runtime relocation.
- Exact next action: run the centre-discovery workflow on exact-current-main. Preserve zero/ambiguous as valid evidence outcomes. If unique, register against official orthophoto in a separate PR before any movement.
