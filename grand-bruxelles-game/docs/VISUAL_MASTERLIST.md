# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This file is the player-facing priority backlog, not a completeness claim.

Current production checkpoint: `c188e60ab3be314bf55ccdc5673ee792e18c5efa` (Direction-only merge #249). Latest substantive player-facing Web publication remains `5c306cdae9fe5439bd3bd87796ae1730cf0aefc7`, containing shipped #241 Bourse roof winding, #242 direct Ixelles entry and #243 bilingual Brussels street-name plaque.

## North star

Ask at every zone: **if a real Brussels photo or observation is beside the game, what gives the game away in the first three seconds?**

Optimize three horizons:

1. **3 seconds** — silhouette, proportions, materials, landmark/street identity, obvious placeholders.
2. **30 seconds** — signage, transport vocabulary, furniture, motion, clutter, lighting and atmosphere.
3. **10 minutes** — playable continuity, navigation, believable traffic/PNJ behavior, missions/saves and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient. Source truth and direct player-facing inspection are hard gates.

## Director gates — 2026-08-14 12:05 Brussels

- **#243 bilingual Brussels street-name plaque** — `shipped`, `shared_identity_gain`. Reusable FR/NL plaque family is in production. Permanent surveyed placement remains a separate source-truth gate.
- **#242 direct Ixelles player/Web entry** — `shipped`, `player_access_gain`. `?spawn=ixelles` exposes the shipped one-cell micro-slice without adding geography or unresolved heights.
- **#241 Bourse official roof winding** — `shipped`, `source_preserving_roof_gain`. Existing UrbIS3D ROOFSURFACE geometry is kept while exterior winding is normalized for deterministic culling.
- **#239 Ixelles compact visible micro-slice** — `shipped`, `runtime_foundation_gain`. One cell only; 309 StreetSurfaces, 277 StreetAxes, 260 strong-source-height buildings, 460 unresolved-height buildings absent.
- **#250 Grand-Place architecture-bearing plaza arrival** — `full_frame_impact`, `recognition_rejected`, `closed_without_merge`. The calibrated witness contained 15 production building masses and the official surface changed 389,909 strong pixels (~42.31% of 1280×720), but direct inspection still read as generic low architecture plus a black/dark slab. Do not revisit paving presentation before authoritative Grand-Place frontage/massing is present in-frame.
- **#251 Ixelles bilingual junction cue** — `source_anchored`, `visual_impact_rejected`, `closed_without_merge`. Exact source junction/name evidence was correct, but direct-player A/B changed only 212 pixels above the >8-RGB threshold, below the predeclared 300-pixel gate. Do not enlarge/move the plaques or redesign the camera to rescue this micro-cue.
- **#252 Atomium Topo esplanade context** — `source_coverage_positive`, `technically_green`, `capture_required`, `keep_draft`. Bounded official UrbIS Topo now locks 19 immediate features within 90 m of the Atomium anchor: 14 `BB03L` (`Escalier/escalator/rampe`) and 5 `CR39L` (`Banc`). Exact-head generic/source/runtime gates are green. Integration is blocked until deterministic 1280×960 hero + 1280×720 direct-player A/B prove visible Heysel identity and no debug-line/clutter effect. `BB03L` must not be mislabeled as exclusively surveyed stairs; vertical/profile presentation values remain authored and non-collision.
- **#247 Atomium measured glazed pavilion** — `source_truth_rejected`, `visual_impact_rejected`, `closed_without_merge`. The proposed 4.027 m facade height came from low-quality landmark-contaminated DSM-DTM evidence and changed only ~0.143% of the hero frame.
- **#248 historic shopfront vocabulary** — `source_disciplined`, `visual_identity_rejected`, `closed_without_merge`. Readable but generic at normal street scale.
- **#246 Grand-Place StreetSurface witness** — `full_frame_impact`, `recognition_rejected`, `closed_without_merge`. Official surface changed ~47.42% of the frame but the witness lacked recognizable Grand-Place architecture.
- **#244 Atomium StreetSurface context** — `visual_impact_rejected`, `closed_without_merge`.
- **#231 shared STIB surface-stop vocabulary** — `technically_green`, `human_visual_accepted`, `placement_source_deferred`, `keep_draft`. Preserve the accepted family; no shelter/furniture placement until independent evidence proves the real subset.
- **#223 Midi blue-stone material** — `source_disciplined`, `visual_impact_rejected`, `keep_draft`.
- **#220 Atomium trees** — `source_coverage_rejected`, `closed_without_merge`.
- **#222 Bourse vault proxy** — `source_truth_rejected`, `closed_without_merge`.

## Latest shipped player-facing gains

- **#243 bilingual Brussels street-name plaque** — reusable Brussels language identity.
- **#242 direct Ixelles Web/player spawn** — first bounded Ixelles slice directly inspectable by the player.
- **#241 Bourse roof winding normalization** — source-preserving improvement to the hero roof/interior layer.
- **#239 Ixelles compact runtime micro-slice** — clean production foundation for one real Ixelles cell.
- **#230 Atomium direct Web spawn** — landmark immediately reachable/testable.
- **#226 Atomium deterministic reflection environment** — stronger stainless response.
- **#217 Bourse white-stone portico** — stronger six-column readability.
- **#215 Midi/Fonsny Fauquenberg brick** — large flat façade response replaced by source-scaled procedural brick.
- **#214 Atomium stainless presentation** — improved metallic landmark response.

## Current top 5 perceived-quality bottlenecks

1. **Grand-Place still lacks recognizable authoritative architecture in the arrival frame** — `visual_gap_critical`. #250 proves that simply adding more existing generic masses does not solve recognition. The next Centre lot needs authoritative frontage/massing identity before paving presentation returns.
2. **Bourse roof/interior volumes + immediate surrounding frontage** — `visual_gap_high`. #241 improves the authoritative roof layer, but simplified/incomplete structure remains visible. No proxy pediment or invented landmark dimensions.
3. **Ixelles is directly playable but visually generic beyond terrain/streets/massing** — `identity_gap_high`. #251 proves micro-signage is too weak from the shipped player view. Prefer one larger source-backed frontage/material/roofline or vegetation cue occupying meaningful screen area.
4. **Midi lacks unmistakable STIB/station/public-space identity** — `visual_gap_high`. #215 brick is shipped and #231 proves a strong transit cue, but placement truth is explicitly deferred.
5. **Atomium immediate public realm/pavilion/supports remain incomplete** — `visual_gap_high`. #252 is the first recent Laeken context lot with materially positive authoritative feature density; dedicated player-facing capture is now the hard gate.

## Active ownership map

- **Centre Vertical Slice** — owns Bourse/Centre/Midi/Grand-Place visible geography. No integration-ready Centre PR. After #250 rejection, next work must first add authoritative Grand-Place frontage/massing identity or a materially larger Bourse/Midi correction, not another paving-only or micro-frontage lot.
- **Visual Assets + Atmosphere** — owns shared PBR/furniture/signage/vegetation/lighting/weather/audio. #243 is shipped. #231 remains preserved but placement-deferred. Avoid generic free-standing props/modules that do not create obvious Brussels identity.
- **Ixelles Runtime Slice** — #239 and #242 are shipped. #251 is closed/rejected for weak impact. Next lot remains inside the same cell and must affect a larger in-frame identity cue; no infrastructure/geography expansion.
- **Laeken Hero Impact** — #214/#226/#230 are shipped. #252 is the single active Laeken context lot. It has good source density but is not integration-ready until hero/direct-player captures pass human review.
- **Impact Director maintenance** — Traffic/Living City/missions/saves/release only for blockers, regressions or unusually high perceived-impact opportunities.

## Stream health

- **Centre** — `drift_risk_high`: #250 had full-frame impact but still failed Brussels recognition. Stop optimizing paving/camera metrics without authoritative architecture.
- **Visual Assets + Atmosphere** — `productive_but_source_blocked`: bilingual signage shipped; STIB asset accepted but placement deferred; generic shopfront rejected.
- **Ixelles** — `productive_but_identity_micro_risk`: runtime/access are strong, but #251 shows that tiny cues are not enough. Next cue must occupy meaningful screen area.
- **Laeken** — `productive`: #252 has real source coverage and all technical gates green, but capture/human impact is now mandatory before merge.

## Shared priorities

1. **Authoritative Grand-Place frontage/massing identity** before another plaza-paving attempt.
2. **#252 Atomium esplanade context capture gate** — hero + direct-player A/B, with semantic discipline for `BB03L` and authored vertical profiles.
3. **Larger Ixelles identity cue** in the existing `?spawn=ixelles` view — frontage/material/roofline/vegetation rather than micro-signage.
4. **#231 STIB family preserved, not actively integrated** until new placement/furniture evidence appears.
5. Atmosphere/wet/night only after the chosen frame has credible geometry/street identity.

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

**No open runtime PR is integration-ready yet. #252 is the strongest current active candidate because its bounded official Topo density is materially positive and all exact-head technical gates are green, but it must first produce dedicated Atomium hero/direct-player A/B and pass human impact/semantic review. In parallel, Centre should stop Grand-Place paving work and obtain authoritative architecture-bearing frontage/massing; Ixelles should pivot from micro-signage to one larger source-backed identity cue in the already shipped player view.**
