# Production Wall

## Main
- observed_main_before_this_edit: `36ef8d6016f92030bcf040831b75fac513aa148d`
- last_verified: `2026-08-18T04:32:00Z`
- latest_verified_publication: `f713299f23aff7805228db00706ccfec9f8771fd` — Web publication after QA #753.
- latest substantive gameplay changes: #749 official Midi street-surface solidity + #750 player melee feel.
- rule: re-read live `main`, open PRs, changed-file ownership and this wall before every branch, merge, rejection or production claim.

## Active ownership
- #752 — vehicle/Mission 01. Current head `c4b62eb2...` is green for Mission Save Contract, Primary Physical Vehicle, Game CI, Test, Branch Hygiene, Web, PC, Photo Match and Performance, but it started from older production `deb16461...`. Its files now include mission drive/return/runtime state plus mission regression tests and the physical-vehicle workflow/test. It is not production until synchronized/revalidated against live main and merged. Do not overlap its files.
- #11 — long-lived rest-of-Brussels mapping/data/tooling specialist. Never merge wholesale; extract one coherent checkpoint from current main.
- #2 — long-lived Laeken + Jette / Heysel / Atomium specialist. Never merge wholesale; extract current-main checkpoints only.
- Old #665/#652/#643/Bourse/Atomium/NPC drafts are stale specialist/evidence workspaces, not current-main integration candidates.
- Grand-Place / Maison des Brasseurs currently has no active implementation owner after #755 was rejected and closed without merge.

## Recently shipped
- #753 / `1296b057...` / publication `f713299f...` — canonical Grand-Place camera contract is production truth. Exact merged #711 witness = 1280x720, camera `[319.01, 1.72, -535.20]`, target `[321.91, 11.8, -485.66]`, FOV 62. Clean witness PNG SHA-256 `d869abcbd1cbc500954b85e5de07ee25ab4f2ecf96f0d5a593e9762a762d0798`. Brasseurs owner audit from this REAL camera reports 25/25 sampled collision rays with `hit_count=0`, `collider_counts={}`. This proves collision-line clearance only, not absence of non-collidable visual overlap.
- #750 / `4615e481...` — player melee readable-weight lot shipped.
- #749 / `815f5a6e...` — official Midi StreetSurface families made solid on source geometry.
- #743 / `b4973a2...` — generic selected-OSM owner hypothesis for Brasseurs rejected; nearest selected OSM building remains ~90.031492 m from wall `10945501`. Its old camera provenance is superseded by #753.
- #711 — clean Grand-Place player-eye witness pattern, now backed by #753 shared camera contract.
- #680 — Brasseurs photo-plan contract; source/license/hash + exact UrbIS constraints, no runtime geometry.

## Maison des Brasseurs — current truth
- Official building: UrbIS `1639974`.
- Tested official face: wall `10945501`.
- Exact wall evidence: five official vertices / three official triangles, span ~8.749036 m, y 0..24.746 m. UrbIS owns placement, shape and vertical anchors.
- Generic selected OSM ownership is disproved; do not assign this wall to `Building_306856563` or another distant OSM block.
- `GrandPlace1786758` broad AABB touches the shared-corner neighborhood but is not proven to own wall `10945501`; never hide it wholesale merely to reveal a candidate.
- #753 canonical collision rays are clear. This does not prove that every visual layer is absent in front of the wall.
- #703 did not implement a continuous official wall; it built detached bands/pilasters/windows/arcades, so it is not the base-wall experiment.
- #755 is now the valid single-face experiment. It proves wall `10945501` itself is genuinely visible from the canonical camera when rendered exactly in-place with shadows disabled, but it is too narrow to be a production-quality player-facing unit.

## #755 exact-wall verdict — DO NOT RETRY SINGLE FACE
- Base: `36ef8d6016f92030bcf040831b75fac513aa148d`; final candidate head `a844724b536d145cef0225b84ca17c840406c592`; closed without merge.
- RED-first was clean: source/topology/gates validated, first dedicated failure was only missing runtime.
- Structural GREEN: exactly five official unique vertices / three official triangles, `details=0`, `outward_offset=0`, `hide_neighbor=false`, no `main.tscn`/`project.godot` mutation.
- Candidate shadow was disabled so the visual diff cannot be a #703-style ground-shadow false positive.
- Canonical A/B run `32099235835`; artifact `9310999041`; zip digest `sha256:58991676c2359c8583c7f51cca704b21c94170f799dadac35f379e29796fdc15`.
- Frozen metrics: `ratio3=2.5597%` PASS versus 2.00%; `ratio8=2.5597%` PASS versus 1.00%; changed bbox `96x287` FAIL versus required `300x260` because width `96 < 300`; 23,590 pixels changed at both thresholds.
- Human full-frame verdict: FAIL. AFTER shows the exact source wall as a narrow pale gable/slab at the left of the existing Grand-Place mass. It is visible, but it does not read as a recognizable Maison des Brasseurs facade in three seconds.
- Therefore wall `10945501` alone is permanently rejected as the integration unit. Do not retry by material retune, camera movement, lower thresholds, outward offset, neighbor hide, widening, or post-failure decorative detail.

## Closed / rejected visual paths
- #755 — exact Brasseurs wall `10945501`: source-correct and visible, but only 96 px wide; frozen bbox gate + human 3-second gate FAIL.
- #740 — Fonsny canopy-only replacement rejected: `1.2509% / 1.0272% / 649x149` versus locked `3.00% / 1.50% / 700x160`; insufficient 3-second impact.
- #738 — generic street-level OSM roofs rejected: `>3 RGB = 0.0`; no player value from legitimate camera.
- #737 — additive Fonsny porch rejected: exact-zero visible gain because it sat largely inside/behind existing entrance articulation.
- #696 — Brasseurs detached primitive overlay technical PASS but mandatory human FAIL; scaffold, not coherent facade.
- Maison du Roi raw UrbIS LoD2, Ducs de Brabant blind LoD2 mass, Roi d'Espagne primitive dome/proxy and La Brouette generic window grid remain prior human fidelity failures.

## Blocked / do not repeat
- Never use `Vector3(324.9581,3.3,-512.8388)` as “#711”; #753 shared camera contract is production truth.
- Never lower Brasseurs visual thresholds after a failed render.
- Never retry wall `10945501` alone as the facade unit; #755 answered that question.
- Do not hide `GrandPlace1786758`, invent an outward wall offset, widen official geometry, or brighten material just to increase pixel count.
- Do not return to detached free-standing bars/columns/slabs/arches/window grids or a raw Commons photo quad.
- Commons/photo pixels remain reference/constraint data unless a separate compliant derivative/license strategy is approved.

## NOW / NEXT / LATER
- NOW: production HEAD observed `36ef8d60...`. #755 is closed without merge. No failed Brasseurs runtime is in production. #752 remains an unmerged vehicle owner despite its current green head.
- NEXT Brasseurs step is EVIDENCE FIRST, not another visual skin: use the frozen official UrbIS extraction for building `1639974` to identify whether multiple connected camera-facing WALLSURFACE faces form a broader coherent Maison des Brasseurs frontage/building envelope from the canonical #753 camera. The evidence must list exact face IDs/triangles, connectivity, screen-space projection and source provenance. No runtime or material change in that evidence lot.
- If official same-building faces objectively support a broader coherent frontage with enough projected width, a later fresh visual lot may render that complete official set as one base skin before details. If they do not, stop Brasseurs rather than inventing geometry and choose another unowned high-impact Centre defect.
- Human full-frame 3-second verdict remains mandatory for any later visual candidate.
- LATER: only after a coherent official frontage base passes may a separate lot consider shallow photo-constrained architectural relief.

## Known visible debt
- Grand-Place landmark-house facade/silhouette fidelity remains weak; no production-quality Brasseurs facade has passed the human three-second gate.
- Midi/Fonsny entrance remains generic; additive detail and canopy-only correction were both insufficient from normal player distance.
- Vehicle Mission 01 physical-primary work remains unshipped until #752 is integrated from current main.

## Important invariants
- `main` is the only production truth; green unmerged PRs are not shipped progress.
- One defect may have only one active implementation; close/rebuild stale candidates rather than racing them.
- Human full-frame verdict overrides green CI for visual lots.
- #753 shared camera contract is the sole canonical source for Grand-Place clean player-eye tests.
- UrbIS owns official geometry where available; photo measurements are image-space constraints, not survey geometry.

## Shift handoff
- What changed: #755 completed the missing coherent single-face experiment and was rejected without merge. It proved exact wall visibility but also proved that `10945501` is only a 96 px-wide player-view unit and cannot carry a recognizable Brasseurs facade by itself.
- What is proven: exact source wall + canonical camera + no shadow = `2.5597% / 2.5597%`, bbox `96x287`; player-eye human FAIL because it reads as a thin slab rather than a landmark facade.
- What is NOT proven: whether multiple connected UrbIS faces of building `1639974` jointly form the correct broader player-facing frontage; any production-quality detailed Brasseurs facade.
- What must not be redone: single-face `10945501` render, camera rescue, threshold lowering, material pixel-gaming, destructive neighbor hide, outward offset, #703 detached overlay.
- Exact next action: fresh live-main/ownership read, then an evidence-only audit of all WALLSURFACE faces for building `1639974` projected from the shared #753 camera. No runtime until that audit objectively identifies a coherent broader frontage.
