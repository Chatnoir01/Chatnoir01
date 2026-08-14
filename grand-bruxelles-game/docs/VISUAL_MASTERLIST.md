# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This file is the player-facing priority backlog, not a completeness claim.

Current production checkpoint: `cc36b6cb5998f6fb5480674858dc63352e3cdc2d` (Direction-only merge #245). Latest substantive player-facing Web publication remains `5c306cdae9fe5439bd3bd87796ae1730cf0aefc7`, containing shipped #241 Bourse roof winding, #242 direct Ixelles entry and #243 bilingual Brussels street-name plaque.

## North star

Ask at every zone: **if a real Brussels photo or observation is beside the game, what gives the game away in the first three seconds?**

Optimize three horizons:

1. **3 seconds** — silhouette, proportions, materials, landmark/street identity, obvious placeholders.
2. **30 seconds** — signage, transport vocabulary, furniture, motion, clutter, lighting and atmosphere.
3. **10 minutes** — playable continuity, navigation, believable traffic/PNJ behavior, missions/saves and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient. Source truth and direct player-facing inspection are hard gates.

## Director gates — 2026-08-14 11:09 Brussels

- **#243 bilingual Brussels street-name plaque** — `shipped`, `shared_identity_gain`. Reusable FR/NL plaque family is in production. Permanent surveyed placement remains a separate source-truth gate.
- **#242 direct Ixelles player/Web entry** — `shipped`, `player_access_gain`. `?spawn=ixelles` exposes the shipped one-cell micro-slice without adding geography or unresolved heights.
- **#241 Bourse official roof winding** — `shipped`, `source_preserving_roof_gain`. Existing UrbIS3D ROOFSURFACE geometry is kept while exterior winding is normalized for deterministic culling.
- **#239 Ixelles compact visible micro-slice** — `shipped`, `runtime_foundation_gain`. One cell only; 309 StreetSurfaces, 277 StreetAxes, 260 strong-source-height buildings, 460 unresolved-height buildings absent.
- **#247 Atomium measured glazed pavilion** — `source_truth_rejected`, `visual_impact_rejected`, `closed_without_merge`. Heritage semantics support a 26 m circular fully glazed pavilion, but the proposed 4.027 m facade height came from a `height_quality: low`, landmark-contaminated DSM-DTM distribution and is not a defensible facade-top measurement. Exact 1280×960 A/B changed only about 1,757 pixels above 8 RGB (~0.143%). Preserve semantics; do not promote the contaminated median to landmark geometry.
- **#248 historic shopfront vocabulary** — `source_disciplined`, `visual_identity_rejected`, `closed_without_merge`. Readable historic commercial vocabulary, but still generic at normal street scale. Do not manufacture impact with branding or fabricated surrounding facade geometry.
- **#246 Grand-Place StreetSurface witness** — `full_frame_impact`, `recognition_rejected`, `closed_without_merge`. Official surface changed ~47.42% of the 1280×720 frame, proving non-micro impact, but the witness was sky + flat ground with no recognizable Grand-Place architecture and a dark slab foreground. Next Grand-Place work must first establish architecture in the deterministic arrival frame.
- **#244 Atomium StreetSurface context** — `visual_impact_rejected`, `closed_without_merge`. Official surfaces produced sparse slivers only; do not inflate coverage/material contrast.
- **#231 shared STIB surface-stop vocabulary** — `technically_green`, `human_visual_accepted`, `placement_source_deferred`, `keep_draft`. Two source-truth passes identified Suède / Zweden on Fonsny as a real candidate stop, but still did not establish surveyed pole pose or the actual shelter/bench/info subset. Preserve the accepted family; stop spending cycles on placement until new geolocated imagery, asset inventory or equivalent evidence appears.
- **#223 Midi blue-stone material** — `source_disciplined`, `visual_impact_rejected`, `keep_draft`. Preserve for closer/source-confirmed reuse; do not retune for pixel delta.
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

1. **Grand-Place arrival lacks recognizable architecture in the production witness** — `visual_gap_critical`. #246 proved the plaza foreground can change a large fraction of the frame, but a paving-only frame is not Brussels recognition. First establish an architecture-bearing arrival witness, then correct one coherent source-backed massing/frontage/paving/signage giveaway.
2. **Bourse roof/interior volumes + immediate surrounding frontage** — `visual_gap_high`. #241 improves the authoritative roof layer, but simplified/incomplete structure remains visible. No proxy pediment or invented landmark dimensions.
3. **Ixelles is directly playable but visually generic beyond terrain/streets/massing** — `player_access_shipped`, `identity_gap_high`. It now offers the cleanest low-risk opportunity for a single source-backed local identity cue visible directly in `?spawn=ixelles`.
4. **Midi lacks unmistakable STIB/station/public-space identity** — `visual_gap_high`. #215 brick is shipped and #231 proves a strong transit cue, but placement truth has been explicitly deferred after two unsuccessful evidence passes.
5. **Atomium immediate pavilion/context/supports remain incomplete** — `visual_gap_high`. Stainless, reflections and direct spawn are strong; #247 confirms that weak vertical evidence must not be promoted merely to fill the base.

## Active ownership map

- **Centre Vertical Slice** — owns Bourse/Centre/Midi visible geography. No integration-ready high-impact PR at this checkpoint. #246 is closed diagnostic evidence. Next lot should establish a recognizable Grand-Place architecture-bearing witness or a materially large authoritative Bourse/Midi correction.
- **Visual Assets + Atmosphere** — owns shared PBR/furniture/signage/vegetation/lighting/weather/audio. #243 is shipped. #231 is preserved but placement work is deferred pending new evidence; do not style/retune it. The stream should pivot to another unmistakable reusable identity cue rather than generic modules.
- **Ixelles Runtime Slice** — #239 and #242 are shipped. Infrastructure phase is over. Next lot stays in the same cell and adds one visible source-backed Ixelles identity cue only.
- **Laeken Hero Impact** — #214/#226/#230 are shipped. #247 is closed. Preserve the factual 26 m circular fully glazed pavilion semantics, but do not create height/roof/access geometry without a defensible source. Pivot to another high-impact source-bounded context fact if vertical evidence remains blocked.
- **Impact Director maintenance** — Traffic/Living City/missions/saves/release only for blockers, regressions or unusually high perceived-impact opportunities.

## Stream health

- **Centre** — `drift_risk_high`: repeatedly finds either micro-deltas or full-frame changes without Brussels recognition. Must optimize witness composition + source-backed architecture, not commit count.
- **Visual Assets + Atmosphere** — `productive_but_pivot_needed`: bilingual signage shipped; STIB placement truth is deferred; generic shopfront family was correctly rejected. Next cue must be unmistakably Brussels and source-defensible.
- **Ixelles** — `productive`: runtime + direct access shipped. Must now convert technical fidelity into local visual identity.
- **Laeken** — `productive_but_fact_blocked`: landmark material/reflection/access are strong; context attempts must stop when source truth or screen impact is weak.

## Shared priorities

1. **Ixelles first identity cue** in the shipped `?spawn=ixelles` view: frontage/material/vegetation/signage with strong source support and obvious street-scale impact.
2. **Grand-Place architecture-bearing deterministic arrival witness**, followed immediately by one coherent full-frame correction.
3. Source-defensible bilingual wayfinding/street-name placements using #243.
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

**No currently open runtime PR is integration-ready. The highest-value clean next target is one source-backed Ixelles identity cue in the already shipped/player-accessible cell: it has low infrastructure risk and can directly improve the 3-second and 30-second experience. Centre should prepare the next Grand-Place correction only after the deterministic arrival witness actually contains recognizable Grand-Place architecture. #231 remains preserved as a strong asset family, but production placement is explicitly deferred until new evidence appears.**