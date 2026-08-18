# Production Wall

## Main
- observed_main_before_this_edit: `8809b5ed25f4dd67a337af9cd9669c7602f0499e`
- last_verified: `2026-08-18T04:44:30Z`
- latest_verified_publication: `f713299f23aff7805228db00706ccfec9f8771fd` — Web publication after QA #753. #758 is QA/data only; re-read live main before assuming a later publication.
- latest substantive gameplay: #749 official Midi street-surface solidity + #750 player melee feel.
- rule: `main` is sole production truth. Re-read live main, open PRs, changed-file ownership and this wall before every branch, merge, rejection or production claim.

## Active ownership
- #752 — vehicle / Mission 01 physical B primary. Current head `c4b62eb2...` has its full listed gates green, but it started from an older production base and is not shipped until synchronized/revalidated from live main and merged. Do not overlap mission/vehicle files.
- #11 — long-lived rest-of-Brussels mapping/data/tooling specialist. Never merge wholesale; extract one current-main checkpoint only.
- #2 — long-lived Laeken + Jette / Heysel / Atomium specialist. Never merge wholesale; extract one current-main checkpoint only.
- #759 generic OSM facade articulation is CLOSED WITHOUT MERGE after main advanced through #758. It owns nothing now; do not reopen stale.
- Old #665/#652/#643/Bourse/Atomium/NPC drafts are stale evidence/specialist workspaces, not current-main integration candidates.

## Recently shipped
- #758 / `8809b5ed...` — evidence-only full-building Maison des Brasseurs projection audit; official building `1639974` persisted from UrbIS LoD2, no runtime/material/scene change.
- #757 / `289bca77...` — production wall recorded #755 exact single-face rejection.
- #753 / `1296b057...` / publication `f713299f...` — canonical Grand-Place camera contract. Exact #711 witness: 1280x720, camera `[319.01,1.72,-535.20]`, target `[321.91,11.8,-485.66]`, FOV 62. Clean image SHA-256 `d869abcbd1cbc500954b85e5de07ee25ab4f2ecf96f0d5a593e9762a762d0798`.
- #750 / `4615e481...` — player melee readable-weight lot.
- #749 / `815f5a6e...` — official Midi StreetSurface families made solid.
- #711 — clean Grand-Place player-eye witness pattern, now backed by #753 shared camera contract.

## Maison des Brasseurs — CLOSED SAME-BUILDING PATH
Official source target is UrbIS building `1639974`; face `10945501` was the first exact wall experiment.

### #755 exact face result
- exact five official vertices / three official triangles; `details=0`, offset=0, no neighbor hide, shadow disabled.
- canonical run `32099235835`, artifact `9310999041`, digest `sha256:58991676c2359c8583c7f51cca704b21c94170f799dadac35f379e29796fdc15`.
- frozen metrics: ratio >3 RGB `2.5597%` PASS; >8 RGB `2.5597%` PASS; bbox `96x287` FAIL versus frozen `300x260` because width `96 < 300`.
- human full-frame FAIL: visible exact wall reads as a thin pale slab/gable, not a recognizable Maison des Brasseurs facade in three seconds.

### #758 decisive full-building upper bound
- source: official UrbIS 3D Constructions building `1639974`, one solid, 6 WALLSURFACE faces, CC0-1.0.
- source artifact binary SHA-256 `7d5927902e43d74b62120436a4f928c56f33185c40428ff4c18aa15fa51b56e1`; committed semantic canonical JSON SHA-256 `9969e6e2f0e02cb58d9f89e27454e09cca15e75ea52f5724c773df5929a90dad`; package SHA `cf8449d1...`.
- dedicated run `32099922488` PASS; artifact `9311195340`; zip digest `sha256:b56314a4b02df0ed8fcb2281653d1ecae649ba4c67af52c9f2ac8c3bb179660f`.
- projection calibrates to the real #755 render: face `10945501` = `95.973x287.869 px` versus rendered `96x287`.
- all six official wall faces are edge-connected.
- optimistic union of ALL six WALLSURFACE faces = `174.526x287.869 px`.
- width upper bound is only `58.175%` of the already-frozen 300 px width requirement.
- `can_any_same_building_wall_subset_meet_755_width_gate=false` and `recommend_same_building_visual_retry=false`.
- because the union includes every official wall regardless of occlusion/backface, no subset of the same building can be wider.

### Hard conclusion
STOP all visual retries restricted to building `1639974` from the canonical camera. Do not lower thresholds, move the camera, hide neighbors, widen/invent geometry, brighten material for pixel count, or add decorative detail after the base geometry failure. A future Brasseurs attempt would require a genuinely broader separately sourced product scope beyond this single official building; otherwise Brasseurs is closed.

## Other rejected paths — do not repeat
- #740 Fonsny canopy-only: `1.2509% / 1.0272% / 649x149` versus locked `3.00% / 1.50% / 700x160`; insufficient 3-second impact.
- #738 generic street-level roofs: `>3 RGB = 0.0`; no player value from legitimate camera.
- #737 additive Fonsny porch: exact-zero visible gain.
- #696 Brasseurs detached primitive overlay: technical PASS, human FAIL; scaffold, not facade.
- Maison du Roi raw UrbIS LoD2, Ducs de Brabant blind LoD2 mass, Roi d'Espagne primitive dome/proxy and La Brouette generic window grid remain previous human fidelity failures.
- never use `Vector3(324.9581,3.3,-512.8388)` as “#711”; #753 shared camera contract is the sole Grand-Place camera truth.

## NOW / NEXT / LATER
- NOW: production HEAD observed `8809b5ed...`. No failed Brasseurs runtime is in production. #752 owns vehicle/Mission 01 but is unmerged. Generic OSM articulation #759 is closed stale.
- NEXT Centre action: leave Brasseurs. Use the canonical #753 Grand-Place witness to identify the largest source-backed production geometry occupying the visually weak/blank screen mass, with an evidence-only screen-space ownership audit first. Do not choose a landmark by name before the node/building ID is proven.
- Selection rule: choose a large normal-player-visible defect that is not already a known rejected pathway and is not owned by another PR. If the large screen owner resolves to Maison du Roi/Ducs/Roi d'Espagne/La Brouette in a previously rejected form, do not repeat that form; either find a different source-backed correction strategy or move to another Centre defect.
- LATER: generic OSM articulation may be rebuilt from then-live main only if still valuable and unowned, preserving its frozen Anneessens gate. Vehicle integration remains #752's ownership.

## Known visible debt
- canonical Grand-Place view remains visually sparse and weak; large blank/generic building masses dominate, while Brasseurs cannot lawfully be enlarged to solve it.
- Midi/Fonsny entrance remains generic; additive detail and canopy-only correction were insufficient from normal player distance.
- physical B vehicle as Mission 01 primary remains unshipped until #752 is current-main integrated.

## Important invariants
- green unmerged PRs are not shipped progress.
- one defect may have only one active implementation.
- human full-frame verdict overrides green CI for visual lots.
- UrbIS owns official geometry where available; photo measurements are image-space constraints, not survey geometry.
- Commons/photo pixels are not shipped by current Centre contracts.

## Shift handoff
- What changed: #755 proved the exact Brasseurs wall is visible but only 96 px wide; #758 proved even all six official walls together max out at 174.526 px, so the same-building Brasseurs path is mathematically closed under the frozen player-eye gate. #759 generic facade articulation was closed stale after main advanced.
- What is proven: Brasseurs same-building geometry cannot satisfy the 300 px width requirement from the canonical #753/#711 camera without violating source/gate rails.
- What is NOT proven: which exact production node/building owns the large weak screen mass in the canonical Grand-Place view, or which next Centre correction will pass a human 3-second gate.
- What must not be redone: any building-1639974 Brasseurs visual retry, camera rescue, threshold lowering, destructive neighbor hide, geometry widening/invention, #703 detached overlay, stale #759 merge.
- Exact next action: re-read live main/owners, then run one evidence-only canonical-camera screen-space owner audit of the large Grand-Place mass. No new visual runtime until that owner is identified and its previous failure history is checked.
