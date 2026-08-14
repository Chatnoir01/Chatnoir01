# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This file is the player-facing priority backlog, not a completeness claim.

Current production checkpoint: `9f7e014fe63f3dfa4a54e6068fdc856b559c75d0` (publication-only Web refresh). Latest substantive merge beneath it: `3cd0b76c96d7afd9e4968ab572b3ee1cde5edb5d` (#260 Grand-Place official LoD2 ensemble mass 1786758), following #257 Grand-Place LoD2 mass 1655673, #258 Ixelles Stassart 124 frontage and #254 tighter direct Atomium framing.

## North star

Ask at every zone: **if a real Brussels photo or observation is beside the game, what gives the game away in the first three seconds?**

Optimize three horizons:

1. **3 seconds** — silhouette, proportions, materials, landmark/street identity, obvious placeholders.
2. **30 seconds** — signage, transport vocabulary, furniture, motion, clutter, lighting and atmosphere.
3. **10 minutes** — playable continuity, navigation, believable traffic/PNJ behavior, missions/saves and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient. Source truth and direct player-facing inspection are hard gates.

## Director gates — 2026-08-14 14:08 Brussels

- **#260 Grand-Place official LoD2 ensemble mass 1786758** — `shipped`, `ensemble_gain`. Exact official UrbIS3D geometry from the same audited CC0 package as #257. One solid, 82 faces, 196 source triangles, 19 WALLSURFACE + 62 ROOFSURFACE, ~29.284 m source vertical extent and ~19.96 × 17.70 m XY envelope. Deterministic 1280×720 A/B changed 65,125 pixels >3 RGB = 7.0665%; human accepted. #257 remains visible and dominant. No invented openings/material identity; current witness masks zero OSM nodes.
- **#258 Ixelles Stassart 124 blue-stone frontage** — `shipped`, `local_identity_gain`. One source-backed lower-façade register in the shipped one-cell runtime. Deterministic direct-player A/B: 111,611 pixels >=12/255, bbox `[8,243,559,467]`; human accepted. No terrain/collision/camera/geography expansion; 460 unresolved-height buildings remain absent.
- **#257 Grand-Place official LoD2 landmark mass 1655673** — `shipped`, `major_silhouette_gain`. Official UrbIS3D building ~43 m from the locked control point, ~54.02 × 67.92 m source envelope, 93.024 m vertical extent, 82 faces / 262 source triangles. Human accepted; ~102,017 pixels >3 RGB = 11.07% of 1280×720.
- **#254 Atomium direct FOV framing** — `shipped`, `major_landmark_presentation_gain`. Direct `?spawn=atomium` uses 48° FOV while preserving source-bounded visitor position and pitch. Human accepted; ~43.08% of 1280×720 pixels changed >8 RGB. Geometry/world truth unchanged.
- **#243 bilingual Brussels street-name plaque** — `shipped`, `shared_identity_gain`. Reusable FR/NL plaque family accepted; permanent surveyed placement remains separate.
- **#242 direct Ixelles player/Web entry** — `shipped`, `player_access_gain`.
- **#241 Bourse official roof winding** — `shipped`, `source_preserving_roof_gain`.
- **#239 Ixelles compact visible micro-slice** — `shipped`, `runtime_foundation_gain`.
- **#261 Ixelles next identity discovery** — `active_draft`, `bounded_evidence_gate`. Current-main probe only. It checks exactly three nearby heritage candidates against live official UrbIS Addresses and the 260 already-rendered strong-source buildings. Discovery workflow is green and therefore at least one candidate is eligible; no runtime cue has been authored yet. Continue this same PR with exactly one high-screen-area cue or close it. Remove temporary discovery files before integration. Do not let it become a research chain.
- **#252 Atomium Topo esplanade** — `source_disciplined`, `visual_impact_rejected`, `closed_without_merge`.
- **#250 Grand-Place plaza arrival** — `full_frame_impact`, `recognition_rejected`, `closed_without_merge`. Paving changed a large part of frame but architecture remained generic. #257/#260 have now improved architectural massing; paving can be revisited only when it complements a recognizable ensemble.
- **#251 Ixelles bilingual junction cue** — `source_anchored`, `visual_impact_rejected`, `closed_without_merge`.
- **#247 Atomium glazed pavilion** — `source_truth_rejected`, `visual_impact_rejected`, `closed_without_merge`.
- **#248 historic shopfront vocabulary** — `source_disciplined`, `visual_identity_rejected`, `closed_without_merge`.
- **#244 Atomium StreetSurface context** — `visual_impact_rejected`, `closed_without_merge`.
- **#231 shared STIB surface-stop vocabulary** — `technically_green`, `human_visual_accepted`, `placement_source_deferred`, `keep_draft`. Asset family remains valuable; production placement waits for defensible stop/furniture evidence.
- **#223 Midi blue-stone material** — `source_disciplined`, `visual_impact_rejected`, `keep_draft`.
- **#220 Atomium trees** — `source_coverage_rejected`, `closed_without_merge`.
- **#222 Bourse vault proxy** — `source_truth_rejected`, `closed_without_merge`.

## Latest shipped player-facing gains

- **#260 second Grand-Place LoD2 mass** — expands the official architecture ensemble with another immediately visible roofed mass while preserving #257.
- **#258 Ixelles Stassart 124 frontage** — first strong local material/heritage identity cue inside the directly playable Ixelles cell.
- **#257 Grand-Place LoD2 mass 1655673** — first major source-backed architecture to dominate the Grand-Place witness.
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

1. **Grand-Place still lacks a coherent, detailed architectural ensemble despite two strong official masses** — `visual_gap_critical_but_improving`. #257 + #260 prove the LoD2 source path and full-frame witness. The next gain should be one more adjacent large official mass/frontage only if it materially increases recognition; otherwise switch to frontage/material/paving context that complements the now-visible architecture rather than stacking small buildings for count.
2. **Bourse roof/interior volumes + immediate surrounding frontage** — `visual_gap_high`. #241 and #217 improved the right layers, but simplified/incomplete structure remains obvious. No proxy pediment or invented landmark dimensions.
3. **Midi still lacks unmistakable STIB/station/public-space identity** — `visual_gap_high`. #215 brick is strong; #231 remains placement-blocked. Station frontage/entries/wayfinding/transport interface remain the highest-value Midi opportunities.
4. **Ixelles is playable and has one strong local frontage, but the street remains sparse/generic beyond it** — `identity_gap_medium_high`. #261 is the sole active quality lot and must convert its successful discovery probe into exactly one substantial runtime cue or close.
5. **Atomium immediate ground/context/pavilion/supports remain generic or unresolved** — `visual_gap_high`. Landmark framing/material/reflections are strong after #254/#214/#226; the remaining giveaway is site context.

## Active ownership map

- **Centre Vertical Slice** — owns Bourse/Centre/Midi/Grand-Place visible geography. #257 and #260 are shipped. Next lot should attempt one additional adjacent high-screen-area official LoD2 mass/frontage only if it clearly builds recognition; otherwise pivot to a materially larger Grand-Place context/frontage, Bourse roof/interior or Midi station correction. Avoid micro-frontage loops.
- **Visual Assets + Atmosphere** — owns shared PBR/furniture/signage/vegetation/lighting/weather/audio. #243 shipped; #231 preserved but placement-deferred. Prioritize unmistakable reusable identity, not generic props/material micro-deltas.
- **Ixelles Runtime Slice** — #239/#242/#258 shipped. #261 is the sole active next-identity owner. Same one-cell scope only. Discovery must become one high-impact cue within this PR or be closed; no terrain/access/camera/geography work.
- **Laeken Hero Impact** — #214/#226/#230/#254 shipped. Landmark presentation is strong; next work is one source-bounded context/pavilion/public-realm correction with obvious screen impact. Do not reopen rejected trees/StreetSurface/esplanade/pavilion-height paths.
- **Impact Director maintenance** — Traffic/Living City/missions/saves/release only for blockers, regressions or unusually high perceived-impact opportunities.

## Stream health

- **Centre** — `highly_productive_now`: two consecutive source-backed Grand-Place masses produced ~11.07% then ~7.07% frame changes. Keep the anti-micro bar; the next Centre lot must add recognition, not simply another object.
- **Visual Assets + Atmosphere** — `productive_but_source_blocked_on_stib`: bilingual signage shipped; STIB family remains valuable but placement truth is deferred. Pivot if no genuinely new placement evidence appears.
- **Ixelles** — `productive_with_evidence_risk`: runtime/access/frontage are shipped and #261 discovery is green. This evidence phase is acceptable only because it directly gates one candidate runtime cue; do not permit a second discovery-only PR.
- **Laeken** — `productive_but_context_blocked`: #254 delivered a major 3-second framing gain. Remaining context candidates must be judged under that stronger view and rejected early if source coverage or projected screen area is weak.

## Shared priorities

1. **Grand-Place ensemble recognition after #257 + #260** — one more large adjacent official architectural cue only if screen impact is clearly substantial; otherwise use the now-visible architecture as the basis for a coherent frontage/context correction.
2. **Midi station/STIB identity** through source-backed frontage/entry/wayfinding or a genuinely proven #231 placement.
3. **Ixelles second local identity cue** through #261 only, inside the shipped cell, with direct-player A/B and anti-micro gate.
4. **Atomium immediate context** with source-bounded geometry/material visible in the strengthened #254 direct-player framing.
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

**Highest-value next candidate: a third adjacent authoritative Grand-Place LoD2 mass/frontage only if a bounded source/screen-impact probe shows another clearly substantial recognition gain. #257 and #260 have already proven the ensemble strategy; do not turn it into object-count accumulation. If the next candidate is materially smaller or visually redundant, pivot immediately to a coherent Grand-Place frontage/context correction or Midi station identity. In parallel, #261 may proceed only to one directly player-visible Ixelles cue from its successful bounded discovery; no further evidence-only chain.**
