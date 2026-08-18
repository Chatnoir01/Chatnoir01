# Production Wall

## Main
- observed_main: `21b8718c9c3c2948f0fa312cfa59a75d50ab5de6`
- last_verified: `2026-08-18T12:13Z`
- rule: `main` is the sole production truth. Re-read live main, open PRs, changed-file ownership and this wall before every branch, merge, rejection or production claim.
- six-point campaign status: **6/6 merged**.
- latest shipped visual lot: **#770** generic OSM `Building_*` facade articulation.
- Web publication invariant from #767 remains artifact-only and repository-read-only; do not reintroduce generated commits to main.

## Six-point campaign — SHIPPED
1. **#749** Midi official StreetSurface collision.
2. **#750** player melee feel.
3. **#752** PhysicalCarB primary for Mission 01 with persistence/reward flow.
4. **#765** Midi/Fonsny full source-backed entrance; `4.9336%` >3 RGB, `4.2255%` >8, bbox `903x185`, human PASS.
5. **#766** LABO→JOUABLE fail-closed gate; Midi remains sole JOUABLE.
6. **#767** Web artifact-only publication + live-main Branch Hygiene.

## Recently shipped / audited
- **#770 / `2c37f4e...` — generic OSM facade articulation SHIPPED.** No geometry change. Locked Anneessens witness: `20.0362%` >3 RGB, `1.5754%` >8 RGB, bbox `979x498`; human PASS.
- **#772 — Grand-Place screen-owner audit CLOSED WITHOUT MERGE.** Hôtel de Ville UrbIS building `1655673` owns `30.1684%` full-frame >3 RGB, `29.9571%` >8 RGB, `60.1997%` of the right half, bbox `670x720`. Generic OSM buildings own `0.0%` in this canonical frame after #770.
- **#773 — generic inferred lane-marking removal REJECTED.** Source concern valid, but normal-player A/B `0.000000`; closed without merge.
- **#776 — Hôtel de Ville exact face-map PASS, CLOSED WITHOUT MERGE.** Passing head `af52c50...`; run `32133587934`; artifact `9323125300`; zip SHA-256 `4a2bf0b64d3a9df220d040ab3a5ad9bdbae3776148ef9d1bb2477a96308592c4`. Canonical #753/#711 camera proves connected official lower-façade chain `10792525 + 10798452`, source span `15.944082 m`, visible overlay `146596` pixels >8 RGB = `15.906684%`, bbox `[959,0,1279,527]`; human face-ownership PASS; `visual_candidate_approved=false`.
- **#778 — KCML/Jamaer B1500 source acquisition PASS, CLOSED WITHOUT MERGE.** Passing head `92602b4...`; run `32135036345`; artifact `9323640012`; artifact digest `sha256:81e854c4a2a63d0b5699bd350c687e1b71fdd6973b2ecf4015d586041f097992`. Official Beeldbank image `431760`, archive `B1500`, public `full` source acquired as JPEG `12062×7469`, source SHA-256 `94db156fc3f7e8aa97e475a138982f2cb3b7190964bc0ac165cb91465898dd8d`. Sheet metadata `1000×602 mm`, scale `1/20`, Pierre Victor Jamaer, `28-02-1867`, Public Domain Mark 1.0. Human source-usability PASS: elevation, section and plan are present; section visibly contains explicit `0,42` dimension. No gallery height claimed in #778.

## Active ownership
- **#775** generic OSM sidewalk-edge presentation, stale base `54996f27...`; explicitly excludes Grand-Place architecture. Do not merge until rebuilt/resynced on live main.
- **#652** Anneessens SIGNALER sync export — stale draft; historical evidence only until rebuilt from current main.
- **#643** LABO selector UI — stale draft; must not bypass #766.
- **#596 / #592** Bourse QA/architecture — stale drafts; source/evidence only until rebuilt from current main.
- **#2 / #11** long-lived geography specialists — never merge wholesale; extract one coherent current-main lot only.
- #776 and #778 are closed evidence banks and own nothing now.

## Current Grand-Place decision
- Canonical camera remains #753/#711: `[319.01,1.72,-535.20]` → `[321.91,11.8,-485.66]`, FOV `62`, 1280×720.
- Correct architectural owner remains **Hôtel de Ville UrbIS `1655673`**.
- Exact proven lower façade source plane is connected chain **buildingface `10792525` + `10798452`**.
- Urban 31125 documents a projecting ground-floor gallery/portico, with eleven bays on the left and six on the right of the portal, using pointed-arch openings.
- KCML B1500 now supplies a primary restoration-era measured drawing for the gallery to the right of the tower. It contains elevation + section + plan, states scale `1/20` (`Échelle de 0,05 par mètre`) and contains an explicit `0,42` dimension in the section.
- **No Hôtel de Ville visual geometry is authorized yet.** The next lot may only convert B1500 into a conservative vertical gallery-band envelope with explicit pixel anchors and uncertainty.

## Known visible debt
- Grand-Place remains visually weak in the canonical frame; #772/#776 identify the dominant building and exact lower official source plane, while #778 provides primary drawing evidence needed for the next vertical bound.
- Midi/Fonsny entrance is improved after #765, but complete station/district realism remains incomplete.
- Six LABO zones remain LABO by design.

## Rejected / closed paths — do not repeat
- **#773 markings:** 0.0 player-visible impact; no camera/threshold rescue.
- **#740 Fonsny canopy-only:** insufficient; superseded by #765.
- **#737 additive Fonsny porch:** exact-zero visible gain.
- **#738 generic roofs:** `>3 RGB = 0.0`.
- **Maison des Brasseurs `1639974` same-building path is mathematically closed:** #755 exact wall `96x287 px`; #758 all six walls `174.526x287.869 px`, below frozen 300 px width requirement.
- Maison du Roi raw LoD2, Ducs blind LoD2, Roi d'Espagne primitive dome/proxy and La Brouette generic windows remain previous human fidelity failures.
- Never use `Vector3(324.9581,3.3,-512.8388)` as #711; #753 shared camera is canonical.

## Important invariants
- green unmerged PRs are not shipped progress.
- exact-current-main is mandatory; live `behind > 0` is a Branch Hygiene failure.
- one defect may have only one active implementation owner.
- human full-frame verdict overrides green CI for visual lots.
- UrbIS owns official geometry; heritage/archive evidence may bound semantics/image space but does not authorize invented survey geometry.
- source acquisition, source-face mapping and metric conversion remain separate evidence decisions.
- LABO data readiness is not JOUABLE.
- Web publication remains artifact-only and repository-read-only.

## NOW / NEXT / LATER
- **NOW**: production HEAD `21b8718c...`; #776 face-map and #778 B1500 acquisition are sealed evidence-only and closed without merge; #775 is stale and unrelated.
- **NEXT Grand-Place evidence**: exact-current-main B1500 measurement lot. Re-download public `full` image 431760 and verify source SHA `94db156f...`; use explicit `0,42 m` section dimension as local pixel calibration plus stated `1/20` scale; record floor/platform pixel anchors and conservative scan-axis/systematic uncertainty. Output a vertical gallery top envelope only.
- **MEASUREMENT RAIL**: do not infer portico depth, exact arch width, portal geometry, statuary, bay spacing in metres or horizontal wing identity. No runtime geometry.
- **STOP CONDITION**: if anchors/calibration cannot be reproduced robustly, keep gallery band unresolved and do not build arcades.
- **LATER**: only after vertical-band evidence closes may a separate exact-current-main visual PR propose one bounded gallery/portico motif with locked player A/B and human full-frame gate.

## Shift handoff
- What is proven: Town Hall `1655673` is the dominant weak Grand-Place owner; exact lower source plane is `10792525 + 10798452`; official B1500 scan is acquired, hashed and visually suitable for metric evidence.
- What is NOT proven: final gallery top elevation, portico depth, exact arch dimensions, portal geometry, support spacing in metres, or exact heritage wing mapping of the source faces.
- What must not be redone: #778 `/content/original` route (HTTP 400), single-face-per-wing assumption from #776 first RED run, camera/threshold rescue, Brasseurs same-building rescue, or generic primitive façade detail.
- Exact next action: create reproducible B1500 vertical-band measurement evidence with conservative uncertainty before authoring any Town Hall detail.
