# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This file is the player-facing priority backlog, not a completeness claim.

Current production checkpoint: `23e00aa33592ef0e6883ea429802336e3490bbc4` (publication-only Web refresh). Latest substantive merge beneath it: `3c2941a11dca4af78f81b4f651365887a8e42f15` (#265 Grand-Place Town Hall white-stone wall presentation), following #260 second official Grand-Place LoD2 mass, #258 Ixelles Stassart 124 frontage and #254 tighter direct Atomium framing.

## North star

Ask at every zone: **if a real Brussels photo or observation is beside the game, what gives the game away in the first three seconds?**

Optimize three horizons:

1. **3 seconds** — silhouette, proportions, materials, landmark/street identity, obvious placeholders.
2. **30 seconds** — signage, transport vocabulary, furniture, motion, clutter, lighting and atmosphere.
3. **10 minutes** — playable continuity, navigation, believable traffic/PNJ behavior, missions/saves and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient. Source truth and direct player-facing inspection are hard gates.

## Director gates — 2026-08-14 15:09 Brussels

- **#265 Grand-Place Town Hall white-stone walls** — `shipped`, `major_material_identity_gain`. Keeps official UrbIS3D building `1655673` geometry/roof unchanged and applies a white-stone WALLSURFACE presentation only because urban.brussels record 31125 identifies the Grand-Place-facing Hotel de Ville façades as white stone and documents Gobertange/Euville exterior stone. Exact RGB/roughness remain authored presentation values, not photometric measurements. Dedicated 1280×720 A/B passed the anti-micro gate; Director inspection measured 57,970 pixels >3 RGB = 6.2901% of frame, with the change concentrated on the dominant Town Hall wall mass. Human accepted: the civic landmark reads materially lighter/clearer without holes, geometry drift or fake openings.
- **#260 Grand-Place official LoD2 ensemble mass 1786758** — `shipped`, `ensemble_gain`. Exact official UrbIS3D geometry, 65,125 pixels >3 RGB = 7.0665%; human accepted. #257 remains visible and dominant.
- **#257 Grand-Place official LoD2 landmark mass 1655673** — `shipped`, `major_silhouette_gain`. Official UrbIS3D building ~43 m from locked control point, ~54.02 × 67.92 m source envelope, 93.024 m vertical extent; ~102,017 pixels >3 RGB = 11.07% of 1280×720.
- **#258 Ixelles Stassart 124 blue-stone frontage** — `shipped`, `local_identity_gain`. Direct-player A/B: 111,611 pixels >=12/255; one source-backed lower-façade register in the shipped one-cell runtime; 460 unresolved-height buildings remain absent.
- **#254 Atomium direct FOV framing** — `shipped`, `major_landmark_presentation_gain`. `?spawn=atomium` uses 48° FOV while preserving source-bounded visitor position/pitch; ~43.08% of 1280×720 >8 RGB.
- **#243 bilingual Brussels street-name plaque** — `shipped`, `shared_identity_gain`.
- **#242 direct Ixelles player/Web entry** — `shipped`, `player_access_gain`.
- **#241 Bourse official roof winding** — `shipped`, `source_preserving_roof_gain`.
- **#239 Ixelles compact visible micro-slice** — `shipped`, `runtime_foundation_gain`.
- **#261 Ixelles next identity discovery** — `active_draft`, `bounded_evidence_gate`. Exact-current-main probe remains the sole active Ixelles next-cue owner. Discovery artifact confirms all three tested heritage candidates are inside the cell and already among the 260 strong-source rendered buildings: Rue de Stassart 131 / building 1633062 / 22.394 m, Place Stéphanie 8 / building 1737880 / 19.884 m, Rue des Drapiers 31 / building 1618967 / 19.1804 m. This evidence phase is allowed only because the same PR must now select at most one candidate and convert it into a substantial direct-player cue. No second discovery-only PR.
- **#263 Midi physical bilingual station identity** — `closed_without_merge`. Do not reopen the stale branch; the factual `BRUXELLES-MIDI · BRUSSEL-ZUID` identity remains valuable, but any future implementation must be exact-current-main and visibly stronger than the old floating-label presentation without copying proprietary logo/font artwork.
- **#262 Atomium pavilion annulus height probe** — `closed_without_merge`. Do not convert a noisy/contaminated DSM-DTM probe into pavilion geometry unless a future clean source establishes the vertical fact.
- **#252/#247/#244/#220 Laeken context experiments** — rejected/closed; do not revive or inflate.
- **#231 shared STIB surface-stop vocabulary** — `technically_green`, `human_visual_accepted`, `placement_source_deferred`, `keep_draft`. Asset family remains valuable; production placement still waits for a defensible real stop + furniture subset.
- **#223 Midi blue-stone material** — `source_disciplined`, `visual_impact_rejected`, `keep_draft`.
- **#222 Bourse vault proxy** — `source_truth_rejected`, `closed_without_merge`.

## Latest shipped player-facing gains

- **#265 Town Hall white-stone material identity** — turns the dominant Grand-Place civic mass from generic neutral beige into a source-backed white-stone reading over ~6.29% of the frame without changing geometry.
- **#260 second Grand-Place LoD2 mass** — expands the official architecture ensemble with another immediately visible roofed mass.
- **#258 Ixelles Stassart 124 frontage** — first strong local material/heritage identity cue inside directly playable Ixelles.
- **#257 Grand-Place LoD2 mass 1655673** — first major source-backed architecture to dominate the Grand-Place witness.
- **#254 tighter direct Atomium framing** — stronger 3-second landmark scale/readability without moving world geometry.
- **#243 bilingual Brussels street-name plaque** — reusable language identity.
- **#242 direct Ixelles Web/player spawn** — bounded Ixelles slice directly inspectable.
- **#241 Bourse roof winding normalization** — source-preserving hero roof improvement.
- **#230 Atomium direct Web spawn**, **#226 deterministic reflections**, **#217 Bourse white-stone portico**, **#215 Midi/Fonsny Fauquenberg brick**, **#214 Atomium stainless presentation**.

## Current top 5 perceived-quality bottlenecks

1. **Grand-Place now has strong massing and one correct material identity, but still lacks a coherent detailed ensemble** — `visual_gap_high_but_improving_fast`. #257 + #260 + #265 prove silhouette + material can move the frame materially. Next gain should add a clearly visible source-backed adjacent identity/frontage/material/paving/context cue only if it increases recognition; do not accumulate small neutral buildings for count.
2. **Bourse roof/interior volumes + immediate surrounding frontage** — `visual_gap_high`. #241/#217 improved the right layers, but simplified/incomplete structure remains obvious. No proxy pediment or invented landmark dimensions.
3. **Midi still lacks unmistakable station/STIB/public-space identity** — `visual_gap_high`. #215 brick is strong; #231 remains placement-blocked and #263 closed. Station frontage/entries/wayfinding/transport interface remain high-value opportunities.
4. **Ixelles is playable and has one strong local frontage but remains sparse/generic beyond it** — `identity_gap_medium_high`. #261 must now become one substantial runtime cue or close.
5. **Atomium immediate ground/context/pavilion/supports remain generic or unresolved** — `visual_gap_high`. Landmark framing/material/reflections are strong; remaining giveaway is site context.

## Active ownership map

- **Centre Vertical Slice** — owns Bourse/Centre/Midi/Grand-Place visible geography. #257/#260/#265 are shipped. A third Grand-Place object-count loop is no longer preferred; next Centre lot should add recognition through one large, source-backed architectural/material/context cue, or pivot to Bourse/Midi if the projected screen impact is weak.
- **Visual Assets + Atmosphere** — owns shared PBR/furniture/signage/vegetation/lighting/weather/audio. #243 shipped; #231 preserved but placement-deferred. Prioritize unmistakable reusable identity, not generic prop/material micro-deltas.
- **Ixelles Runtime Slice** — #239/#242/#258 shipped. #261 is the sole active next-identity owner. Same one-cell scope only; discovery must become one high-impact cue within this PR or be closed.
- **Laeken Hero Impact** — #214/#226/#230/#254 shipped. Landmark presentation is strong; next work is one source-bounded context/pavilion/public-realm correction with obvious screen impact. Rejected context/elevation probes remain rejected.
- **Impact Director maintenance** — Traffic/Living City/missions/saves/release only for blockers, regressions or unusually high perceived-impact opportunities.

## Stream health

- **Centre** — `highly_productive_now`: #257/#260/#265 delivered ~11.07%, ~7.07% and ~6.29% full-frame visual changes with strong source truth. Keep the anti-micro bar and move from raw mass accumulation toward coherent Grand-Place recognition.
- **Visual Assets + Atmosphere** — `productive_but_source_blocked_on_stib`: bilingual signage shipped; STIB family remains valuable but placement truth is deferred. Pivot if no genuinely new official placement evidence appears.
- **Ixelles** — `productive_with_evidence_risk`: runtime/access/frontage are shipped. #261 discovery successfully found three eligible rendered heritage candidates; it must now ship one visible cue or close, not deepen research.
- **Laeken** — `productive_but_context_blocked`: landmark presentation is strong after #254/#214/#226. Remaining candidates must be rejected early when source coverage or projected screen impact is weak.

## Shared priorities

1. **Grand-Place coherent recognition after #257 + #260 + #265** — add one more large source-backed recognition cue only if it improves the ensemble, not object count.
2. **Midi station/STIB identity** through source-backed frontage/entry/wayfinding or a genuinely proven #231 placement.
3. **Ixelles second local identity cue** through #261 only, inside the shipped cell, with direct-player A/B and anti-micro gate.
4. **Atomium immediate context** with source-bounded geometry/material visible in the strengthened #254 framing.
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

**Highest-value next candidate: one additional high-screen-area Grand-Place recognition cue that complements shipped #257/#260/#265, not another neutral mass for count. The preferred target is an adjacent source-backed material/frontage/architectural identity or coherent square context that is obvious in the locked 1280×720 witness. If no such Centre candidate clears the anti-micro/source-truth gate quickly, #261 Ixelles becomes the next candidate only when it converts exactly one of its three eligible heritage buildings into a substantial direct-player cue; otherwise pivot to Midi station identity.**
