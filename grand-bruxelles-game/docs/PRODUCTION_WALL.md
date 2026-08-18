# Production Wall

## Main
- observed_main: `2c37f4e686750d31601597a66685f3fff0796471`
- last_verified: `2026-08-18T11:24Z`
- rule: `main` is the sole production truth. Re-read live main, open PRs, changed-file ownership and this wall before every branch, merge, rejection or production claim.
- six-point campaign status: **6/6 merged**.
- latest shipped visual lot: **#770** generic OSM `Building_*` facade articulation, merged from exact current main with player A/B, human full-frame, Performance, Web, PC, Game CI, Photo Match and Branch Hygiene green.
- Web publication invariant from #767 remains: build is repository-read-only, publication is artifact-backed, and no generated `web: publish ...` commit appears in the current recent-commit chain after #770. The connector available in this shift still does not enumerate push/workflow_run runs, so do not invent a Pages workflow-run PASS.

## Six-point campaign — SHIPPED
1. **#749 — Midi official street collision**: official StreetSurface families physically solid under the player.
2. **#750 — player melee feel**: recovery/anti-spam, no attack during dodge, collision-aware reaction, existing KO/loot preserved.
3. **#752 — PhysicalCarB primary**: Mission 01 uses physical B; A remains fallback/comparison; save/resume/reward/Retour Express follow the mission primary.
4. **#765 — Midi/Fonsny entrance**: full in-place Urban 9423 source-backed porch replacement; locked result `4.9336%` >3 RGB, `4.2255%` >8 RGB, bbox `903x185`; human full-frame PASS.
5. **#766 — LABO→JOUABLE promotion gate**: Midi remains the only JOUABLE; six other zones remain LABO; promotion is fail-closed and human-only.
6. **#767 — Web/integration discipline**: Web no longer commits generated preview files to main; any PR to main with live `behind > 0` fails Branch Hygiene until resync + gate rerun.

## Recently shipped / audited
- **#770 / `2c37f4e...` — generic OSM facade articulation SHIPPED.** Reuses `brussels_osm_facade_articulation_v1` over existing `Building_*` geometry only. No mesh/collision/footprint/height/placement changes. Locked Anneessens witness: `20.0362%` >3 RGB, `1.5754%` >8 RGB, bbox `979x498`; human PASS. Historic #768/#764 are stale/closed and own nothing.
- **#772 — Grand-Place canonical screen-owner audit CLOSED WITHOUT MERGE, evidence retained.** On production `2c37f4e...`, official Hôtel de Ville UrbIS building `1655673` owns `30.1684%` full-frame >3 RGB, `29.9571%` >8 RGB, `60.1997%` of the right half, bbox `670x720`. Official Etoile/Cygne `1786758` owns `7.5891%`; generic OSM buildings own `0.0%` in this canonical frame; current Town Hall window rhythm owns `2.5587%`. Decision: Hôtel de Ville is the dominant eligible architectural owner of the weak canonical Grand-Place frame.
- **#773 — generic OSM inferred lane-marking removal REJECTED.** Source audit proved road class alone does not justify the generated centre-dash presence/type, but the locked normal-player A/B produced `0.000000` >3 RGB. Closed without merge; do not lower thresholds or move the camera to rescue it. Future marking work requires explicit marking evidence.

## Active ownership
- No fresh current-main Grand-Place implementation owner after #772 closed. A new lot may audit Hôtel de Ville `1655673` only if started from live main and kept evidence-only until real exposed UrbIS faces are mapped.
- **#652** Anneessens SIGNALER sync export — old/stale draft; historical evidence only until rebuilt from current main.
- **#643** LABO selector UI — old/stale draft; must not bypass #766 promotion semantics.
- **#596 / #592** Bourse QA/architecture — old drafts; source/evidence only until rebuilt from current main.
- **#2 / #11** Laeken/Jette and rest-of-Brussels specialist branches — never merge wholesale; extract one coherent lot from then-current main.
- Other old Atomium/NPC/evidence drafts are specialist/history workspaces, not current-main merge candidates.

## Current Grand-Place decision
- Canonical camera remains #753/#711: position `[319.01, 1.72, -535.20]`, target `[321.91, 11.8, -485.66]`, FOV `62`, 1280x720, dynamics/UI frozen.
- The next eligible architectural owner is **Hôtel de Ville UrbIS `1655673`**, not a generic OSM mass and not Maison des Brasseurs.
- Before any new geometry: map the actual camera-facing WALLSURFACE face IDs from `data/urbis/grand_place_lod2/1655673.game.json`, their projected screen ownership and their relation to the documented Grand-Place-facing wings.
- Heritage source Urban 31125 documents the ground-floor gallery/portico, portal under the tower, east/west wing bay rhythm and continuous sculptural/niche organization. These semantics may guide a future candidate only after source-face mapping; exact opening dimensions/positions are not survey-authorized by the heritage text.
- First new lot must therefore be **evidence-only face mapping**, not a visual implementation. It may nominate one large motif for a later PR, but it may not author windows, arches, portal depth, statuary or approximate facade geometry.

## Known visible debt
- Grand-Place remains visually sparse/weak in the canonical #753 view despite the generic OSM articulation; the dominant weak architectural mass is now proven to be official Hôtel de Ville `1655673`.
- Midi/Fonsny is materially better at the targeted entrance after #765, but the complete station/district is not realism-complete.
- Six LABO zones remain LABO by design; #766 prevents status inflation.

## Rejected / closed visual paths — do not repeat
- **#773 generic lane-marking visibility toggle**: truth issue valid, but player A/B impact `0.0`; no visual-booster merge.
- **#740 Fonsny canopy-only**: `1.2509% / 1.0272% / 649x149`, below locked gate; superseded by #765.
- **#737 additive Fonsny porch**: exact-zero visible gain because production articulation occluded it.
- **#738 generic street-level roofs**: `>3 RGB = 0.0` from legitimate player camera.
- **Maison des Brasseurs building `1639974` same-building path is mathematically closed**: #755 exact wall `96x287 px`; #758 optimistic union all six WALLSURFACE faces `174.526x287.869 px`, below frozen 300 px width requirement. Do not lower thresholds, move the camera, hide neighbours, widen or invent geometry.
- Maison du Roi raw UrbIS LoD2, Ducs de Brabant blind LoD2 mass, Roi d'Espagne primitive dome/proxy and La Brouette generic window grid remain previous human fidelity failures; do not repeat the same forms.
- Never use `Vector3(324.9581,3.3,-512.8388)` as “#711”; #753 shared Grand-Place camera contract is canonical.

## Important invariants
- green unmerged PRs are not shipped progress.
- exact-current-main is mandatory at merge time; live `behind > 0` is a Branch Hygiene failure.
- one defect may have only one active implementation owner.
- human full-frame verdict overrides green CI for visual lots.
- UrbIS owns official geometry where available; heritage/photo evidence can describe semantics/image-space constraints but does not authorize invented survey geometry.
- LABO data readiness is not JOUABLE; only a human-approved proof satisfying #766 can change status.
- Web publication must remain artifact-only and repository-read-only.

## NOW / NEXT / LATER
- **NOW**: production HEAD `2c37f4e...`; #770 is shipped; #772 evidence identifies Hôtel de Ville `1655673` as the dominant Grand-Place architectural screen owner; #773 is rejected.
- **NEXT**: exact-current-main evidence-only face map for `1655673`: identify camera-facing official WALLSURFACE IDs and screen-space contribution, then nominate at most one large heritage-backed motif for a later implementation PR.
- **NEXT production verification**: if a connector/tool exposes push/workflow_run Actions, record the first artifact-backed Web→Pages production chain; until then, keep this item unclaimed rather than guessing.
- **LATER**: no LABO promotion without #766 proof; no Hôtel de Ville visual geometry before the face-map evidence closes.

## Shift handoff
- What changed since the previous wall: #770 shipped generic OSM facade articulation; #772 proved Hôtel de Ville dominates the weak canonical Grand-Place architectural frame; #773 marking-truth visual candidate failed and was closed.
- What is proven: `1655673` is the correct next architectural owner; generic OSM buildings are not the canonical-frame culprit after #770.
- What is NOT proven: which exact UrbIS wall face IDs are exposed to the canonical camera, or which single heritage motif can be placed without inventing geometry.
- What must not be redone: stale #768/#764, #773 camera/threshold rescue, Brasseurs same-building rescue, additive/canopy-only Fonsny, or wholesale specialist merges.
- Exact next action: map `1655673` official faces from exact live main, evidence-only, before authoring any Hôtel de Ville detail.
