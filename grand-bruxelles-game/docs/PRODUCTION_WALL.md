# Production Wall

## Main
- observed_main: `9dbe540d1d809f214a6e2b9ec3e595b0201508db`
- last_verified: `2026-08-18T17:29Z`
- rule: `main` is the sole production truth. Re-read live main, open PRs, changed-file ownership and this wall before every branch, merge, rejection or production claim.
- six-point campaign status: **6/6 merged**.
- latest substantive Grand-Place visual correction: **#783** Hôtel de Ville right-gallery B1500 fidelity correction.
- current HEAD `9dbe540d...` is docs-only (#793); it ships no new runtime beyond its parent.
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
- **#778 — KCML/Jamaer B1500 source acquisition PASS, CLOSED WITHOUT MERGE.** Official Beeldbank image `431760`, archive `B1500`, full JPEG `12062×7469`, source SHA-256 `94db156fc3f7e8aa97e475a138982f2cb3b7190964bc0ac165cb91465898dd8d`, sheet `1000×602 mm`, scale `1/20`, Pierre Victor Jamaer, `28-02-1867`, Public Domain Mark 1.0.
- **#781 — first right-gallery visual MERGED, then HUMAN/SOURCE QA FAILED.** It introduced unsupported internal arch dimensions/Bézier geometry. Superseded by #783; never restore.
- **#783 / `dd57d043...` — right-gallery B1500 fidelity correction SHIPPED.** Source anchors: gallery top `4.9611 m`, arch apex `3.8295 m`, spring `2.5340 m`, opening width `1.9922 m`, pitch `2.6573489 m`, side margin `0.3325745 m`, base `0.0 m`. Two-circle pointed arch; max traced-fit error `0.052 m` against frozen `0.08 m`. Dedicated GREEN: `1.8911675%` >3 RGB, `1.8908420%` >8 RGB, bbox `271×101`; human full-frame PASS.
- **#787 — left-gallery face `10792523` audit CLOSED WITHOUT MERGE.** This face is outside the canonical player camera; do not treat it as the next visible defect.
- **#788 / `b9d12ae...` — shared sidewalk-edge CI gate installed.** Workflow-only production change; no sidewalk-edge runtime shipped.
- **#790 — post-#783 Town Hall owner audit CLOSED WITHOUT MERGE.** Exact base `b9d12ae...`; run `32162599007`, artifact `9334220024`, zip SHA-256 `dd5e508932393642ca64802053523de22f8609a0ac7c40b56fae9b209ec64083`. WALLSURFACE mass wins at `17.0999%` >3 RGB / `16.9939%` >8, bbox `660×666`; roofs/tower `11.5271%`; window rhythm `2.5587%`; #783 gallery `1.8912%`. All required gates PASS. `implementation_authorized=false`.
- **#791 / `ece1c97e...` — docs-only production-wall refresh SHIPPED.** No runtime change.
- **#789 — shared generic sidewalk-edge candidate CLOSED STALE WITHOUT MERGE.** It was based on `b9d12ae...`; #791 advanced production before integration. No negative visual verdict is implied. Any retry must rebuild from then-live main and preserve its frozen player gate `>=0.25%` >3 RGB, `>=0.10%` >8, bbox `>=400×100` plus full general gates/human PASS.
- **#792 — remaining Hôtel de Ville wall-face audit CLOSED WITHOUT MERGE, evidence complete.** Exact base `ece1c97e...`, final evidence head `82445d88...`; dedicated run `32164076851`, artifact `9334743973`, zip SHA-256 `32a7ee6cfe416c8f74358247cc3933b8f9d62566859e1bf9d06afe5b90caae68`. Test, Zone Promotion Readiness, Game CI, Web, Branch Hygiene, PC, Photo Match and Performance all PASS on the same head.
- **#793 / `9dbe540d...` — docs-only record of #792 face evidence SHIPPED.** No runtime change.
- **#794 — face `10792937` semantic/topology audit CLOSED WITHOUT MERGE, evidence complete.** Exact base `9dbe540d...`, final head `eabc51ec...`; dedicated run `32165438328`, artifact `9335212298`, zip SHA-256 `11fa70895fa879e962cf27bead38a14c3df7457944bc2c12bbe74ac4e49d22ea`. Test, Zone Promotion Readiness, Branch Hygiene, Game CI and Performance Baseline all PASS on the same head. No runtime was changed.

## #792 exact face result
- Hard exclusions from winner selection remained: `10792525 + 10798452` already occupied by #783; `10792523` off-camera per #787.
- Winner: official WALLSURFACE **buildingface `10792937`**.
- Source geometry: `2` triangles; horizontal span `3.18631744384766 m`; vertical range `y=0.0..23.7119998931885 m`.
- Projected source bbox: about `100.49×436.15 px` in the canonical 1280×720 frame.
- Actual no-shadow QA overlay diff: **24,812 pixels >8 RGB = `2.69227430555556%`**, bbox `[886,82,985,517]` = `100×436`.
- Human artifact check: PASS for **face ownership only**. The magenta overlay is a direct, localized vertical façade strip, not a shadow-only or invisible result.
- Runner-up metrics are not promoted to product truth because its capture contained unrelated transient `PARLER [T]` UI noise.

## #794 semantic/topology result — exact identity still unresolved
- Official source chain is **`10798452` (#783 frontage) → `10792936` (orthogonal return) → `10792937` → `10832750`**.
- `10792937` exact span = `3.1863122885 m`, y `0..23.712 m`, 2 triangles.
- Intervening return `10792936` span = `2.3500280849 m`.
- Target vs #783 frontage abs direction dot = `0.9999929664` — parallel.
- Target vs return abs direction dot = `0.0027035533` — near-perpendicular.
- Lambert72 target endpoints = `[148840.8500279,170670.8860493]` and `[148842.8690279,170668.4210493]`.
- Target centroid is `1.009472 m` from the official building east bbox; eastmost endpoint is only `0.000028 m` from that bbox limit.
- Supported coarse spatial identity only: **east-end stepped/projection zone of the east wing at the Grand-Place → rue Charles Buls transition**.
- Exact architectural identity remains **UNRESOLVED**. Do not label it turret, portal, pavilion, stair bay, buttress, statuary zone or opening pattern.
- urban.brussels record 31125 supports east-wing / Charles-Buls-return context and Jamaer restoration chronology, but does not map this face to a motif.
- Candidate archive plans for the next lot only: KCML **B1499 / image 431679** and **B1501 / image 431747**, both gallery plans at `1/20` by Pierre Victor Jamaer, 28-02-1867, Public Domain Mark 1.0. No dimensions from them were used in #794.
- `implementation_authorized=false`, `reuse_783_dimensions=false`; portal/tower/turret/statuary/opening authoring all remain false.

## Active ownership
- No current-main Grand-Place implementation owner after #794 closure.
- No current-main shared sidewalk-edge owner after #789 closure.
- **#652** Anneessens SIGNALER sync export — stale draft; historical evidence only until rebuilt from current main.
- **#643** LABO selector UI — stale draft; must not bypass #766.
- **#596 / #592** Bourse QA/architecture — stale drafts; source/evidence only until rebuilt from current main.
- **#2 / #11** long-lived geography specialists — never merge wholesale; extract one coherent current-main lot only.
- Closed evidence banks (#794/#792/#790/#787/#776/#778) own nothing.

## Current Grand-Place decision
- Canonical camera remains #753/#711: `[319.01,1.72,-535.20]` → `[321.91,11.8,-485.66]`, FOV `62`, 1280×720.
- Correct architectural owner remains **Hôtel de Ville UrbIS `1655673`**.
- #790 proves the remaining WALLSURFACE mass is the dominant post-#783 screen owner.
- #792 narrows the next naturally exposed official face to **`10792937`**.
- #794 proves its coarse east-end/corner location but **not its exact motif**.
- The next step is **source acquisition + plan registration only**: obtain full B1499 and B1501 rasters from the official KCML Beeldbank, hash/license them, then test whether their plan geometry can be registered to the UrbIS corner chain `10798452→10792936→10792937→10832750` without forcing scale/orientation.
- No runtime is authorized until plan registration either resolves the motif and relevant dimensions or fails honestly.

## Known visible debt
- Grand-Place remains incomplete beyond the bounded #783 gallery correction. Remaining wall hierarchy, portal, tower, statuary/sculptural system and other visible façade regions require separate source-backed evidence and human gates.
- Midi/Fonsny entrance is improved after #765, but complete station/district realism remains incomplete.
- Six LABO zones remain LABO by design.

## Rejected / superseded paths — do not repeat
- **#781 internal arch geometry:** never restore its Bézier or unsupported `spring=2.95`, `base=0.20`, `side_margin=0.22` constants.
- **#787 left-gallery face `10792523`:** off-camera from canonical witness; no camera rescue.
- **#773 markings:** `0.0` player-visible impact; no camera/threshold rescue.
- **#740 Fonsny canopy-only:** insufficient; superseded by #765.
- **#737 additive Fonsny porch:** exact-zero visible gain.
- **#738 generic roofs:** `>3 RGB = 0.0`.
- **Maison des Brasseurs `1639974` same-building path is mathematically closed:** #755 exact wall `96×287 px`; #758 all six walls `174.526×287.869 px`, below frozen 300 px width requirement.
- Maison du Roi raw LoD2, Ducs blind LoD2, Roi d'Espagne primitive dome/proxy and La Brouette generic windows remain previous human fidelity failures.
- Never use `Vector3(324.9581,3.3,-512.8388)` as #711; #753 shared camera is canonical.

## Important invariants
- Green CI alone does not authorize a visual merge; #781 is the explicit counterexample.
- Exact-current-main is mandatory; live `behind > 0` is a Branch Hygiene failure.
- One defect may have only one active implementation owner.
- Human full-frame verdict overrides green CI for visual lots.
- UrbIS owns official geometry; heritage/archive evidence may bound presentation geometry but must record measurement anchors and uncertainty instead of inventing internal dimensions.
- Source acquisition, plan registration, metric conversion and visual implementation are separate decisions.
- LABO data readiness is not JOUABLE.
- Web publication remains artifact-only and repository-read-only.

## NOW / NEXT / LATER
- **NOW**: production HEAD `9dbe540d...`; #783 remains latest substantive Grand-Place visual correction. #794 is closed evidence-only; no current-main Environment or Grand-Place implementation owner exists.
- **NEXT Grand-Place**: fresh exact-current-main evidence-only acquisition/registration audit for KCML plans **B1499 (431679)** and **B1501 (431747)**. Persist source URLs/licences/hashes and only accept a registration if the plan's own geometry naturally matches the official UrbIS corner chain; do not warp it to fit.
- **NEXT Environment**: any sidewalk-edge retry must be a fresh rebuild from then-live main; do not reuse stale #789 as integration unit.
- **LATER**: only after B1499/B1501 registration resolves what `10792937` represents and provides bounded dimensions may a separate visual lot be proposed. No automatic portal/tower/turret/sculpture implementation and no LABO auto-promotion.

## Shift handoff
- What changed: #794 completed the semantic/topology audit of `10792937` and was closed without merge.
- What is proven: the face is a 3.1863 m frontage-parallel segment after a 2.3500 m orthogonal return at the east extremity of Town Hall building `1655673`; it lies at the Grand-Place / rue Charles Buls transition.
- What is NOT proven: exact motif/name/function, any portal geometry/depth, tower/turret detail, statuary or opening pattern.
- What must not be redone: #781 invented Bézier dimensions, #787 off-camera left-gallery, Brasseurs same-building rescue, camera/threshold rescue, transfer of #783 dimensions, or exact identity claims from metadata alone.
- Exact next action: re-read live main/owners, then acquire/register official B1499 and B1501 plan rasters against the UrbIS corner footprint before any implementation.
