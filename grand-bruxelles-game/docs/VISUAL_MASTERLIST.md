# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This backlog optimizes player-perceived Brussels quality, not commit count.

Current production checkpoint: `f4e9a84e45ca06d4bb80c82f424523a5d766bafe` (publication-only). Latest substantive player-facing merge: `15ae99f937b50dc9a2abb8aab92f8d86164b5241` (#272 Grand-Place 1786758 white-stone identity).

## North star

Ask at every zone: **if a real Brussels photo or observation is beside the game, what gives the game away in the first three seconds?**

Optimize three horizons:
1. **3 seconds** — silhouette, proportions, materials, landmark/street identity, obvious placeholders.
2. **30 seconds** — signage, transport vocabulary, furniture, motion, clutter, lighting and atmosphere.
3. **10 minutes** — playable continuity, navigation, believable traffic/PNJ behavior, missions/saves and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient. Source truth and direct player-facing inspection are hard gates.

## Director gates — 2026-08-14 18:08 Brussels

### Shipped anchors

- **#272 Grand-Place building 1786758 white-stone identity** — `shipped`, `major_material_identity_gain`. Existing official LoD2 geometry retained; independently sourced white-stone identity for the Le Cygne/L'Etoile mass. Deterministic 1280×720 A/B: 50,274 pixels >3 RGB = 5.4551%, bbox x=184..461 / y=316..625. Human accepted; no geometry/roof/opening drift.
- **#265 Grand-Place Town Hall white-stone walls** — `shipped`, `major_material_identity_gain`. 57,970 pixels >3 RGB = 6.2901% of 1280×720. Human accepted.
- **#260 Grand-Place official LoD2 mass 1786758** — `shipped`, `ensemble_gain`. 65,125 pixels >3 RGB = 7.0665%.
- **#257 Grand-Place official LoD2 landmark mass 1655673** — `shipped`, `major_silhouette_gain`. ~102,017 pixels >3 RGB = 11.07%.
- **#258 Ixelles Stassart 124 blue-stone frontage** — `shipped`, `local_identity_gain`. 111,611 direct-player pixels >=12/255; 460 unresolved-height buildings remain absent.
- **#254 Atomium direct 48° framing** — `shipped`, `major_landmark_presentation_gain`. Same source-bounded position/pitch; ~43.08% >8 RGB.
- **#243 bilingual Brussels street-name plaque**, **#242 direct Ixelles entry**, **#241 Bourse roof winding**, **#239 Ixelles compact runtime**, **#230 Atomium direct entry**, **#226 Atomium reflections**, **#217 Bourse white-stone portico**, **#215 Midi/Fonsny brick**, **#214 Atomium stainless** remain production foundations.

### Fresh verdicts / rejected paths

- **#273 Grand-Place architectural illumination** — `closed_without_merge`, `source_disciplined_but_impact_rejected`. Daylight witness changed only 1,253 pixels >3 RGB = 0.1360% and 848 >8 RGB = 0.0920%. Do not revive before a real night/time-of-day presentation exists; do not inflate authored light energy to manufacture impact.
- **#268 Atomium official pavilion LoD2** — `closed_without_merge`, `exact_source_repaired_but_impact_rejected`. Exact topology drift was diagnosed and repaired to the official 19 faces / 60 triangles / 6.674 m source height, but hero A/B still changed 0 pixels at the locked witness. Preserve source evidence; do not merge this geometry merely because it is correct.
- **#267 Midi bilingual station identity** — `closed_without_merge`, `impact_zero`. Dedicated 1280×720 A/B rendered successfully but remained pixel-identical (`changed=0`). Do not rescue via oversized typography, camera changes or fake emission.
- **#269 Town Hall slate roof** — `closed_without_merge`, `source_disciplined_but_human_impact_rejected`. Corrected A/B measured 3.4419% >3 RGB but full-frame review found the shift too subtle.
- **#231 STIB surface-stop vocabulary** — `closed_evidence`, `asset_family_accepted_but_placement_unproven`. Any future use requires a fresh current-main lot with an official stop and independently defensible furniture subset.
- **#261 Ixelles next-identity discovery** — `closed_evidence`. Candidate evidence may inform a fresh compact current-main cue; do not merge history.
- **#223 Midi blue-stone**, **#235 bins**, **#227 micro-material context**, generic shopfront lots — rejected for weak/generic identity or low impact.
- **#222 Bourse vault proxy** — source-truth rejected.
- Long-lived **#2/#11** remain evidence/lab only and are never merge units. Old #165/#182/#204 remain stale evidence ownership, not integration candidates.

## Active ownership map

- **Centre Vertical Slice** — no active runtime PR after #272 shipped. Grand-Place has strong massing + white-stone identity on two large masses; next lot must increase coherent Grand-Place recognition, not object count or daylight micro-lighting. If no high-impact source-backed Grand-Place cue clears the gate quickly, pivot to a materially large Bourse roof/interior or Midi station-frontage correction.
- **Visual Assets + Atmosphere** — no active PR. Shared signage foundation #243 is shipped. #231 is closed evidence. Next shared lot must be a fresh current-main Brussels-specific cue with strong placement truth and normal-distance visibility.
- **Ixelles Runtime Slice** — #239/#242/#258 shipped; no active PR. Next cue must stay in the same one-cell production slice and approach #258's visible quality bar. No infrastructure reopening or unresolved-height buildings.
- **Laeken Hero Impact** — no active runtime PR after #268 rejection. Shipped #214/#226/#230/#254 remain the presentation base. Next candidate must improve immediate site context/pavilion/public realm with meaningful projected area and clean source truth.
- **Impact Director maintenance** — Traffic/Living City/missions/saves/release remain maintenance-only unless a blocking regression or unusually high perceived-impact opportunity appears.

## Current top 5 perceived-quality bottlenecks

1. **Grand-Place coherent detailed recognition** — `visual_gap_high_but_improving_fast`. Two official masses and two major white-stone identity passes now read much better; openings, roof detail, secondary façades, paving and square context still remain simplified. Next work must add coherence, not count.
2. **Bourse roof/interior volumes + immediate frontage** — `visual_gap_high`. Existing portico/roof/surface gains are real, but simplified structure remains obvious. No proxy pediment or authored landmark dimensions.
3. **Midi station/STIB/public-space identity** — `visual_gap_high`. Brick is improved, but both #267/#263 showed that labels/panels cannot compensate for weak real entrance/frontage geometry. Future work should target source-backed station architecture or transport context with meaningful screen area.
4. **Ixelles local identity density** — `identity_gap_medium_high`. Direct access and Stassart 124 are shipped; another substantial local cue is needed in the same cell, not more infrastructure or micro-signage.
5. **Atomium immediate site context/pavilion/supports** — `visual_gap_high`. Landmark framing/material response is strong; official pavilion LoD2 correctness alone proved visually insufficient at the current witness. Future work must target a context cue that actually occupies the player view.

## Stream health

- **Centre** — `high_player_value_but_guard_against_diminishing_returns`: #257/#260/#265/#272 are strong. #273 proves daylight lighting is not the next gain. Require a coherent full-frame cue or pivot.
- **Visual Assets + Atmosphere** — `needs_fresh_high_identity_target`: useful shared foundations exist, but no active placement-ready cue. Avoid stale STIB or generic props.
- **Ixelles** — `productive_with_no_active_lot`: runtime/access/frontage are healthy. Next change should be one major local identity cue from fresh main.
- **Laeken** — `presentation_strong_context_blocked`: pavilion source geometry is solved but visually negligible. Do not deepen evidence chains; pick a different high-area site/context discrepancy.

## Shared priorities

1. **Grand-Place coherent recognition after #272** — one high-area source-backed frontage/material/context cue that complements the two visible masses; reject micro-lighting/object-count accumulation.
2. **Bourse high-area structure correction** — authoritative roof/interior/envelope work if Centre cannot clear another Grand-Place gate quickly.
3. **Midi real station architecture / transport context** — solve the underlying entrance/public-space weakness rather than adding more labels.
4. **Ixelles second substantial local identity cue** — fresh compact exact-current-main lot, same shipped cell.
5. **Atomium context with real screen area** — only when source confidence and projected occupancy are both high.
6. Atmosphere/wet/night after geometry/local identity support it; #273 can be reconsidered only under a real night presentation.

## Production rules

1. Exact current `main` is the only production truth.
2. One active lot per exact problem/domain.
3. Small current-main PRs only; re-check `main` and active PRs before push/PR/merge.
4. Publication-only commits are not new gameplay/visual truth.
5. Prefer Paradigm/UrbIS/UrbIS3D, Brussels Mobility, STIB and official orthophoto/DTM/DSM. OSM is complement, not proof for unresolved geometry/traffic semantics.
6. Preserve lawful provenance/licensing; never distribute reference imagery as textures without permission.
7. Evidence-only work is allowed only when it can unlock material player-facing improvement within one or two lots.
8. Green CI can still be rejected for negligible player impact or weak source truth.
9. Substantive lots require deterministic player-facing evidence, human inspection, relevant tests, branch hygiene and performance when applicable.
10. Pixel delta is evidence, not the objective. Judge recognition, silhouette, street proportions, material response, atmosphere, legibility, motion and gameplay feel.

## Director next-integration priority

**Highest-value next candidate: one coherent, source-backed Grand-Place identity/context cue that builds on shipped #257/#260/#265/#272 and is obvious at the locked production witness. Do not add a third/fourth neutral object merely for count and do not revisit daylight illumination. If no such cue clears the anti-micro/source-truth gate in one bounded pass, pivot immediately to a large Bourse roof/interior or Midi station-frontage correction.**
