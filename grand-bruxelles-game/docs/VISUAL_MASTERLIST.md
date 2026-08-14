# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This backlog optimizes player-perceived Brussels quality, not commit count.

Current production checkpoint: `85de060bbbf7233c3bafd0ca9cbb866684c286af` (#274, Direction/docs only). Latest substantive player-facing merge remains #272 Grand-Place 1786758 white-stone identity; latest corresponding published Web build remains `f4e9a84e45ca06d4bb80c82f424523a5d766bafe`.

## North star

Ask at every zone: **if a real Brussels photo or observation is beside the game, what gives the game away in the first three seconds?**

Optimize three horizons:
1. **3 seconds** — silhouette, proportions, materials, landmark/street identity, obvious placeholders.
2. **30 seconds** — signage, transport vocabulary, furniture, motion, clutter, lighting and atmosphere.
3. **10 minutes** — playable continuity, navigation, believable traffic/PNJ behavior, missions/saves and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient. Source truth and direct player-facing inspection are hard gates.

## Director gates — 2026-08-14 19:08 Brussels

### Leading active candidate

- **#280 Grand-Place source-backed granite paving** — `open`, `leading_candidate`, `DIRECTOR_EVIDENCE_BLOCKED`. Exact-current-main base. Uses exact official Paradigm/UrbIS StreetSurface `42405` / Grand-Place–Grote Markt polygon: official area 5,337 m²; stored 100-point Lambert72 ring computes 5,336.610 m². urban.brussels independently identifies the square as granite-paved. Geometry is not authored/scaled/rectangularized; paving-unit/joint dimensions are not invented. Presentation RGB/roughness/broad mineral variation remain explicitly authored rather than measured.
  - Reported deterministic 1280×720 impact after a moiré-rejection revision: 363,750 pixels >3 RGB = 39.4694%; 348,067 >8 RGB = 37.7677%.
  - General test, Game CI, Branch Hygiene, Photo Match, Performance, Web Export and dedicated granite gate are green on head `5f6f2ba2149ff9167f7b14ed57a9515a7c8d65e4`.
  - **Blocking evidence defect:** downloaded Actions artifact `grand-place-granite-paving-visual-evidence` (`sha256:cddfea6c5f5ad259866acb53a02d39e77b53e304a0c499f8c2f095d9a87ca286`) contains only the two logs; the workflow-declared `before.png` and `after.png` are absent. Logs prove the witness ran, but Director cannot independently inspect the actual pixels. Do not merge until the same PR packages both real PNGs and they pass direct human inspection without moiré/noise/z-fighting or reduced architecture readability.
  - Visual Assets + Atmosphere owns this exact lot. Centre must not duplicate Grand-Place paving while #280 is unresolved.

### Shipped anchors

- **#272 Grand-Place building 1786758 white-stone identity** — `shipped`, `major_material_identity_gain`. Existing official LoD2 geometry retained; independently sourced white-stone identity for the visible mass. 50,274 pixels >3 RGB = 5.4551% of 1280×720. Human accepted.
- **#265 Grand-Place Town Hall white-stone walls** — `shipped`, `major_material_identity_gain`. 57,970 pixels >3 RGB = 6.2901%. Human accepted.
- **#260 Grand-Place official LoD2 mass 1786758** — `shipped`, `ensemble_gain`. 65,125 pixels >3 RGB = 7.0665%.
- **#257 Grand-Place official LoD2 landmark mass 1655673** — `shipped`, `major_silhouette_gain`. ~102,017 pixels >3 RGB = 11.07%.
- **#258 Ixelles Stassart 124 blue-stone frontage** — `shipped`, `local_identity_gain`. 111,611 direct-player pixels >=12/255; 460 unresolved-height buildings remain absent.
- **#254 Atomium direct 48° framing** — `shipped`, `major_landmark_presentation_gain`. Same source-bounded position/pitch; ~43.08% >8 RGB.
- **#243 bilingual Brussels street-name plaque**, **#242 direct Ixelles entry**, **#241 Bourse roof winding**, **#239 Ixelles compact runtime**, **#230 Atomium direct entry**, **#226 Atomium reflections**, **#217 Bourse white-stone portico**, **#215 Midi/Fonsny brick**, **#214 Atomium stainless** remain production foundations.

### Fresh verdicts / rejected paths

- **#275 Midi official-forecourt reveal** — `closed_without_merge`. Keep as evidence only; do not reopen automatically.
- **#278 Ixelles Place Stéphanie 8 frontage** — `closed_without_merge`. Evidence remains usable, but no active Ixelles lot follows from it automatically.
- **#273 Grand-Place architectural illumination** — `closed_without_merge`, `source_disciplined_but_impact_rejected`. Daylight witness changed only 0.1360% >3 RGB / 0.0920% >8 RGB. Reconsider only under a real night/time-of-day presentation.
- **#268 Atomium official pavilion LoD2** — `closed_without_merge`, `exact_source_repaired_but_impact_rejected`. Exact topology corrected to 19 faces / 60 triangles / 6.674 m source height, but locked hero A/B still changed 0 pixels.
- **#267 Midi bilingual station identity** — `closed_without_merge`, `impact_zero`. Dedicated A/B pixel-identical; no oversized text/camera/emission rescue.
- **#269 Town Hall slate roof** — `closed_without_merge`, `source_disciplined_but_human_impact_rejected`. 3.4419% >3 RGB but too subtle at full-frame inspection.
- **#231 STIB surface-stop vocabulary** — `closed_evidence`, asset family accepted but placement/furniture truth unproven. Future use requires fresh current-main implementation after an official stop and defensible furniture subset are established.
- **#261 Ixelles discovery** — `closed_evidence`; candidate facts may inform a future compact lot, never merge its history.
- **#223 Midi blue-stone**, **#235 bins**, **#227 micro-material context**, generic shopfront lots — rejected for weak/generic identity or low impact.
- **#222 Bourse vault proxy** — source-truth rejected.
- Long-lived **#2/#11** remain evidence/lab only and are never merge units. Old #165/#182/#204 remain stale evidence, not integration candidates.

### Prototype quarantine — not production progress

- **#276 LimboAI NPC bridge** — `draft_prototype_only`. Production `NpcBehaviorModel`/`NpcAgent` unchanged. Do not integrate until a separate current-main playable A/B proves better multi-step police/civilian behavior while preserving Web and existing NPC contracts.
- **#277 60 Hz physical vehicle dynamics** — `draft_prototype_only`. Production vehicle controller unchanged. Current probe is technically promising, but production acceptance requires wiring to the real player car and a playable handling/braking A/B plus Web regression.
- **#279 modern player locomotion layer** — `draft_prototype_only`. Production player controller unchanged. Requires real playable A/B and Web/mobile regression before any production wiring.

## Active ownership map

- **Centre Vertical Slice** — while #280 is active, do **not** touch Grand-Place paving/material files. Next non-overlapping priority is a materially large authoritative Bourse roof/interior/envelope correction, then a real Midi station frontage/entrance/forecourt correction. Avoid micro-frontages, floating labels and proxy landmark geometry.
- **Visual Assets + Atmosphere** — owns **#280 only** until resolved. No second shared asset lot. Fix evidence packaging, inspect the real PNG A/B, then either integrate or reject on visual quality.
- **Ixelles Runtime Slice** — #239/#242/#258 shipped; no active production lot. Same-cell quality only; no terrain/infrastructure reopening or unresolved-height buildings.
- **Laeken Hero Impact** — #214/#226/#230/#254 shipped; no active production lot. Next context candidate must have meaningful projected screen area and clean source truth.
- **Impact Director maintenance** — Traffic/Living City/missions/saves/release remain maintenance-only unless a blocking regression or unusually high perceived-impact opportunity appears. Prototypes #276/#277/#279 are quarantined experiments, not maintenance integration candidates.

## Current top 5 perceived-quality bottlenecks

1. **Grand-Place coherent detailed recognition** — `visual_gap_high_but_improving_fast`. Architecture and white-stone identity are stronger; the square ground/context is still a major giveaway. #280 could be the largest next first-impression gain, but only after real PNG inspection.
2. **Bourse roof/interior volumes + immediate frontage** — `visual_gap_high`. Existing portico/roof/surface gains are real, but simplified structure remains obvious. No proxy pediment or authored landmark dimensions.
3. **Midi station/STIB/public-space identity** — `visual_gap_high`. Brick improved; label/forecourt experiments have not solved the actual entrance/transport/public-space weakness.
4. **Ixelles local identity density** — `identity_gap_medium_high`. Direct access and Stassart 124 are shipped; another substantial same-cell cue is needed, not research/infrastructure.
5. **Atomium immediate site context/pavilion/supports** — `visual_gap_high`. Landmark presentation is strong; context candidates must actually occupy the direct-player view.

## Stream health

- **Centre** — `productive_but_temporarily_nonoverlap`: recent Grand-Place gains are strong; avoid competing with #280 and pivot to Bourse/Midi until paving resolves.
- **Visual Assets + Atmosphere** — `high_value_candidate_evidence_blocked`: #280 has exceptional reported impact but cannot pass Director human acceptance until PNG evidence is actually retrievable.
- **Ixelles** — `productive_no_active_lot`: shipped runtime/access/frontage healthy; avoid low-impact follow-ups.
- **Laeken** — `presentation_strong_context_blocked`: no active lot; do not deepen old evidence chains.
- **Prototype experiments** — `properly_quarantined`: potentially valuable for the 30-second/10-minute feel, but zero production credit until real playable A/B evidence exists.

## Shared priorities

1. **Resolve #280 Grand-Place granite evidence** — same runtime result, real downloadable PNG A/B, direct human review; integrate only if coherent and artifact-free.
2. **Bourse high-area structure correction** — authoritative roof/interior/envelope while Grand-Place paving is owned elsewhere.
3. **Midi real station architecture / transport context** — solve entrance/public-space weakness rather than labels.
4. **Ixelles second substantial local identity cue** — same shipped cell, fresh compact lot only.
5. **Atomium context with real screen area** — only when source confidence and projected occupancy are both high.
6. Prototype handling/locomotion/AI can compete only after current-main playable A/B proves a major 30-second or 10-minute improvement.

## Production rules

1. Exact current `main` is the only production truth.
2. One active lot per exact problem/domain.
3. Small current-main PRs only; re-check `main` and active PRs before push/PR/merge.
4. Publication-only commits are not new gameplay/visual truth.
5. Prefer Paradigm/UrbIS/UrbIS3D, Brussels Mobility, STIB and official orthophoto/DTM/DSM. OSM is complement, not proof for unresolved geometry/traffic semantics.
6. Preserve lawful provenance/licensing; never distribute reference imagery as textures without permission.
7. Evidence-only work is allowed only when it can unlock material player-facing improvement within one or two lots.
8. Green CI can still be rejected for negligible player impact, weak source truth, or missing human-inspectable evidence.
9. Substantive lots require deterministic player-facing evidence, human inspection, relevant tests, branch hygiene and performance when applicable.
10. Pixel delta is evidence, not the objective. Judge recognition, silhouette, street proportions, material response, atmosphere, legibility, motion and gameplay feel.

## Director next-integration priority

**#280 Grand-Place granite paving is the single highest-impact next integration candidate, conditionally. Do not merge until its Actions artifact actually contains the 1280×720 before/after PNGs and direct human inspection confirms that the large ground change reads as believable granite without moiré/noise/z-fighting and without harming the shipped Grand-Place architecture. While #280 is blocked, Centre should work only on a non-overlapping high-area Bourse/Midi discrepancy.**
