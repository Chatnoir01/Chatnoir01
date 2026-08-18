# Production Wall

## Main
- observed_main: `54996f27a0009d96bac41b56e156ad364b67afd0`
- last_verified: `2026-08-18T11:52Z`
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
- **#776 — Hôtel de Ville exact face-map PASS, CLOSED WITHOUT MERGE.** Exact passing head `af52c50...`; run `32133587934`; artifact `9323125300`; zip SHA-256 `4a2bf0b64d3a9df220d040ab3a5ad9bdbae3776148ef9d1bb2477a96308592c4`. Canonical #753/#711 camera proves one dominant connected official lower-façade chain made of buildingfaces `10792525` + `10798452`. Source span `15.944082 m`; actual visible overlay `146596` pixels >8 RGB = `15.906684%` of 1280×720; bbox `[959,0,1279,527]`. Human face-ownership verdict PASS. `visual_candidate_approved=false` remains mandatory.

## Active ownership
- **#775** generic OSM sidewalk-edge presentation, base `54996f27...`; explicitly excludes Grand-Place architecture. No overlap with Hôtel de Ville evidence, but any merge advances main and makes every other integration candidate resync.
- **#652** Anneessens SIGNALER sync export — stale draft; historical evidence only until rebuilt from current main.
- **#643** LABO selector UI — stale draft; must not bypass #766.
- **#596 / #592** Bourse QA/architecture — stale drafts; source/evidence only until rebuilt from current main.
- **#2 / #11** long-lived geography specialists — never merge wholesale; extract one coherent current-main lot only.
- #776 is closed and owns nothing now.

## Current Grand-Place decision
- Canonical camera remains #753/#711: `[319.01,1.72,-535.20]` → `[321.91,11.8,-485.66]`, FOV `62`, 1280×720.
- Correct architectural owner remains **Hôtel de Ville UrbIS `1655673`**.
- Exact proven lower façade source plane is the connected chain **buildingface `10792525` + `10798452`**.
- These faces run from ground to roughly the lower roofline; the face-map does **not** locate the gallery/portico vertically, does not prove east/west heritage wing identity from this camera, and does not authorize arches, portal depth, supports or statuary.
- Urban 31125 documents a projecting ground-floor gallery/portico, with eleven bays on the left and six on the right of the portal, using pointed-arch openings. These are heritage semantics only until a separate evidence lot bounds the ground-floor band.
- **No Hôtel de Ville visual geometry is authorized yet.**

## Known visible debt
- Grand-Place remains visually weak in the canonical frame; #772 and #776 now identify both the dominant building and the exact lower official source plane.
- Midi/Fonsny entrance is improved after #765, but the complete station/district remains incomplete.
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
- UrbIS owns official geometry; heritage/photo evidence may bound semantics/image space but does not authorize invented survey geometry.
- LABO data readiness is not JOUABLE.
- Web publication remains artifact-only and repository-read-only.

## NOW / NEXT / LATER
- **NOW**: production HEAD `54996f27...`; #776 exact source-plane evidence is sealed and closed without merge; #775 owns generic sidewalk-edge presentation only.
- **NEXT Grand-Place evidence**: source a primary/official façade reference or architectural elevation that can bound the **vertical ground-floor gallery/portico band** on the proven `10792525 + 10798452` plane. Image measurements are image-space ratios only; do not infer depth or opening geometry.
- **STOP CONDITION**: if no authoritative enough reference can bound the band, do not build arcades. Document the source gap and move to another source-backed defect.
- **LATER**: only after vertical-band evidence closes may a separate exact-current-main PR propose one bounded gallery/portico visual motif with locked player A/B and human full-frame gate.

## Shift handoff
- What is proven: Hôtel de Ville `1655673` is the dominant weak Grand-Place owner; exact connected lower façade faces are `10792525` + `10798452`; their canonical visible footprint is large enough for a meaningful future correction.
- What is NOT proven: gallery top elevation, portico depth, exact arch width/height, portal geometry, support spacing in metres, or which heritage wing label applies to this camera-visible chain.
- What must not be redone: single-face-per-wing assumption from #776 first RED run, camera/threshold rescue, stale #776 merge, Brasseurs same-building rescue, or generic primitive façade detail.
- Exact next action: obtain primary-source vertical-band evidence for the ground-floor gallery/portico before authoring any Town Hall detail.
