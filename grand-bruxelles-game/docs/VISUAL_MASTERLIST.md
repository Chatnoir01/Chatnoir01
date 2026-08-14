# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This file is the player-facing priority backlog, not a completeness claim.

Current production checkpoint: `046036d53e38d1909fca83ef2fe17c68af04a696` (publication-only Web refresh). Latest substantive merge beneath it: `a8e41662524f62444e16c1b5124498c9dcf29a79` (#258 Ixelles Stassart 124 frontage), following #257 Grand-Place official LoD2 landmark mass and #254 tighter direct Atomium framing.

## North star

Ask at every zone: **if a real Brussels photo or observation is beside the game, what gives the game away in the first three seconds?**

Optimize three horizons:

1. **3 seconds** — silhouette, proportions, materials, landmark/street identity, obvious placeholders.
2. **30 seconds** — signage, transport vocabulary, furniture, motion, clutter, lighting and atmosphere.
3. **10 minutes** — playable continuity, navigation, believable traffic/PNJ behavior, missions/saves and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient. Source truth and direct player-facing inspection are hard gates.

## Director gates — 2026-08-14 13:06 Brussels

- **#258 Ixelles Stassart 124 blue-stone frontage** — `shipped`, `local_identity_gain`. Compact exact-current-main rebuild preserved the one-cell runtime and adds one obvious source-backed lower-façade register. Deterministic direct-player A/B: 111,611 pixels >=12/255, bbox `[8,243,559,467]`; human accepted. No terrain/collision/camera/geography expansion; 460 unresolved-height buildings remain absent.
- **#257 Grand-Place official LoD2 landmark mass 1655673** — `shipped`, `major_silhouette_gain`. Source-backed UrbIS3D building ~43 m from the locked Grand-Place control point, 54.02 × 67.92 m source envelope, 93.024 m vertical extent, 82 faces / 262 triangles. Human accepted; deterministic witness changed ~102,017 pixels >3 RGB = 11.07% of 1280×720. This is the first clearly non-generic Grand-Place-scale architectural mass in the production witness.
- **#254 Atomium direct FOV framing** — `shipped`, `major_landmark_presentation_gain`. Direct `?spawn=atomium` now uses 48° FOV while preserving the same source-bounded visitor position and pitch. Human accepted; ~43.08% of 1280×720 pixels changed >8 RGB vs prior direct-spawn baseline. Geometry/world truth unchanged.
- **#243 bilingual Brussels street-name plaque** — `shipped`, `shared_identity_gain`. Reusable FR/NL plaque family accepted; permanent surveyed placement remains separate.
- **#242 direct Ixelles player/Web entry** — `shipped`, `player_access_gain`.
- **#241 Bourse official roof winding** — `shipped`, `source_preserving_roof_gain`.
- **#239 Ixelles compact visible micro-slice** — `shipped`, `runtime_foundation_gain`.
- **#252 Atomium Topo esplanade** — `source_disciplined`, `visual_impact_rejected`, `closed_without_merge`. 14 BB03L + 5 CR39L line features were real but too small in player view; the BR15S area pivot was a topographic-update localisation shape, not a physical esplanade polygon. Do not revive or inflate.
- **#250 Grand-Place plaza arrival** — `full_frame_impact`, `recognition_rejected`, `closed_without_merge`. Paving affected ~42.31% of frame but architecture remained generic. #257 has now solved the first massing bottleneck; do not return to paving until architecture/context is stronger.
- **#251 Ixelles bilingual junction cue** — `source_anchored`, `visual_impact_rejected`, `closed_without_merge`. Only 212 >8-RGB pixels; do not enlarge or move to manufacture impact.
- **#247 Atomium glazed pavilion** — `source_truth_rejected`, `visual_impact_rejected`, `closed_without_merge`.
- **#248 historic shopfront vocabulary** — `source_disciplined`, `visual_identity_rejected`, `closed_without_merge`.
- **#244 Atomium StreetSurface context** — `visual_impact_rejected`, `closed_without_merge`.
- **#231 shared STIB surface-stop vocabulary** — `technically_green`, `human_visual_accepted`, `placement_source_deferred`, `keep_draft`. Asset family remains valuable; production placement waits for defensible stop/furniture evidence.
- **#223 Midi blue-stone material** — `source_disciplined`, `visual_impact_rejected`, `keep_draft`.
- **#220 Atomium trees** — `source_coverage_rejected`, `closed_without_merge`.
- **#222 Bourse vault proxy** — `source_truth_rejected`, `closed_without_merge`.

## Latest shipped player-facing gains

- **#258 Ixelles Stassart 124 frontage** — first strong local material/heritage identity cue inside the directly playable Ixelles cell.
- **#257 Grand-Place official LoD2 mass** — first major source-backed architecture to dominate the deterministic Grand-Place witness.
- **#254 tighter direct Atomium framing** — much stronger 3-second landmark scale/readability without moving world geometry.
- **#243 bilingual Brussels street-name plaque** — reusable language identity.
- **#242 direct Ixelles Web/player spawn** — bounded Ixelles slice directly inspectable.
- **#241 Bourse roof winding normalization** — source-preserving hero roof improvement.
- **#230 Atomium direct Web spawn** — landmark immediately reachable.
- **#226 Atomium deterministic reflection environment** — stronger stainless response.
- **#217 Bourse white-stone portico** — stronger six-column readability.
- **#215 Midi/Fonsny Fauquenberg brick** — large flat façade replaced by source-scaled procedural brick.
- **#214 Atomium stainless presentation** — improved metallic landmark response.

## Current top 5 perceived-quality bottlenecks

1. **Grand-Place still lacks a coherent recognizable architectural ensemble** — `visual_gap_critical_but_unblocked`. #257 proves large official LoD2 geometry can dominate the frame. Next gain should add one adjacent high-screen-area authoritative LoD2 mass/frontage or another equally strong source-backed architectural cue before revisiting plaza material.
2. **Bourse roof/interior volumes + immediate surrounding frontage** — `visual_gap_high`. #241 and #217 improved the right layers, but simplified/incomplete structure remains obvious. No proxy pediment or invented landmark dimensions.
3. **Midi still lacks unmistakable STIB/station/public-space identity** — `visual_gap_high`. #215 brick is strong; #231 asset family remains placement-blocked. Station frontage/entries/wayfinding/transport interface remain the highest-value Midi opportunities.
4. **Ixelles is now playable and has one strong local heritage cue, but the street remains visually sparse/generic beyond that frontage** — `identity_gap_medium_high`. Infrastructure work is finished; next lot should add exactly one more defensible high-screen-area local cue, not return to terrain or micro-signage.
5. **Atomium immediate ground/context/pavilion/supports remain generic or unresolved** — `visual_gap_high`. Landmark framing/material/reflections are now strong after #254/#214/#226; the remaining giveaway has shifted decisively to site context.

## Active ownership map

- **Centre Vertical Slice** — owns Bourse/Centre/Midi/Grand-Place visible geography. #257 is shipped. Next lot should extend Grand-Place with one adjacent official high-impact LoD2 mass/frontage, or pivot to a materially larger Bourse/Midi correction if no such candidate exists. Avoid micro-frontage loops.
- **Visual Assets + Atmosphere** — owns shared PBR/furniture/signage/vegetation/lighting/weather/audio. #243 shipped; #231 preserved but placement-deferred. Prioritize unmistakable reusable identity, not generic props/material micro-deltas.
- **Ixelles Runtime Slice** — #239/#242/#258 shipped. Same one-cell scope only. Next lot may add exactly one new high-impact local identity cue using direct `?spawn=ixelles` A/B; no terrain/access/camera/geography work unless regression appears.
- **Laeken Hero Impact** — #214/#226/#230/#254 shipped. The landmark itself is now much stronger; focus next on one source-bounded context/pavilion/public-realm correction with obvious screen impact. Do not reopen rejected trees/StreetSurface/esplanade/pavilion-height paths.
- **Impact Director maintenance** — Traffic/Living City/missions/saves/release only for blockers, regressions or unusually high perceived-impact opportunities.

## Stream health

- **Centre** — `productive_now`: #257 finally converted Grand-Place source data into an obvious 11% frame architectural gain. Keep the anti-micro bar and build an ensemble, not another tiny frontage.
- **Visual Assets + Atmosphere** — `productive_but_source_blocked_on_stib`: bilingual signage shipped; STIB family remains valuable but placement truth is deferred. Seek another unmistakable reusable cue if no new placement evidence appears.
- **Ixelles** — `highly_productive`: compact runtime, direct access and first strong identity frontage are shipped. Do not reopen infrastructure; quality-only from here.
- **Laeken** — `productive`: #254 delivered a major 3-second presentation gain. Remaining work should move from landmark framing to site context, with strict source/impact gates.

## Shared priorities

1. **Grand-Place second authoritative architectural mass/frontage** adjacent to #257, with full-frame deterministic A/B and human recognition gate.
2. **Midi station/STIB identity** through source-backed frontage/entry/wayfinding or a genuinely proven #231 placement.
3. **Ixelles second local identity cue** inside the already shipped cell, only if it occupies meaningful screen area.
4. **Atomium immediate context** with source-bounded geometry/material that is visible in the strengthened #254 direct-player framing.
5. Atmosphere/wet/night only after the chosen frame has credible geometry and street identity.

## Production rules

1. Exact current `main` is the only production truth.
2. One active lot per exact problem/domain.
3. Small current-main PRs only; re-check `main` and active PRs immediately before push/PR/merge.
4. Publication-only commits are not new gameplay/visual truth.
5. Prefer Paradigm/UrbIS/UrbIS3D, Brussels Mobility, STIB and official orthophoto/DTM/DSM. OSM is complement, not proof for unresolved geometry/traffic semantics.
6. Preserve lawful provenance/licensing; never distribute reference imagery as textures without permission.
7. Evidence-only work is allowed only if it can unlock a material player-facing correction within one or two lots.
8. Green CI can still be rejected for negligible player impact or weak source truth.
9. Substantive lots require deterministic player-facing evidence, human inspection, relevant tests, branch hygiene and performance when applicable.
10. Pixel delta is evidence, not the objective. Judge recognition, silhouette, street proportions, material response, atmosphere, legibility, motion and gameplay feel.

## Director next-integration priority

**Highest-value next candidate: one second, adjacent authoritative Grand-Place LoD2 mass/frontage that materially increases ensemble recognition around shipped #257. #257 has proven the source path, witness and impact scale. If no second large defensible candidate exists, pivot immediately to Midi station identity or a high-screen-area Bourse correction rather than falling back to Grand-Place paving or micro-façade work. Ixelles is now healthy and should continue with one-cue-at-a-time quality work; Laeken should exploit the stronger #254 player framing to judge context candidates more strictly.**
