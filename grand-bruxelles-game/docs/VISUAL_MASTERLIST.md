# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This backlog optimizes player-perceived Brussels quality, not commit count.

Current production checkpoint: `cb7fe2056397415f0ff1b43abed023855e8aae0e` (publication-only Web commit). Latest substantive player-facing merge: `f1a9ac41864fd63a53b95a2975d2d3a3e6ef3736` (#280 Grand-Place source-backed granite paving).

## North star

Ask at every zone: **if a real Brussels photo or observation is beside the game, what gives the game away in the first three seconds?**

Optimize three horizons:
1. **3 seconds** — silhouette, proportions, materials, landmark/street identity, obvious placeholders.
2. **30 seconds** — signage, transport vocabulary, furniture, motion, clutter, lighting and atmosphere.
3. **10 minutes** — playable continuity, navigation, believable traffic/PNJ behavior, missions/saves and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient. Source truth and direct player-facing inspection are hard gates.

## Director gates — 2026-08-14 19:12 Brussels

### Fresh production change

- **#280 Grand-Place source-backed granite paving** — `shipped`, `major_ground_identity_gain`, `post_merge_evidence_debt`. Exact official Paradigm/UrbIS StreetSurface `42405` / Grand-Place–Grote Markt polygon: official 5,337 m²; stored 100-point Lambert72 ring computes 5,336.610 m². urban.brussels independently identifies the square as granite-paved. Geometry is not authored/scaled/rectangularized; paving-unit dimensions and joint patterns are not invented. Presentation RGB/roughness/broad mineral variation are explicitly authored rather than measured.
  - Reported deterministic 1280×720 impact after a moiré-rejection revision: 363,750 pixels >3 RGB = 39.4694%; 348,067 >8 RGB = 37.7677%.
  - General tests, Game CI, Branch Hygiene, Photo Match, Performance, Web Export and dedicated granite gate were green on the merged head `5f6f2ba2149ff9167f7b14ed57a9515a7c8d65e4`.
  - **Evidence debt:** downloaded Actions artifact `grand-place-granite-paving-visual-evidence` (`sha256:cddfea6c5f5ad259866acb53a02d39e77b53e304a0c499f8c2f095d9a87ca286`) contains the two logs but not the workflow-declared 1280×720 before/after PNGs. Logs prove the witness ran, but Director could not independently inspect the pixels before another actor merged the PR. Treat the granite paving as production truth now, but require a tiny current-main QA/evidence repair that packages the exact production before/after PNGs and performs direct human inspection before starting another shared asset lot. If the real production witness reveals moiré/noise/z-fighting or harmed architecture readability, fix production immediately in a separate small corrective PR.

### Shipped anchors

- **#272 Grand-Place building 1786758 white-stone identity** — `shipped`, 50,274 pixels >3 RGB = 5.4551%; human accepted.
- **#265 Grand-Place Town Hall white-stone walls** — `shipped`, 57,970 pixels >3 RGB = 6.2901%; human accepted.
- **#260 Grand-Place official LoD2 mass 1786758** — `shipped`, 65,125 pixels >3 RGB = 7.0665%.
- **#257 Grand-Place official LoD2 landmark mass 1655673** — `shipped`, ~102,017 pixels >3 RGB = 11.07%.
- **#258 Ixelles Stassart 124 blue-stone frontage** — `shipped`, 111,611 direct-player pixels >=12/255; 460 unresolved-height buildings remain absent.
- **#254 Atomium direct 48° framing** — `shipped`, ~43.08% >8 RGB.
- **#243 bilingual Brussels street-name plaque**, **#242 direct Ixelles entry**, **#241 Bourse roof winding**, **#239 Ixelles compact runtime**, **#230 Atomium direct entry**, **#226 Atomium reflections**, **#217 Bourse white-stone portico**, **#215 Midi/Fonsny brick**, **#214 Atomium stainless** remain production foundations.

### Fresh verdicts / rejected paths

- **#275 Midi official-forecourt reveal** — `closed_without_merge`; evidence only, no automatic revival.
- **#278 Ixelles Place Stéphanie 8 frontage** — `closed_without_merge`; evidence only.
- **#273 Grand-Place daylight architectural illumination** — `closed_without_merge`, impact rejected at 0.1360% >3 RGB / 0.0920% >8 RGB. Reconsider only under a real night/time-of-day presentation.
- **#268 Atomium official pavilion LoD2** — `closed_without_merge`; exact source topology repaired but locked hero A/B still changed 0 pixels.
- **#267 Midi bilingual station identity** — `closed_without_merge`, impact zero; no oversized typography/camera/emission rescue.
- **#269 Town Hall slate roof** — `closed_without_merge`; 3.4419% >3 RGB but human full-frame impact rejected.
- **#231 STIB surface-stop vocabulary** — `closed_evidence`; asset family accepted but placement/furniture truth unproven.
- **#261 Ixelles discovery** — `closed_evidence`; never merge history.
- **#223 Midi blue-stone**, **#235 bins**, **#227 micro-material context**, generic shopfront lots — rejected for weak/generic identity or low impact.
- **#222 Bourse vault proxy** — source-truth rejected.
- Long-lived **#2/#11** remain evidence/lab only and are never merge units. Old #165/#182/#204 remain stale evidence, not integration candidates.

### Prototype quarantine — not production progress

- **#276 LimboAI NPC bridge** — `draft_prototype_only`; production NPC runtime unchanged. Requires a separate current-main playable A/B proving better multi-step behavior plus Web/NPC-regression safety.
- **#277 60 Hz physical vehicle dynamics** — `draft_prototype_only`; production vehicle controller unchanged. Technical probe is promising, but production acceptance requires real player-car wiring and a playable handling/braking A/B plus Web regression.
- **#279 modern player locomotion layer** — `draft_prototype_only`; production player controller unchanged. Requires a real playable A/B and Web/mobile regression.

## Active ownership map

- **Centre Vertical Slice** — no Grand-Place paving/material duplication after #280. While post-merge granite evidence is being repaired by Visual Assets, Centre should pursue a **non-overlapping** materially large authoritative Bourse roof/interior/envelope correction, then a real Midi station frontage/entrance/forecourt correction. Avoid micro-frontages, floating labels and proxy landmark geometry.
- **Visual Assets + Atmosphere** — owns the **post-merge #280 evidence repair only**. Do not start another shared asset lot until the exact production granite PNG A/B is packaged and human-reviewed.
- **Ixelles Runtime Slice** — #239/#242/#258 shipped; no active production lot. Same-cell quality only; no terrain/infrastructure reopening or unresolved-height buildings.
- **Laeken Hero Impact** — #214/#226/#230/#254 shipped; no active production lot. Next context candidate must have meaningful projected screen area and clean source truth.
- **Impact Director maintenance** — Traffic/Living City/missions/saves/release remain maintenance-only unless a blocking regression or unusually high perceived-impact opportunity appears. Prototype PRs #276/#277/#279 stay quarantined.

## Current top 5 perceived-quality bottlenecks

1. **Bourse roof/interior volumes + immediate frontage** — `visual_gap_high`. With Grand-Place ground now materially improved, Bourse returns to the largest clean Centre giveaway. Existing portico/roof/surface gains are real, but structure remains simplified. No proxy pediment or authored landmark dimensions.
2. **Midi station/STIB/public-space identity** — `visual_gap_high`. Brick improved, but label/forecourt experiments have not solved the real entrance/transport/public-space weakness.
3. **Grand-Place detailed coherence after #280** — `visual_gap_medium_high`. Massing, white-stone identity and granite ground are now much stronger; openings, roof detail, secondary façades, edge context and street furniture still reveal the game. Do not add more ground/material work until #280 production evidence is independently inspected.
4. **Ixelles local identity density** — `identity_gap_medium_high`. Direct access and Stassart 124 are shipped; another substantial same-cell cue is needed, not research/infrastructure.
5. **Atomium immediate site context/pavilion/supports** — `visual_gap_high`. Landmark presentation is strong; context candidates must actually occupy the direct-player view.

## Stream health

- **Centre** — `productive_nonoverlap_required`: strong recent Grand-Place gains; pivot to Bourse/Midi while granite evidence is repaired.
- **Visual Assets + Atmosphere** — `production_gain_with_evidence_debt`: #280 is a very large shipped change, but workflow artifact packaging failed the Director's independent visual-evidence requirement. Fix evidence before new work.
- **Ixelles** — `productive_no_active_lot`: shipped runtime/access/frontage are healthy; avoid low-impact follow-ups.
- **Laeken** — `presentation_strong_context_blocked`: no active lot; do not deepen rejected evidence chains.
- **Prototype experiments** — `properly_quarantined`: promising for 30-second/10-minute feel, but zero production credit until current-main playable A/B evidence exists.

## Shared priorities

1. **Repair #280 production evidence** — package the exact current production before/after PNGs and human-review them; if bad, correct production immediately.
2. **Bourse high-area structure correction** — authoritative roof/interior/envelope, non-overlapping with Grand-Place granite.
3. **Midi real station architecture / transport context** — solve entrance/public-space weakness rather than labels.
4. **Ixelles second substantial local identity cue** — same shipped cell, fresh compact lot only.
5. **Atomium context with real screen area** — only when source confidence and projected occupancy are high.
6. Prototype handling/locomotion/AI may compete only after current-main playable A/B proves a major perceived-quality gain.

## Production rules

1. Exact current `main` is the only production truth.
2. One active lot per exact problem/domain.
3. Small current-main PRs only; re-check `main` and active PRs before push/PR/merge.
4. Publication-only commits are not new gameplay/visual truth.
5. Prefer Paradigm/UrbIS/UrbIS3D, Brussels Mobility, STIB and official orthophoto/DTM/DSM. OSM is complement, not proof for unresolved geometry/traffic semantics.
6. Preserve lawful provenance/licensing; never distribute reference imagery as textures without permission.
7. Evidence-only work is allowed only when it can unlock material player-facing improvement within one or two lots.
8. Green CI can still be rejected for negligible player impact, weak source truth or missing human-inspectable evidence.
9. Substantive lots require deterministic player-facing evidence, human inspection, relevant tests, branch hygiene and performance when applicable.
10. Pixel delta is evidence, not the objective. Judge recognition, silhouette, street proportions, material response, atmosphere, legibility, motion and gameplay feel.

## Director next-integration priority

**No new shared visual integration should outrank fixing the #280 evidence debt. For new player-facing work, the highest-value non-overlapping integration target is now a materially large authoritative Bourse roof/interior/envelope correction. Centre should pursue that while Visual Assets proves the already-shipped Grand-Place granite visually from current production.**
