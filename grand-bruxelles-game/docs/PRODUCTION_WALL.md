# Production Wall

## Main observation
- observed_main_before_this_wall_edit: `e2e4586c01a5d629b7e954bbbbc1bdc4d941fae5`
- observed_at: `2026-08-19T16:25Z`
- rule: `main` is the sole production truth. This records the SHA observed before the wall edit; re-read live GitHub `main` before every branch, merge, rejection or production claim.
- observed production change: #917 repairs Kenney intake workflow YAML only; no game/runtime/visual file changed and no Grand-Place ownership change.

## Core invariants
- Exact-current-main mandatory; if `main` advances before integration, rebuild rather than merge stale work.
- One coherent lot per PR; one active owner per defect.
- UrbIS owns official geometry. Heritage/archive evidence constrains identity only after exact registration.
- Green CI alone does not authorize a visual merge. Subjective visual verdict requires owner-visible full-frame evidence.
- No frozen-camera/threshold/source-geometry rescue.
- LABO/readiness is not JOUABLE.

## Current ownership — recalculated 2026-08-19T16:25Z
- **#916** owns Grand-Place complete contour for the 23 official owners not already handled by dedicated production loaders; scope = runtime mesh/collision + canonical A/B only.
- #874 historical Grand-Place campaign ledger only; never merge wholesale.
- #907 Anderlecht B01 source-complexity QA only; #898 regional LoD2 planning only.
- #903 shared street-furniture binding only; #905/#887 combat only; #900/#892 vehicles only; #875/#831/#829/#813 Midi/NPC only.
- #880/#596 Bourse review/QA; #2/#11 long-lived specialist geography branches.

## Grand-Place production truth
- Frozen player witness #711/#753: `[319.01,1.72,-535.20]` -> `[321.91,11.8,-485.66]`, FOV 62°, 1280×720.
- Hôtel de Ville owner `1655673`; preserve shipped #783/#848.
- Maison du Roi owner `1654360`.
- #899 SHIPPED complete official set: **25 owners / 715 faces / 2170 triangles**, UrbIS 3D revision 2026-08-08, EPSG:31370, CC0-1.0, package SHA-256 `cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2`.
- Dedicated loaders already cover `1655673` and `1786758`; remaining contour = **23 owners / 551 faces / 1712 source triangles**.
- Contour may render official WALLSURFACE + ROOFSURFACE only and create collision from official walls. GROUNDSURFACE remains excluded.
- Unregistered owners remain neutral: no guessed windows, signs, materials, names or ground-floor identity.
- Brasseurs `1639974` belongs to the contiguous contour, not an isolated retry.
- Do not retry `10792523`; do not force-fit `10792937`; do not repeat `10796610`/`10796609` treatments unchanged.

## Completion order
1. official owner coverage — DONE #899;
2. 23-owner visible contour runtime — NOW #916;
3. 3–5 frozen normal traversal views / zero-large-gap gate — NEXT;
4. official square ground / StreetSurface 42405 joins / foot collision — NEXT;
5. exact address crosswalk then player-height ground floors — LATER;
6. source/heritage-backed roofline/identity — LATER;
7. final Game CI / Photo Match / Performance / Web / PC + owner multi-view review.

## Prepared next-lot evidence (not yet committed)
- deterministic 5-view generator from official StreetSurface 42405 + official WALLSURFACE targets: blob `bbfd8da203c72d3de335f50f285a84047c94d422`;
- player-foot continuity test using only 42405 triangle centroids: blob `8fc99641ab6e1aea089e19a18522e2cd09c4bf47`;
- fail-closed UrbIS AddressNumbers→official GROUNDSURFACE crosswalk extractor: blob `aa6031bb5f6704dc1f5b155305855349e8efa5ef`;
- Urban Brussels address/heritage registry kept separate from BU_ID until crosswalk proof: blob `a4fc647b8059f955a4b9c44f2b04e17a9cb4ddf7`.

## Ground / identity rails
- Existing square paving uses official StreetSurface `42405` with collision from the same triangulated mesh.
- Exits/joins must use official UrbIS `StreetSurfaces` and Brussels Mobility / Paradigm `bm_urbis:urbadm_ssw`; curb elevation and paving-joint dimensions remain unresolved.
- No nearest-neighbour semantic mapping. Building→address requires exact official relation or unambiguous AddressNumbers-point containment in official GROUNDSURFACE.

## NOW
#916 must be rebuilt and tested against observed production `e2e4586c01a5d629b7e954bbbbc1bdc4d941fae5`. Canonical numeric A/B PASS is necessary but never sufficient for merge; owner full-frame verdict remains mandatory.
