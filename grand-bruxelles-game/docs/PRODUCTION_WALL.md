# Production Wall

## Main
- observed_main_before_this_edit: `b4973a2093f2c3c68f8ed01600e303ea2678bd99`
- last_verified: `2026-08-18T03:48:15Z`
- latest_published_runtime_parent: `cf2433da792d3bd4616f2a27e6924de412c474aa` — shared presentation-only OSM rail surface shipped; publication `ce640963f6468cce2ccf786f26f53c3dfa0bb9c0` remains the latest verified public runtime publication in this wall.
- rule: re-read live `main`, open PRs and changed-file ownership before every branch, merge, rejection or production claim.

## Active ownership
- #742 — Midi official street-surface collision only. Owns `urbis_midi_builder.gd`, Midi collision tests/workflows and rendered-main baseline. Base is `b869552e...`, so it is now stale after #743; do not merge without rebuilding/revalidating from current main.
- #744 — generic OSM facade articulation only. Owns its articulation scripts/tests/workflow, checker and `project.godot`. Base is `b869552e...`; its own contract says close without merge if main advances. Do not overlap `project.godot` while it remains open.
- #11 — long-lived rest-of-Brussels mapping/data/tooling specialist workstream. Never merge wholesale; extract one coherent checkpoint from current main.
- #2 — long-lived Laeken + Jette / Heysel / Atomium specialist workstream. Never merge wholesale; extract current-main checkpoints only.
- Grand-Place / Brasseurs exact wall `1639974` / `10945501` has no active implementation owner after #743 QA landed.

## Recently shipped
- #743 / `b4973a2...` — QA-only Brasseurs geometry-owner resolution. Generic selected OSM owner hypothesis rejected: nearest selected OSM building is ~90.031492 m from wall `10945501`. Broad AABB overlap with official building `1786758` is not a hide target. From canonical #711 camera, 25/25 rays across the exact wall at 3/7/11/15/18 m have no collider. Historical #703 did not build a continuous official wall skin and used an older farther/left camera. Dedicated owner audit, Test, Branch Hygiene, Performance, Game CI, Web, PC and Photo Match are green on its unchanged head.
- `cf2433da...` / publication `ce640963...` — reusable shared OSM rail presentation surface on existing geometry; no geometry claim.
- #733 — Bourse standardized OSM zone environment view.
- #730 — Anneessens standardized OSM zone environment contract.
- #711 — canonical clean Grand-Place 1280x720 player-eye witness.
- #680 — Brasseurs photo-plan contract; source/license/hash + exact UrbIS wall constraints, no runtime geometry.

## Closed / rejected evidence
- #740 — source-backed Fonsny canopy-only replacement rejected: locked player-eye gate `1.2509% / 1.0272% / 649x149` versus `3.00% / 1.50% / 700x160`. Correct in-place replacement mechanism, insufficient 3-second impact.
- #738 — generic OSM roof treatment rejected: legitimate street-level A/B `>3 RGB = 0.0`; roofs not meaningfully visible.
- #737 — additive Fonsny porch rejected: exact-zero visible gain because it sat largely inside/behind existing entrance articulation.
- #726 — stale Brasseurs coherent-wall workspace closed.
- #696 — detached primitive Brasseurs overlays technical PASS but mandatory human FAIL; scaffold, not coherent facade.
- Maison du Roi raw UrbIS LoD2, Ducs de Brabant blind LoD2 mass, Roi d'Espagne primitive dome/proxy and La Brouette generic window grid remain prior human fidelity failures.

## Blocked / do not repeat
- Do not assign Brasseurs wall `10945501` to `Building_306856563` or another selected OSM block: #743 disproved that ownership hypothesis.
- Do not hide `GrandPlace1786758` merely because its AABB touches the shared corner neighborhood. #743 did not prove it owns the Brasseurs wall and the canonical #711 rays are clear.
- Do not treat #703 as a failed coherent-wall-skin experiment: it built detached bands/pilasters/windows/arcades, not the exact five-vertex / three-triangle wall skin.
- Do not revive free-standing Brasseurs bars/columns/slabs/arches/window grids, raw photo quad, invisible street-level roofs, hidden duplicate Fonsny porch or canopy-only Fonsny retune.
- Never lower a predeclared visual threshold after failure and never move the camera to rescue a weak candidate.

## NOW / NEXT / LATER
- NOW: production HEAD is `b4973a2...`. #743 QA is shipped; no Brasseurs runtime facade is shipped.
- NEXT Brasseurs experiment: fresh RED-first branch from then-live main. First implementation state must be one continuous base skin for exact UrbIS building `1639974` / wall `10945501`, using the exact five official vertices / three official triangles and `details=0`. Reuse canonical #711 1280x720 player-eye witness. No windows, bands, columns, arcades or relief until the base skin itself proves visibly present. Do not hide 1786758 and do not invent outward displacement.
- Integration safety for that experiment: avoid `project.godot` while #744 owns it; prefer an unowned mount path after a fresh changed-file ownership check.
- LATER: only after base-wall visibility PASS may a separate lot add shallow photo-constrained relief. Photo measurements remain image-space constraints; UrbIS owns placement/span/wall shape/vertical anchors.

## Known visible debt
- Grand-Place landmark-house facade/silhouette fidelity remains weak; no production-quality Brasseurs facade has passed the mandatory human three-second gate.
- Midi/Fonsny entrance remains generic; two source-backed micro-approaches prove that additive detail and canopy-only correction are insufficient at normal player distance.
- Bourse/Atomium/Anneessens old drafts must be rebuilt from current main before any integration decision.

## Important invariants
- `main` is the only production truth; green unmerged PRs are not shipped progress.
- Human full-frame verdict overrides green CI for visual lots.
- One defect may have only one active implementation; close/rebuild stale candidates rather than racing them.
- #711 is the canonical clean Grand-Place player-eye witness pattern.
- UrbIS owns official geometry where available; photo measurements are constraints, not survey geometry.
- Commons pixels are not shipped by current Brasseurs contracts; any future derivative must satisfy applicable license obligations.

## Shift handoff
- What changed: #743 landed and removed the false assumption that a generic OSM block or neighboring official building must be hidden before Brasseurs can be tested.
- What is proven: no selected OSM building is near wall `10945501`; 25/25 #711 rays across the wall are clear; #703 was detached-feature geometry, not a coherent official wall skin.
- What is NOT proven: that an exact three-triangle base wall skin is visible enough from #711, or that any detailed Brasseurs facade passes the human 3-second gate.
- What must not be redone: #703 detached feature overlay, destructive hide of 1786758, outward-offset rescue, stale pre-#743 branch, lowered visual gate.
- Exact next action: after this wall refresh lands and after one more live-main/ownership read, create one fresh RED-first Brasseurs base-wall visibility lot on exact current main, with details=0 and the #711 witness.
