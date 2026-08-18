# Production Wall

## Main
- observed_main: `570a7c5c89566e863edf1d7364bf9a401f835619`
- last_verified: `2026-08-18T17:49Z`
- rule: `main` is the sole production truth. Re-read live main, open PRs, changed-file ownership and this wall before every branch, merge, rejection or production claim.
- six-point campaign status: **6/6 merged**.
- latest substantive Grand-Place visual correction: **#783** Hôtel de Ville right-gallery B1500 fidelity correction.
- current HEAD `570a7c5c...` is docs-only (#795); it ships no new runtime beyond its parent.
- Web publication invariant from #767 remains artifact-only and repository-read-only.

## Six-point campaign — SHIPPED
1. **#749** Midi official StreetSurface collision.
2. **#750** player melee feel.
3. **#752** PhysicalCarB primary for Mission 01 with persistence/reward flow.
4. **#765** Midi/Fonsny full source-backed entrance; `4.9336%` >3 RGB, `4.2255%` >8, bbox `903x185`, human PASS.
5. **#766** LABO→JOUABLE fail-closed gate; Midi remains sole JOUABLE.
6. **#767** Web artifact-only publication + live-main Branch Hygiene.

## Grand-Place chain — current truth
- Canonical camera = #753/#711: `[319.01,1.72,-535.20]` → `[321.91,11.8,-485.66]`, FOV `62`, 1280×720. Never use old `324.9581...` as #711.
- Correct owner = Hôtel de Ville UrbIS building `1655673`.
- **#783 SHIPPED**: B1500-constrained right-gallery correction on official lower-façade chain `10792525 + 10798452`; source span `15.944082 m`. Frozen source anchors: gallery top `4.9611 m`, arch apex `3.8295 m`, spring `2.5340 m`, opening width `1.9922 m`, pitch `2.6573489 m`, side margin `0.3325745 m`, base `0.0 m`; max traced fit error `0.052 m` <= `0.08 m`. Player-eye result `1.8911675%` >3 RGB, `1.8908420%` >8, bbox `271×101`; human PASS.
- **#790 CLOSED evidence-only**: after #783, whole official WALLSURFACE mass remains dominant at `17.0999%` >3 RGB / `16.9939%` >8, bbox `660×666`; roofs/tower `11.5271%`; window rhythm `2.5587%`; #783 gallery control `1.8912%`.
- **#792 CLOSED evidence-only**: after excluding #783 faces and off-camera `10792523`, dominant remaining naturally visible face = **`10792937`**, 2 triangles, span `3.18631744384766 m`, y `0..23.7119998931885 m`, projected bbox ~`100.49×436.15 px`, actual no-shadow overlay `24,812` >8 RGB pixels = `2.6922743%`, bbox `100×436`. Human PASS for face ownership only.
- **#794 CLOSED evidence-only**: source chain `10798452 → 10792936 → 10792937 → 10832750`; return `10792936` span `2.3500280849 m`; target parallel to #783 frontage (`0.9999929664`) and near-perpendicular to return (`0.0027035533`). Target centroid is `1.009472 m` from official east bbox and reaches that bbox within `0.000028 m`. Coarse spatial identity only = east-end stepped/projection zone of east wing at Grand-Place → rue Charles Buls transition. Exact architectural motif remains UNRESOLVED.

## #797 B1499/B1501 source acquisition — COMPLETE, CLOSED WITHOUT MERGE
- Exact production base: `570a7c5c89566e863edf1d7364bf9a401f835619`.
- Final source head: `6a88300fff137b9d1587f11f3d1f3aab59c71df6`.
- Dedicated run `32166244757` PASS; artifact `9335569072`; artifact zip SHA-256 `d99354ad89618e491758d3976efc28a42dde1bb2ffe6b83d6644ddb689629ef8`.
- Same-head Test, Zone Promotion Readiness, Game CI, Branch Hygiene and Performance Baseline all PASS.
- Full official source rasters were downloaded only into CI artifacts; no archive pixels were committed to Git.

### B1499 / image 431679
- KCML Beeldbank `/content/full` JPEG RGB `19187×6644`.
- SHA-256 `a57f066f19851ca8019cd567a9134b816bdd1adc9b3988a1d6bcb027f578b476`.
- Sheet `1620×529 mm`, stated scale `1/20`, Pierre Victor Jamaer, `28-02-1867`, Public Domain Mark 1.0.
- Primary raster inscription: **`Galerie vers la grande place à droite de la tour — Etat actuel. Plan`**.
- Raster visibly labels `Grande Place`; terminal left context labels `Rue de l’Hôtel de Ville`, `Lieu d’aisance` and `Sureté`.

### B1501 / image 431747
- KCML Beeldbank `/content/full` JPEG RGB `18594×5802`.
- SHA-256 `90f6e5719f89492508c5a1820c3caded8b6d90a5a216409b36f7e2baf2724987`.
- Sheet `1564×471 mm`, stated scale `1/20`, Pierre Victor Jamaer, `28-02-1867`, Public Domain Mark 1.0.
- **Important source-semantic discrepancy:** Beeldbank record metadata/JSON-LD repeats `Etat actuel`, but the acquired primary raster itself visibly reads **`Galerie vers la grande place à droite de la tour — Projet de restauration. Plan`**. Primary raster inscription governs interpretation; do not treat B1501 as a duplicate existing-state sheet.
- Raster labels `Grande Place` and `Rue de l’Hôtel de Ville`; red watercolor marks proposed restoration changes, especially support/perron treatment.

### Human scan review
- B1499 and B1501 are **not interchangeable truths**.
- B1499 = 1867 existing-state plan.
- B1501 = 1867 restoration-project plan according to the primary drawing, despite the Beeldbank description mismatch.
- Their central perron/support geometry materially differs; do not average or merge it.
- Both expose a common terminal street/corner context suitable for a separate registration-only experiment.
- #797 did **not** prove that either plan maps face `10792937`, did not prove B1501 was executed exactly as drawn, and did not authorize metric extraction.

## Active ownership
- No current-main Grand-Place implementation owner after #797 closure.
- No current-main shared sidewalk-edge owner; #789 and #796 were closed stale without merge.
- #652 Anneessens SIGNALER sync export — stale historical workspace.
- #643 LABO selector UI — stale; must not bypass #766.
- #596 / #592 Bourse QA/architecture — stale source/evidence workspaces.
- #2 / #11 long-lived geography specialists — never merge wholesale; extract one coherent current-main lot only.
- Closed evidence/source workspaces (#797/#794/#792/#790/#787/#778/#776) own nothing.

## Current Grand-Place decision
- The next legitimate question is **registration only**, not runtime.
- Re-acquire B1499 and B1501 independently and preserve their roles: B1499 existing state vs B1501 restoration project.
- Test only a rigid/unwarped registration of their terminal street/corner plan geometry against official UrbIS chain `10798452 → 10792936 → 10792937 → 10832750`.
- Freeze acceptance before the first registration result. No scale fudge, perspective warp or manual post-failure anchor movement.
- A topology/orientation match alone may identify which part of the plan corresponds to the UrbIS corner, but it does not automatically authorize present-day dimensions.
- If registration fails naturally, FAIL and stop this face path rather than fitting by hand.
- If registration succeeds, separately decide whether existing-state B1499, restoration-project B1501, or only geometry common to both is admissible for a later metric/source lot.

## Known visible debt
- Grand-Place remains incomplete beyond #783. Remaining wall hierarchy, corner transition, portal, tower and statuary/sculptural system require separate source-backed evidence and human gates.
- Midi/Fonsny entrance is improved after #765, but complete station/district realism remains incomplete.
- Six LABO zones remain LABO by design.

## Rejected / superseded paths — do not repeat
- #781 unsupported Bézier/internal arch dimensions — never restore.
- #787 face `10792523` — off-camera from canonical witness; no camera rescue.
- #773 markings — zero player-visible impact.
- #740 canopy-only and #737 additive Fonsny porch — insufficient; superseded by #765.
- #738 generic roofs — zero player-visible impact.
- Maison des Brasseurs `1639974` same-building path is mathematically closed: #755 exact wall `96×287 px`; #758 all six walls `174.526×287.869 px` < frozen 300 px width.
- Maison du Roi raw LoD2, Ducs blind LoD2, Roi d'Espagne primitive dome/proxy and La Brouette generic windows remain previous human fidelity failures.

## Important invariants
- Green CI alone does not authorize a visual merge; #781 is the explicit counterexample.
- Exact-current-main is mandatory; live `behind > 0` is a Branch Hygiene failure.
- One defect may have only one active implementation owner.
- Human full-frame verdict overrides green CI for visual lots.
- UrbIS owns official geometry. Heritage/archive evidence may constrain presentation only after explicit source registration/measurement.
- Source acquisition, plan registration, metric conversion and visual implementation are separate decisions.
- LABO data readiness is not JOUABLE.
- Web publication remains artifact-only and repository-read-only.

## NOW / NEXT / LATER
- **NOW:** production HEAD `570a7c5c...`; #783 remains latest substantive Grand-Place visual correction. #797 acquisition is complete and closed without merge. No current-main Grand-Place or Environment implementation owner exists.
- **NEXT Grand-Place:** fresh exact-current-main **registration-only** audit of B1499 and B1501 against the `10798452→10792936→10792937→10832750` corner chain. Preserve B1499 existing-state vs B1501 restoration-project semantics and forbid warp/metric/runtime claims.
- **NEXT Environment:** any sidewalk-edge retry must rebuild from then-live main; never reopen stale #789/#796 as integration units.
- **LATER:** only after a clean registration result may a separate metric/source decision be made, and only after that may a visual candidate be proposed.

## Shift handoff
- What changed: #797 acquired both full official Jamaer plans and was closed source-only. Human scan review found B1501's primary inscription says `Projet de restauration`, contradicting the record description that repeats `Etat actuel`.
- What is proven: exact source URLs, hashes, pixel dimensions, 1/20 metadata, date/designer/licence, and visual distinction of existing-state B1499 vs restoration-project B1501.
- What is NOT proven: rigid registration to face `10792937`, execution of B1501 exactly as drawn, present-day metric dimensions, exact motif identity or any runtime geometry.
- What must not be redone: mixing B1499/B1501 as duplicate truths, transfer of #783 dimensions, plan warping, camera rescue, or exact motif claims from metadata alone.
- Exact next action: re-read live main/owners, then run a fresh registration-only experiment with frozen acceptance and independent B1499/B1501 results.
