# Production Wall

## Main
- observed_main_before_this_edit: `8b3f83d59d8e80d051e631fcc0813f37a53ae1d3`
- last_verified: `2026-08-19T11:38Z`
- rule: `main` is the sole production truth. Re-read live main, open PR ownership and this wall before every branch, merge, rejection or production claim.
- current production HEAD: **#864** shared corridor tree material (`brussels_street_tree_v1` material revision 2).
- recent shipped visual chain includes **#848** Grand-Place Town Hall east cross windows, **#853** Ixelles source-safe facade depth, and **#864** shared corridor tree material.

## Core invariants
- Exact-current-main is mandatory. If `main` advances before integration, do not merge the stale candidate; close/rebuild from live main.
- One coherent lot per PR. One active owner per defect.
- UrbIS owns official geometry. Heritage/archive evidence can constrain presentation only after explicit source registration/measurement.
- Source acquisition, source registration, metric conversion, visual implementation and promotion are separate decisions.
- Green CI alone does not authorize a visual merge. Human full-frame player-eye review overrides a numeric PASS.
- Never lower a frozen threshold, move the camera, broaden geometry or displace source geometry to rescue a visual FAIL.
- LABO data/readiness is not JOUABLE.

## Grand-Place — current truth
- Canonical player witness remains #711/#753: camera `[319.01,1.72,-535.20]` -> `[321.91,11.8,-485.66]`, FOV `62`, resolution `1280x720`.
- Correct Hôtel de Ville owner = UrbIS building `1655673`.
- **#783 SHIPPED**: source-constrained right-gallery correction on `10792525 + 10798452`; source span `15.944082 m`; full-frame human PASS.
- **#848 SHIPPED**: east-wing cross-window articulation on the existing window rhythm. Preserves 10 east + 9 west bays / 2 registers / 38 panels; adds 20 east crosses = 20 mullions + 20 transoms. Exact-head A/B: `3,361` pixels >8 RGB, `0.364691840277778%`, bbox `339x291`; full-frame human PASS. UrbIS mesh/openings unchanged; west special ordination remains deferred.
- **#854 CLOSED WITHOUT MERGE**: unchanged Town Hall dormer retry remains too small at the natural player frame. Do not rebuild the same dormer candidate unchanged.
- **#860 CLOSED evidence-only**: bright full-face unshaded drilldown nominated WALLSURFACE `10796610`, but that method overestimated useful low-relief visibility.
- **#862 CLOSED evidence-only**: source registration of the west-wing / rue de la Tête d'Or architectural semantics remains evidence only.
- **#865 CLOSED WITHOUT MERGE**: realistic Tête d'Or gable treatment on exact WALLSURFACE `10796609` failed the frozen player-eye gate. Measured `0.318359375%` >3 RGB, `0.3178168403%` >8, bbox `122x341`; human FAIL because the visible change is a narrow strip clipped against the extreme right edge.
- **Grand-Place stop rule:** do not retry `10796609`/Tête d'Or with lower thresholds, moved camera, broader plates or copied #863 treatment. Do not treat #860's bright full-face mask as implementation authorization.
- **NEXT Grand-Place:** evidence-only re-rank of naturally visible Town Hall WALLSURFACE owners from exact live main using a realistic shaded/low-relief white-stone probe, with explicit horizontal edge-margin/centrality criteria. Source-register exactly one winning large motif only after human review of the rerank.

## Ixelles — current truth
- Ixelles remains **LABO** unless a separate promotion gate says otherwise.
- **#819 SHIPPED**: source-backed facade articulation on the 260 direct source-backed Ixelles buildings and whitelisted context cells; source geometry/collision preserved.
- **#853 SHIPPED**: source-safe authored facade depth rebuilt from current production after #848/#851. Scope remained renderer-only relief on existing source-backed walls; footprints, accepted heights, collisions and surveyed claims unchanged. Stassart 124 remains excluded from generic relief so its dedicated identity cue is preserved.
- Do not reopen stale #842; #853 superseded it.

## Atomium / Heysel — current truth
- Production direct arrival remains the legitimate player path; do not move its camera merely to rescue a visual candidate.
- **#833 SHIPPED evidence-only**: the prior DTM reference resolves to the ticket-shop POI, while a separate monument-relation witness is ~`29 m` away. It rejects treating the ticket-shop point as the Atomium hero centre but authorizes no replacement anchor or runtime move.
- **#814** basin and **#820** neutral StreetSurface arrival were technical/source successes but mandatory player-visible failures.
- **Atomium stop rule:** no stronger-colour/wider-radius/camera-moved retries of the basin or neutral StreetSurface path. A future visual lot needs a different naturally visible defect or separately source-backed arrival-composition evidence.

## Shared environment — current truth
- **#864 SHIPPED / CURRENT HEAD**: shared authored tree material revision 2 on the existing 266 corridor OSM trees / 3 existing MultiMesh batches. No source position, tree count, collision, silhouette geometry, dimensions, roads, sidewalks, Centre architecture or geography changes.
- Exact-head #864 player A/B passed: `12.7875%` >3 RGB, `7.9962%` >8 RGB, bbox `1207x678`; full-frame human PASS. Structural cost remains three shared materials on the three existing batches, with zero new tree meshes/collisions/batches.

## Important rejected paths — do not repeat
- Maison des Brasseurs `1639974` same-building path is screen-space closed from the canonical camera.
- Unsupported Bézier/internal arch dimensions from #781 — never restore.
- Face `10792523` — off-camera; no camera rescue.
- Road markings #773 — zero player-visible impact.
- Generic roofs #738 — zero player-visible impact.
- Town Hall dormer unchanged retry #854 — insufficient player-frame impact.
- Tête d'Or `10796609` path #865 — source-valid but natural-frame visual FAIL; no rescue.
- Maison du Roi raw LoD2, Ducs blind LoD2, Roi d'Espagne primitive proxy and La Brouette generic windows remain previous human fidelity failures.

## Active ownership / stale workspaces
- Always re-read open PRs because concurrent agents move quickly.
- At this verification there is **no active exact Grand-Place architectural implementation owner**; closed evidence/source workspaces own nothing.
- #857 owns authored player-rig work, not exact Grand-Place architecture.
- #2 remains a long-lived Laeken/Jette specialist; never merge it wholesale.
- Old LABO/Bourse/Anneessens drafts are historical workspaces unless rebuilt from live main.

## NOW / NEXT / LATER
- **NOW:** production `8b3f83d59d8e80d051e631fcc0813f37a53ae1d3`; #848 Grand-Place cross windows, #853 Ixelles facade depth and #864 shared tree material are shipped.
- **NEXT Grand-Place:** realistic shaded/low-relief WALLSURFACE rerank from exact live main, prioritizing large central in-frame candidates and rejecting extreme-edge masks before source-registration.
- **NEXT Ixelles:** only a newly identified naturally visible defect; no generic visual soup and no automatic LABO promotion.
- **NEXT Atomium:** a different naturally visible defect or a separately source-backed arrival-composition audit; do not retry rejected basin/StreetSurface presentation.
- **LATER:** continue one source-backed visible defect at a time across the catalogue.

## Shift handoff
- What changed: #848 shipped the Town Hall east cross windows; #853 shipped Ixelles source-safe facade depth; #864 then became production HEAD with shared tree material revision 2.
- What was rejected after source work: the Tête d'Or path is semantically valid but player-frame insufficient; #865 is the stop record.
- What is not active: no exact Grand-Place runtime implementation currently owns the next Town Hall facade defect.
- Exact next action: re-read live main/open owners, then open an **evidence-only realistic low-relief WALLSURFACE rerank** on the current Town Hall using the canonical #711 camera. Human-review the top full-frame candidates before any source-registration or runtime PR.
