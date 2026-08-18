# Production Wall

## Main
- observed_main_before_this_edit: `f713299f23aff7805228db00706ccfec9f8771fd`
- last_verified: `2026-08-18T04:16:30Z`
- latest_verified_publication: `f713299f23aff7805228db00706ccfec9f8771fd` — Web publication after QA #753.
- latest substantive gameplay changes: #749 official Midi street-surface solidity + #750 player melee feel.
- rule: re-read live `main`, open PRs, changed-file ownership and this wall before every branch, merge, rejection or production claim.

## Active ownership
- #752 — vehicle/Mission 01 only: `.github/workflows/grand-bruxelles-primary-physical-vehicle.yml`, `game/scripts/mission_drive_to_center.gd`, `game/tests/primary_physical_vehicle_test.gd`. Draft and currently NOT merge-ready: its current head has Mission Save Contract and Game CI failures. Do not overlap these files.
- #11 — long-lived rest-of-Brussels mapping/data/tooling specialist. Never merge wholesale; extract one coherent checkpoint from current main.
- #2 — long-lived Laeken + Jette / Heysel / Atomium specialist. Never merge wholesale; extract current-main checkpoints only.
- Old #665/#652/#643/Bourse/Atomium/NPC drafts are stale specialist/evidence workspaces, not current-main integration candidates.
- Grand-Place / Brasseurs wall `1639974` / `10945501` currently has no active implementation owner.

## Recently shipped
- #753 / `1296b057...` / publication `f713299f...` — canonical Grand-Place camera contract is production truth. Exact merged #711 witness = 1280x720, camera `[319.01, 1.72, -535.20]`, target `[321.91, 11.8, -485.66]`, FOV 62. Exact-current-main clean witness PNG is bit-for-bit identical to historical #711: SHA-256 `d869abcbd1cbc500954b85e5de07ee25ab4f2ecf96f0d5a593e9762a762d0798`. Brasseurs owner audit from this REAL camera reports 25/25 sampled rays with `hit_count=0`, `collider_counts={}`; artifact `9310657334`, zip digest `sha256:3bfc203be76c46a00dc9547448dfa3fef85426611ca580799318d30333eda770`. This proves collision-line clearance only, NOT absence of non-collidable visual occlusion.
- #750 / `4615e481...` — player melee readable-weight lot shipped.
- #749 / `815f5a6e...` — official Midi StreetSurface families made solid on source geometry.
- #743 / `b4973a2...` — generic selected-OSM owner hypothesis for Brasseurs rejected; nearest selected OSM building remains ~90.031492 m from wall `10945501`. Its old ray result used a mislabeled camera and is superseded by #753 for camera provenance.
- #711 — clean Grand-Place player-eye witness pattern, now backed by #753 shared camera contract.
- #680 — Brasseurs photo-plan contract; source/license/hash + exact UrbIS wall constraints, no runtime geometry.

## Brasseurs truth / corrected history
- Official target: UrbIS building `1639974`, front wall face `10945501`.
- Exact wall evidence: five official vertices / three official triangles, span ~8.749036 m, y 0..24.746 m. UrbIS owns placement, wall shape and vertical anchors.
- Generic selected OSM ownership is disproved; do not assign the wall to `Building_306856563` or another distant OSM block.
- `GrandPlace1786758` broad AABB touches the shared-corner neighborhood but is NOT proven to own wall `10945501`; do not hide it wholesale.
- #753 REAL #711 ray result is 25/25 no collision hit. This does not rule out purely visual/non-collidable overlap; the first fresh wall-skin A/B must answer that.
- #703 is NOT evidence that a coherent official wall skin failed. It built detached bands/pilasters/windows/arcades and never emitted the exact continuous five-vertex/three-triangle base wall.
- #748 is closed stale without a valid candidate A/B. It repeated the wrong `324.9581...` camera and never reached a legitimate final render. Its frozen future visual thresholds remain binding: `>3 RGB >= 2.00%`, `>8 RGB >= 1.00%`, changed bbox `>=300x260`, 1280x720.

## Closed / rejected visual paths
- #740 — Fonsny canopy-only replacement rejected: `1.2509% / 1.0272% / 649x149` versus locked `3.00% / 1.50% / 700x160`; source-correct mechanism but insufficient 3-second impact.
- #738 — generic street-level OSM roofs rejected: `>3 RGB = 0.0`; no player value from legitimate camera.
- #737 — additive Fonsny porch rejected: exact-zero visible gain because it sat largely inside/behind existing entrance articulation.
- #696 — Brasseurs detached primitive overlay technical PASS but mandatory human FAIL; scaffold, not coherent facade.
- Maison du Roi raw UrbIS LoD2, Ducs de Brabant blind LoD2 mass, Roi d'Espagne primitive dome/proxy and La Brouette generic window grid remain prior human fidelity failures.

## Blocked / do not repeat
- No camera rescue: never use `Vector3(324.9581,3.3,-512.8388)` as “#711”. The shared #753 contract is production truth.
- Never lower the frozen Brasseurs visual thresholds after a failed render.
- Do not hide `GrandPlace1786758` merely to make a facade appear.
- Do not invent an outward wall offset to escape overlap.
- Do not return to free-standing Brasseurs bars/columns/slabs/arches/window grids or a raw photo quad.
- Commons/photo pixels remain reference/constraint data unless a separate compliant derivative/license strategy is approved.

## NOW / NEXT / LATER
- NOW: production HEAD observed `f713299f...`. #753 camera truth is shipped and published. #752 owns the vehicle lot and is not yet merge-ready. No active Brasseurs implementation exists.
- NEXT Brasseurs experiment: fresh branch from then-live `main`; exact official five-vertex/three-triangle wall skin only, `details=0`, no outward offset, no neighbor hide, no windows/bands/columns/arcades. A/B must read `data/qa/grand_place_clean_player_witness.json` instead of hardcoding a camera. Preserve frozen thresholds `2.00% / 1.00% / 300x260` before first candidate render.
- Human gate: full-frame 3-second verdict is mandatory. Numerical PASS cannot rescue an invisible, shadow-only or scaffold-like result.
- If the continuous wall itself is not visibly present from the canonical witness, close the visual candidate and diagnose non-collidable visual overlap; do NOT change camera or thresholds.
- LATER: only after continuous base-wall visibility passes may a separate lot consider shallow photo-constrained architectural relief.

## Known visible debt
- Grand-Place landmark-house facade/silhouette fidelity remains weak; no production-quality Brasseurs facade has passed the human three-second gate.
- Midi/Fonsny entrance remains generic; additive detail and canopy-only correction were both insufficient from normal player distance.
- Vehicle mission-primary work remains unshipped while #752 has failing gates.

## Important invariants
- `main` is the only production truth; green unmerged PRs are not shipped progress.
- One defect may have only one active implementation; close/rebuild stale candidates rather than racing them.
- Human full-frame verdict overrides green CI for visual lots.
- #753 shared camera contract is the sole canonical source for Grand-Place clean player-eye tests.
- UrbIS owns official geometry where available; photo measurements are image-space constraints, not survey geometry.

## Shift handoff
- What changed: #749 collisions and #750 melee shipped; #753 corrected the Grand-Place camera provenance bug and locked the real #711 view without changing its rendered image.
- What is proven: real #711 witness is `[319.01,1.72,-535.20]` / target `[321.91,11.8,-485.66]` / FOV 62; its image hash is unchanged; 25/25 Brasseurs wall ray samples have no collision hit on exact-current-main #753.
- What is NOT proven: absence of non-collidable visual occlusion; visible success of the exact continuous Brasseurs wall; any detailed production-quality Brasseurs facade.
- What must not be redone: mislabeled 324.9581 camera, #703 detached feature overlay, destructive 1786758 hide, outward-offset rescue, stale #748 merge, lowered visual gates.
- Exact next action: after a fresh live-main/ownership read, build one RED-first exact continuous Brasseurs wall-skin visibility experiment using the shared #753 camera contract and frozen #748 thresholds. If another agent owns Brasseurs by then, do not duplicate it.
