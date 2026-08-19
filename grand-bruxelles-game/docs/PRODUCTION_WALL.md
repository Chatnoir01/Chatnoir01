# Production Wall

## Main
- last_verified: `2026-08-19T19:13Z`
- rule: `main` is the sole production truth. Re-read live main, open PR ownership and this wall before every branch, merge, rejection or production claim.
- live main observed before this candidate: `d3c0a64fa34749b6257f4f70254bcd931c8fec8c`
- current production change at that observation: **#933 SHIPPED** — Combat V2 real hand grip / animated limbs / visible shot FX; no Grand-Place environment files overlap.
- immediately prior Grand-Place production change: **#899 SHIPPED** — complete official Grand-Place LoD2 source owner set persisted.

## Core invariants
- Exact-current-main is mandatory. If `main` advances before integration, do not merge a stale candidate; rebuild from live main.
- One coherent lot per PR. One active owner per defect.
- UrbIS owns official geometry. Heritage/archive evidence can constrain presentation only after explicit source registration/measurement.
- Source acquisition, source registration, metric conversion, visual implementation and promotion are separate decisions.
- Green CI alone does not authorize a visual merge.
- Owner visual review rule: technical/legal blockers may reject immediately; subjective visual FAIL requires owner-visible full-frame evidence before final rejection/closure.
- Never lower a frozen threshold, move the camera, broaden geometry or displace source geometry merely to rescue a visual gate.
- LABO data/readiness is not JOUABLE.

## Current Grand-Place ownership
- **#874** remains the durable historical full-square campaign/governance workspace; never merge it wholesale.
- **#916 CLOSED / NOT MERGED** after executed evidence. It proved 23 source owners were instantiated but its A/B witness was technically invalid because `SubViewport.own_world_3d=true` isolated the scene/camera from root-mounted runtime geometry. It also used an over-strict triangle expectation that counted zero-area WALL/ROOF source entries as renderable. Camera, FOV and frozen thresholds were not changed after this failure.
- Immediately before branch creation there was **no open PR matching Grand-Place complete contour ownership**.
- Current contour candidate branch: `visual/grand-place-complete-contour-v2-d3c0a64`, rebuilt from exact observed main `d3c0a64fa34749b6257f4f70254bcd931c8fec8c`.
- Regional planning, Midi/NPC/vehicle, Bourse, shared Environment and long-lived geography workstreams remain outside this contour ownership.

## Grand-Place — production truth
- Canonical player witness remains #711/#753: camera `[319.01,1.72,-535.20]` -> `[321.91,11.8,-485.66]`, FOV `62`, resolution `1280x720`.
- Frozen contour A/B thresholds remain: `>3 RGB >= 1.0%`, `>8 RGB >= 0.5%`, changed-pixel bbox `>=500x180`. No post-FAIL rescue is allowed.
- Correct Hôtel de Ville owner = UrbIS building `1655673`.
- **#783 SHIPPED**: source-constrained right-gallery correction on `10792525 + 10798452`; full-frame human PASS.
- **#848 SHIPPED**: east-wing cross-window articulation; full-frame human PASS.
- **#891 SHIPPED**: official Maison du Roi owner `1654360` persisted as source truth.
- **#899 SHIPPED**: `data/urbis/grand_place_lod2/` contains the complete 25-owner official Grand-Place set from UrbIS 3D revision `2026-08-08`, package SHA-256 `cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2`, EPSG:31370, CC0-1.0.
- #899 dedicated source gate: **25 owners / 715 faces / 2170 triangles**, Game CI GREEN, Performance GREEN, tests GREEN, Branch Hygiene GREEN, Zone Promotion Readiness GREEN.
- Existing production runtime loaders already cover `1655673` and `1786758`.
- Current implementation target: load the remaining **23** owners as official WALL/ROOF geometry + wall collisions, neutral presentation only, no semantic façade guessing.
- Persisted Grand-Place `.game.json` triangle coordinates are already project-world coordinates; do not apply a second Lambert72 transform.
- A zero-area official WALL/ROOF triangle may be skipped only when deterministically proven degenerate. Runtime accounting must satisfy `rendered_non_degenerate + skipped_degenerate = all WALL/ROOF source entries`; degenerate geometry must not be repaired or invented.
- Brasseurs `1639974` stays part of the complete contiguous contour, not an isolated micro-candidate.
- Maison du Roi exact source owner is `1654360`; raw LoD2 alone does not authorize detailed neo-Gothic articulation.
- `10792523` remains out-of-frame; do not retry or move camera.
- `10792937` remains semantically unresolved for special architectural registration; do not force-fit B1499/B1501.
- `10796610` / `10796609` prior crude/narrow treatments must not be repeated unchanged.

## Grand-Place completion campaign — locked order
1. complete official source-owner coverage — **DONE via #899**;
2. complete visible building contour runtime from the official set — **NOW / V2 candidate**;
3. full-square multi-view coverage / zero-large-gap witness — **NEXT**;
4. square ground / street joins / player-foot collision continuity — **NEXT**;
5. player-height ground floors and identity details only where exact address/heritage crosswalk is proven — **LATER**;
6. final roofline/silhouette identity pass — **LATER**;
7. final Game CI / Photo Match / Performance / Web / PC + human multi-view gate.

## Ground / street truth
- Current Grand-Place paving already uses official UrbIS StreetSurface `42405` and builds collision from the same triangulated source mesh.
- Future join/exit work must use official UrbIS `StreetSurfaces` and official Brussels Mobility / Paradigm sidewalk layer `bm_urbis:urbadm_ssw`; curb elevation is unresolved unless separately sourced.
- Do not invent curb height, paving joint dimensions or sidewalk profiles.

## Identity / façade truth
- No nearest-neighbour semantic mapping is allowed for the remaining guild houses.
- Building→address identity must be proven by an official address point / ground-surface containment crosswalk or equivalent exact official relation before detailed façade/ground-floor identity is authored.
- Unresolved owners stay neutral LoD2 presentation rather than receiving guessed windows, signs, materials or names.

## Other production truths
- Ixelles remains LABO unless a separate promotion gate says otherwise.
- Midi remains the principal JOUABLE witness for gameplay/vehicle/NPC lots.
- Shared Environment and CityGen remain separate ownership from the Grand-Place contour campaign.
- Player/NPC/combat files are outside Grand-Place contour ownership.

## NOW / NEXT / LATER
- **NOW:** observed production `d3c0a64fa34749b6257f4f70254bcd931c8fec8c`; complete 25-owner source set is shipped; contour V2 is being rebuilt current-main with shared World3D A/B and exact degeneracy accounting.
- **NEXT Grand-Place:** if contour V2 passes numeric + human full-frame review, ship it, then run deterministic source-derived multi-view zero-large-gap witness.
- **NEXT ground:** prove/repair official 42405 continuity and source-backed street/sidewalk joins after the contour is visible.
- **LATER:** exact address/heritage crosswalk -> player-height ground floors -> roofline/detail pass -> zero-large-gap final review.
