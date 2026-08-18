# Production Wall

## Main
- observed_main_before_this_edit: `213a7a851c24866fef91e9efa0e011786b197ca8`
- last_verified: `2026-08-18T22:52Z`
- rule: `main` is the sole production truth. Re-read live main, open PRs, changed-file ownership and this wall before every branch, merge, rejection or production claim.
- six-point campaign status: **6/6 merged**.
- latest substantive zone visual change before this QA merge: **#819 Ixelles LABO facade articulation**.
- latest production QA truth: **#833 Atomium anchor semantics**.

## Six-point campaign — SHIPPED
1. **#749** Midi official StreetSurface collision.
2. **#750** player melee feel.
3. **#752** PhysicalCarB primary for Mission 01 with persistence/reward flow.
4. **#765** Midi/Fonsny full source-backed entrance; `4.9336%` >3 RGB, `4.2255%` >8, bbox `903x185`, human PASS.
5. **#766** LABO→JOUABLE fail-closed gate; Midi remains sole JOUABLE.
6. **#767** Web artifact-only publication + live-main Branch Hygiene.

## Atomium / Heysel — current truth
- Production direct arrival remains the player path itself: current Atomium anchor + `120 m` X offset, FOV `69`, pitch `20°`, spring `4.9 m`. Do not move this camera to rescue a visual candidate.
- Production mounts accepted DTM + official `LandCover.1038`. #806 basin component is shipped but intentionally unmounted (`runtime_approved=false`, `realism_complete=false`).
- **#814 CLOSED WITHOUT MERGE**: mounted basin technical PASS but player-eye human FAIL. Do not move basin/camera or lower its gate.
- **#817 CLOSED evidence-only**: official StreetSurface coverage exists strongly around the legitimate arrival.
- **#820 CLOSED WITHOUT MERGE**: 160 m DTM-draped neutral StreetSurface treatment technical/source PASS but numerical + human player-eye FAIL. Do not retry with stronger colour, wider radius, moved geometry/camera or lower thresholds.
- **#833 SHIPPED QA**: production DTM `atomium_reference=[148093.22038698208,176091.76722726133]` resolves exactly to the Atomium ticket-shop POI witness `node/13156161818`, not to a proven architectural centre. Dedicated run `32192754697` PASS: `ticket_error_m=0.000000`; separate monument-relation position witness projects at EPSG `148084.276,176064.182`, `28.999 m` away; official-ortho separation `144.916 px` at `0.2 m/px`.
- #833 hard status is authoritative: `current_reference_semantically_valid_as_architectural_center=false`, `replacement_anchor_approved=false`, `runtime_move_authorized=false`, `support_pillar_geometry_authorized=false`, `realism_complete=false`.
- **#836 CLOSED WITHOUT MERGE** after #833 advanced main; Branch Hygiene failed on its old `e19c4eb6...` base. Its frozen orthophoto/Hough yaw method is evidence only. Any yaw-modulo-60 audit must be rebuilt from live main without changing thresholds/manual fitting.
- #585 remains an orthophoto evidence bank only. #2 remains a long-lived Laeken/Jette specialist. Never merge either wholesale.
- Old #2 support feet (`centre ± (8 m,5 m)`, 2.4 m tubes) are provisional/invented visualization and must never be promoted as source truth.

## Grand-Place — retained production truths
- Canonical camera #753/#711: `[319.01,1.72,-535.20]` → `[321.91,11.8,-485.66]`, FOV `62`, 1280×720.
- Correct Hôtel de Ville owner = UrbIS building `1655673`.
- **#783 SHIPPED** right-gallery B1500 fidelity correction; human PASS.
- #790/#792/#794/#797 are evidence/source chain only; no automatic motif transfer.
- Maison des Brasseurs same-building retry path remains closed by #755/#758 screen-space upper bound.

## Active ownership / stale workspaces
- Always re-read open PRs because concurrent agents move quickly.
- At this observed main there is **no current Atomium implementation owner** after #836 closed. #585/#2 are evidence/specialist workspaces only.
- #823 owns civilian vehicle visuals. #824 owns Grand-Place Town Hall dormers. #835 owns generic OSM glazing but was created from pre-#833 main and must satisfy exact-current-main policy before any integration.
- #813/#812 and older #652/#643/#596/#592 are stale historical workspaces unless rebuilt from live main.
- #2/#11 long-lived geography specialists: never merge wholesale; extract one coherent exact-current-main lot only.
- Closed evidence/source workspaces own nothing.

## Important rejected paths — do not repeat
- Atomium basin #814 and neutral StreetSurface #820: player-visible FAIL; no cosmetic rescue.
- Atomium support feet from #2: invented provisional geometry; forbidden as truth.
- Maison des Brasseurs same-building, #781 unsupported arches, #787 off-camera face, #773 road markings, #738 generic roofs, old Fonsny micro-proxies, raw Maison du Roi LoD2, Ducs blind LoD2, Roi d'Espagne primitive proxy and La Brouette generic windows remain rejected paths.

## Important invariants
- Green CI alone does not authorize a visual merge; human full-frame verdict overrides numeric PASS.
- Exact-current-main is mandatory; live `behind > 0` is an integration blocker.
- One defect may have only one active implementation owner.
- UrbIS owns official geometry. Heritage/orthophoto/OSM evidence may constrain presentation only after explicit registration and uncertainty.
- Source acquisition, registration, metric conversion and runtime implementation are separate decisions.
- No threshold reduction, camera rescue or geometry displacement after visual FAIL.
- **Atomium specifically:** do not move hero, spawn, terrain reference, basin or supports until a replacement architectural centre is separately resolved and approved. Do not build bipods until centre + yaw + support-foot evidence are all resolved.

## NOW / NEXT / LATER
- **NOW Atomium:** #833 is shipped. Current anchor semantics are invalid for an architectural-centre claim, but no replacement is approved.
- **NEXT Atomium:** evidence-only registration of a replacement architectural centre from a source-backed monument/base-pavilion footprint against the frozen official 2024 orthophoto, with explicit uncertainty. The OSM relation position is only a witness, not an approved centre. No runtime movement in this lot.
- **NEXT Atomium yaw:** rebuild the frozen #836 yaw-modulo-60 method separately from live main if no competing owner exists. Do not combine yaw and centre approval into one claim.
- **LATER Atomium:** only after centre + yaw are independently resolved, source support-foot coordinates; only then consider a separate bipod runtime/A-B lot.
- **NEXT Grand-Place:** continue current source-registration chain only under its active ownership; do not collide with #824.

## Shift handoff
- What changed: #833 shipped QA evidence proving the production DTM Atomium reference is semantically a ticket-shop point rather than a proven monument centre. #836 was closed stale after Branch Hygiene failed on the pre-#833 base.
- What is proven: current reference semantics are invalid for a hero-centre claim; ticket witness match is exact within CI; monument relation witness is ~29 m away in official orthophoto coordinates.
- What is NOT proven: the correct replacement centre, exact global yaw/parity, bipod feet, support geometry or any runtime relocation.
- What must not be redone: basin/StreetSurface cosmetic rescue, camera rescue, old #2 support feet, treating the relation coordinate alone as the new centre, or moving any runtime component before centre evidence is approved.
- Exact next action: re-read live main/owners, then create one evidence-only replacement-centre registration lot from the exact current main if Atomium remains unowned. No runtime movement.
