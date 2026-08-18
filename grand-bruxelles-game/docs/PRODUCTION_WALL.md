# Production Wall

## Main
- observed_main: `b9d12ae52d1b5dce0d26f349276af375c38e69d1`
- last_verified: `2026-08-18T16:56Z`
- rule: `main` is the sole production truth. Re-read live main, open PRs, changed-file ownership and this wall before every branch, merge, rejection or production claim.
- six-point campaign status: **6/6 merged**.
- latest substantive Grand-Place visual correction: **#783** Hôtel de Ville right-gallery B1500 fidelity correction.
- current HEAD `b9d12ae...` is CI-only for the shared sidewalk-edge gate; it does not itself ship sidewalk-edge runtime.
- Web publication invariant from #767 remains artifact-only and repository-read-only; do not reintroduce generated publication commits to `main`.

## Six-point campaign — SHIPPED
1. **#749** Midi official StreetSurface collision.
2. **#750** player melee feel.
3. **#752** PhysicalCarB primary for Mission 01 with persistence/reward flow.
4. **#765** Midi/Fonsny full source-backed entrance; `4.9336%` >3 RGB, `4.2255%` >8, bbox `903x185`, human PASS.
5. **#766** LABO→JOUABLE fail-closed gate; Midi remains sole JOUABLE.
6. **#767** Web artifact-only publication + live-main Branch Hygiene.

## Recently shipped / audited
- **#770 — generic OSM facade articulation SHIPPED.** Locked Anneessens witness: `20.0362%` >3 RGB, `1.5754%` >8 RGB, bbox `979x498`; human PASS. No geometry change.
- **#772 — first Grand-Place screen-owner audit CLOSED WITHOUT MERGE.** Hôtel de Ville UrbIS building `1655673` dominated the canonical frame; generic OSM buildings had `0.0%` impact there after #770.
- **#776 — Hôtel de Ville exact face-map PASS, CLOSED WITHOUT MERGE.** Proven lower-façade chain `10792525 + 10798452`, source span `15.944082 m`; human face-ownership PASS.
- **#778 — KCML/Jamaer B1500 source acquisition PASS, CLOSED WITHOUT MERGE.** Official Beeldbank image `431760`, archive `B1500`, public full JPEG `12062×7469`, source SHA-256 `94db156fc3f7e8aa97e475a138982f2cb3b7190964bc0ac165cb91465898dd8d`, sheet `1000×602 mm`, scale `1/20`, Pierre Victor Jamaer, `28-02-1867`, Public Domain Mark 1.0.
- **#781 — first right-gallery visual MERGED, then HUMAN/SOURCE QA FAILED.** It introduced unsupported internal arch dimensions/Bézier geometry. Superseded by #783; never restore.
- **#783 / `dd57d043...` — right-gallery B1500 fidelity correction SHIPPED.** Source anchors: gallery-band top `4.9611 m`, arch apex `3.8295 m`, spring `2.5340 m`, opening width `1.9922 m`, pitch `2.6573489 m`, side margin `0.3325745 m`, base `0.0 m`. Two-circle pointed arch; max traced-fit error `0.052 m` against frozen `0.08 m`. Dedicated GREEN: `1.8911675%` >3 RGB, `1.8908420%` >8 RGB, bbox `271×101`; human full-frame PASS.
- **#787 — left-gallery face `10792523` audit CLOSED WITHOUT MERGE.** That face is outside the canonical player camera; do not treat it as the next visible defect.
- **#788 / main `b9d12ae...` — shared sidewalk-edge CI gate installed.** Workflow-only production change; no sidewalk-edge runtime shipped by this commit.
- **#790 — post-#783 Town Hall owner audit CLOSED WITHOUT MERGE, evidence complete.** Exact base `b9d12ae...`; dedicated run `32162599007`, artifact `9334220024`, zip SHA-256 `dd5e508932393642ca64802053523de22f8609a0ac7c40b56fae9b209ec64083`. Canonical 1280×720 results: WALLSURFACE mass `157,593` >3 RGB pixels = `17.0999%`, `156,616` >8 = `16.9939%`, bbox `660×666` — WINNER. ROOFSURFACE/tower `11.5271%`, bbox `670×720`; existing window rhythm `2.5587%`, bbox `342×312`; shipped #783 right-gallery control `1.8912%`, bbox `271×101`. Test, Branch Hygiene, Game CI, Photo Match, Performance, Web and PC all PASS on the same head. `implementation_authorized=false` remains binding.

## Active ownership
- **#789 — shared generic sidewalk-edge Environment lot.** Exact base `b9d12ae...`. Owns only `brussels_sidewalk_edge_runtime.gd`, its two tests, `project.godot`, and `tools/qa/validate_sidewalk_edge_runtime.py`. Scope is the already-existing 430 generic OSM-adjacent sidewalk slabs; no Bourse official curb-height claim, no Midi/Fonsny official surface, no Grand-Place architecture. Do not overlap these files. It is not production until its locked player-eye A/B, all required gates and human full-frame verdict pass and it is merged.
- **#652** Anneessens SIGNALER sync export — stale draft; historical evidence only until rebuilt from current main.
- **#643** LABO selector UI — stale draft; must not bypass #766.
- **#596 / #592** Bourse QA/architecture — stale drafts; source/evidence only until rebuilt from current main.
- **#2 / #11** long-lived geography specialists — never merge wholesale; extract one coherent current-main lot only.
- #790/#787/#776/#778 are closed evidence banks and own nothing now.

## Current Grand-Place decision
- Canonical camera remains #753/#711: `[319.01,1.72,-535.20]` → `[321.91,11.8,-485.66]`, FOV `62`, 1280×720.
- Correct architectural owner remains **Hôtel de Ville UrbIS `1655673`**.
- #790 proves the largest remaining naturally exposed owner after #783 is still the official **WALLSURFACE mass**, not the already-corrected six-bay gallery and not the current window-rhythm layer.
- Exact proven lower-façade source plane remains connected chain **buildingface `10792525` + `10798452`**; this chain is already occupied by the bounded #783 correction and must not be silently extended.
- Left-gallery face **`10792523` is off-camera** from the canonical witness per #787; do not spend a visual lot on it from this view.
- The next Centre step is therefore **source-face drill-down only**: rank the remaining official WALLSURFACE faces by actual naturally visible screen-space contribution after excluding the #783 chain and off-camera `10792523`. The winner nominates the next evidence acquisition; it does not automatically authorize geometry.
- No portal depth, tower detail, statuary, new openings or reuse of #783 dimensions is currently authorized.

## Known visible debt
- Grand-Place remains incomplete beyond the bounded #783 gallery correction. The remaining wall hierarchy, portal, tower, statuary/sculptural system and other visible façade regions require separate source-backed evidence and human gates.
- Midi/Fonsny entrance is improved after #765, but complete station/district realism remains incomplete.
- Six LABO zones remain LABO by design.

## Rejected / superseded paths — do not repeat
- **#781 internal arch geometry:** never restore its Bézier or unsupported `spring=2.95`, `base=0.20`, `side_margin=0.22` constants.
- **#787 left-gallery face `10792523`:** off-camera from canonical witness; no camera rescue.
- **#773 markings:** `0.0` player-visible impact; no camera/threshold rescue.
- **#740 Fonsny canopy-only:** insufficient; superseded by #765.
- **#737 additive Fonsny porch:** exact-zero visible gain.
- **#738 generic roofs:** `>3 RGB = 0.0`.
- **Maison des Brasseurs `1639974` same-building path is mathematically closed:** #755 exact wall `96x287 px`; #758 all six walls `174.526x287.869 px`, below frozen 300 px width requirement.
- Maison du Roi raw LoD2, Ducs blind LoD2, Roi d'Espagne primitive dome/proxy and La Brouette generic windows remain previous human fidelity failures.
- Never use `Vector3(324.9581,3.3,-512.8388)` as #711; #753 shared camera is canonical.

## Important invariants
- Green CI alone does not authorize a visual merge; #781 is the explicit counterexample.
- Exact-current-main is mandatory; live `behind > 0` is a Branch Hygiene failure.
- One defect may have only one active implementation owner.
- Human full-frame verdict overrides green CI for visual lots.
- UrbIS owns official geometry; heritage/archive evidence may bound presentation geometry but must record measurement anchors and uncertainty instead of inventing internal dimensions.
- Source acquisition, source-face mapping, metric conversion and visual implementation are separate decisions.
- LABO data readiness is not JOUABLE.
- Web publication remains artifact-only and repository-read-only.

## NOW / NEXT / LATER
- **NOW**: production HEAD `b9d12ae...`; #783 is the latest substantive Grand-Place visual correction; #788 added only sidewalk-edge CI; #789 is the active Environment owner; #790 is closed evidence-only with WALLSURFACE mass winning at `17.0999%`.
- **NEXT Grand-Place**: exact-current-main evidence-only face-level audit of `1655673` WALLSURFACE geometry. Exclude the #783-treated `10792525 + 10798452` chain and off-camera `10792523`; measure naturally exposed contribution per remaining face/group from the canonical camera. Do not write runtime in that audit.
- **NEXT Environment**: allow #789 to finish independently; do not touch its five owned files.
- **LATER**: only after a face/group winner is proven may a separate source acquisition/metric lot investigate the corresponding architectural motif. No automatic portal/tower/sculpture implementation and no LABO auto-promotion.

## Shift handoff
- What changed: #790 completed the post-#783 canonical ownership measurement and was closed without merge; it proves official Town Hall WALLSURFACE mass remains the dominant remaining screen owner. `main` itself is `b9d12ae...`, a CI-only sidewalk-edge workflow commit after #783/#784.
- What is proven: WALLSURFACE `17.0999%` full-frame >3 RGB, ROOFSURFACE/tower `11.5271%`, current window rhythm `2.5587%`, #783 gallery `1.8912%`. The next Centre question is which remaining official wall face/group owns those pixels.
- What is NOT proven: portal geometry/depth, tower detail, statuary, any new opening pattern, or that #783 dimensions transfer anywhere else.
- What must not be redone: #781 invented Bézier dimensions, #787 off-camera left-gallery, Brasseurs same-building rescue, camera/threshold rescue, generic primitive façade detail, or overlap with #789.
- Exact next action: after a fresh live-main/ownership reread, create one evidence-only per-face WALLSURFACE visibility audit on `1655673`, with the #783 face chain and off-camera `10792523` explicitly excluded from winner selection.
