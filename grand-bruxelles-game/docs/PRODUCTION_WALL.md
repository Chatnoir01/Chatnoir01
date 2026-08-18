# Production Wall

## Main
- observed_main: `dd57d043300769251e719b049f55ae7d86cc447b`
- last_verified: `2026-08-18T13:46Z`
- rule: `main` is the sole production truth. Re-read live main, open PRs, changed-file ownership and this wall before every branch, merge, rejection or production claim.
- six-point campaign status: **6/6 merged**.
- latest shipped visual correction: **#783** Hôtel de Ville right-gallery B1500 fidelity correction.
- Web publication invariant from #767 remains artifact-only and repository-read-only; do not reintroduce generated commits to main.

## Six-point campaign — SHIPPED
1. **#749** Midi official StreetSurface collision.
2. **#750** player melee feel.
3. **#752** PhysicalCarB primary for Mission 01 with persistence/reward flow.
4. **#765** Midi/Fonsny full source-backed entrance; `4.9336%` >3 RGB, `4.2255%` >8, bbox `903x185`, human PASS.
5. **#766** LABO→JOUABLE fail-closed gate; Midi remains sole JOUABLE.
6. **#767** Web artifact-only publication + live-main Branch Hygiene.

## Recently shipped / audited
- **#770 — generic OSM facade articulation SHIPPED.** No geometry change. Locked Anneessens witness: `20.0362%` >3 RGB, `1.5754%` >8 RGB, bbox `979x498`; human PASS.
- **#772 — Grand-Place screen-owner audit CLOSED WITHOUT MERGE.** Hôtel de Ville UrbIS building `1655673` owns `30.1684%` full-frame >3 RGB, `29.9571%` >8 RGB, `60.1997%` of the right half, bbox `670x720`. Generic OSM buildings own `0.0%` in this canonical frame after #770.
- **#776 — Hôtel de Ville exact face-map PASS, CLOSED WITHOUT MERGE.** Run `32133587934`, artifact `9323125300`, zip SHA-256 `4a2bf0b64d3a9df220d040ab3a5ad9bdbae3776148ef9d1bb2477a96308592c4`. Canonical #753/#711 camera proves connected official lower-façade chain `10792525 + 10798452`, source span `15.944082 m`, visible overlay `15.906684%` >8 RGB; human face-ownership PASS.
- **#778 — KCML/Jamaer B1500 source acquisition PASS, CLOSED WITHOUT MERGE.** Run `32135036345`, artifact `9323640012`; official Beeldbank image `431760`, archive `B1500`, public full JPEG `12062×7469`, source SHA-256 `94db156fc3f7e8aa97e475a138982f2cb3b7190964bc0ac165cb91465898dd8d`, sheet `1000×602 mm`, scale `1/20`, Pierre Victor Jamaer, `28-02-1867`, Public Domain Mark 1.0.
- **#779 — B1500 acquisition evidence recorded in production docs.** This established the source-before-metric rail on current main.
- **#781 — first right-gallery visual MERGED, then HUMAN/SOURCE QA FAILED.** The exact source face chain and six-bay semantics were valid, but the implementation conflated the top of the whole gallery band with the pointed-arch apex and introduced unsupported `spring=2.95 m`, `base=0.20 m`, `side_margin=0.22 m` plus quadratic Bézier control geometry. Green CI did not catch those internal inventions. This visual is superseded by #783 and must not be restored.
- **#783 / `dd57d043...` — right-gallery B1500 fidelity correction SHIPPED.** RED-first run `32142839612` failed causally on shipped #781 with `runtime still uses unsupported arch construction`. Corrected source anchors on verified B1500 scan: gallery-band top `4.9611 m`, inner arch apex `3.8295 m`, spring `2.5340 m`, opening width `1.9922 m`, six-bay pitch `2.6573489 m`, side margin `0.3325745 m`, ground base `0.0 m`. Runtime now uses a two-circle pointed-arch construction; sampled fit to the manually traced B1500 inner arch is max `0.052 m` against frozen `0.08 m` tolerance. Dedicated GREEN run `32143302578`: `1.8911675%` >3 RGB, `1.8908420%` >8 RGB, bbox `271×101`; artifact `9326957713`, zip SHA-256 `7a727b6ecaaa076fe917972a386242a178c626a9227c8c7c254120705f7573e6`. Human full-frame PASS. Game CI, Web, PC, Mobile, Performance, Photo Match, LoD2, white-stone, tests, promotion and Branch Hygiene all green on the merged head.

## Active ownership
- No active Hôtel de Ville implementation owner after #783 merged. A new Grand-Place lot must begin from then-live main and may not silently extend #783.
- #780 generic sidewalk-edge presentation was closed stale without merge; it owns nothing.
- **#652** Anneessens SIGNALER sync export — stale draft; historical evidence only until rebuilt from current main.
- **#643** LABO selector UI — stale draft; must not bypass #766.
- **#596 / #592** Bourse QA/architecture — stale drafts; source/evidence only until rebuilt from current main.
- **#2 / #11** long-lived geography specialists — never merge wholesale; extract one coherent current-main lot only.
- #776 and #778 are closed evidence banks and own nothing now.

## Current Grand-Place decision
- Canonical camera remains #753/#711: `[319.01,1.72,-535.20]` → `[321.91,11.8,-485.66]`, FOV `62`, 1280×720.
- Correct architectural owner remains **Hôtel de Ville UrbIS `1655673`**.
- Exact proven lower façade source plane remains connected chain **buildingface `10792525` + `10798452`**.
- Urban 31125 supplies the right-of-portal six-bay pointed-arch semantics. KCML/Jamaer B1500 supplies the measured right-gallery elevation/section/plan evidence.
- #783 is a **bounded presentation correction only** on that proven plane: no opening depth, portal depth, statuary, collision or official UrbIS vertex changes; `runtime_approved=false` and `realism_complete=false` remain mandatory.
- The right-gallery motif is now source-bounded enough to remain in production, but the complete Hôtel de Ville / Grand-Place is not fidelity-complete.

## Known visible debt
- Grand-Place remains incomplete beyond this bounded right-gallery correction. The tower, portal, statuary/sculptural system, left gallery and full façade hierarchy still require their own source-backed evidence and human gates.
- Midi/Fonsny entrance is improved after #765, but complete station/district realism remains incomplete.
- Six LABO zones remain LABO by design.

## Rejected / superseded paths — do not repeat
- **#781 internal arch geometry:** do not restore its Bézier, `spring=2.95`, `base=0.20`, `side_margin=0.22`, or use gallery-band top as arch apex. Superseded by #783.
- **#773 markings:** 0.0 player-visible impact; no camera/threshold rescue.
- **#740 Fonsny canopy-only:** insufficient; superseded by #765.
- **#737 additive Fonsny porch:** exact-zero visible gain.
- **#738 generic roofs:** `>3 RGB = 0.0`.
- **Maison des Brasseurs `1639974` same-building path is mathematically closed:** #755 exact wall `96x287 px`; #758 all six walls `174.526x287.869 px`, below frozen 300 px width requirement.
- Maison du Roi raw LoD2, Ducs blind LoD2, Roi d'Espagne primitive dome/proxy and La Brouette generic windows remain previous human fidelity failures.
- Never use `Vector3(324.9581,3.3,-512.8388)` as #711; #753 shared camera is canonical.

## Important invariants
- green CI alone does not authorize a visual merge; #781 is the explicit counterexample.
- exact-current-main is mandatory; live `behind > 0` is a Branch Hygiene failure.
- one defect may have only one active implementation owner.
- human full-frame verdict overrides green CI for visual lots.
- UrbIS owns official geometry; heritage/archive evidence may bound presentation geometry but must record measurement anchors and uncertainty instead of inventing internal dimensions.
- source acquisition, source-face mapping, metric conversion and visual implementation are separate decisions.
- LABO data readiness is not JOUABLE.
- Web publication remains artifact-only and repository-read-only.

## NOW / NEXT / LATER
- **NOW**: production HEAD `dd57d043...`; #783 has corrected the shipped #781 right-gallery regression using source-measured B1500 anchors; all required gates and human full-frame are PASS.
- **NEXT Grand-Place**: do not expand the six-bay motif automatically. Re-audit canonical screen ownership after #783 and choose the next largest remaining visible defect. Any next architectural motif requires its own exact source-plane/metric evidence before runtime geometry.
- **NEXT production verification**: preserve #767 artifact-only Web publication; do not claim a Pages deployment PASS unless a connector exposes the actual production workflow/run.
- **LATER**: tower/portal/sculpture/left-gallery detail only through separate source-backed lots; no automatic LABO promotion.

## Shift handoff
- What changed: #781 reached main before human/source review and exposed a QA hole; #783 added a RED fidelity gate, corrected the internal arch geometry from B1500 measurements, passed all regression/export/performance gates, passed human full-frame, and is now production.
- What is proven: building `1655673`, face chain `10792525 + 10798452`, six right-of-portal bays, and the #783 B1500-bounded arch envelope are valid production evidence.
- What is NOT proven: full Hôtel de Ville realism, left-gallery metric geometry, portal depth, statuary, tower/sculpture detail or complete Grand-Place fidelity.
- What must not be redone: #781 Bézier/internal constants, stale #780, camera/threshold rescue, Brasseurs same-building rescue, or generic primitive façade detail.
- Exact next action: re-audit the post-#783 canonical Grand-Place frame from exact live main and select only the largest remaining source-backed visual defect.
