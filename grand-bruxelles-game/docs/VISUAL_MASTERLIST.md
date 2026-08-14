# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This is the player-facing direction backlog, not a completeness claim.

Current production checkpoint: `30bc0016cd2cd82268b11115664d4992d5968f0d` (Direction/docs only). Latest substantive player-facing merge remains `3c2941a11dca4af78f81b4f651365887a8e42f15` (#265 Grand-Place Town Hall white-stone walls), with Web publication `23e00aa33592ef0e6883ea429802336e3490bbc4`.

## North star

Ask at every zone: **if a real Brussels photo or observation is beside the game, what gives the game away in the first three seconds?**

Optimize three horizons:

1. **3 seconds** — silhouette, proportions, materials, landmark/street identity, obvious placeholders.
2. **30 seconds** — signage, transport vocabulary, furniture, motion, clutter, lighting and atmosphere.
3. **10 minutes** — playable continuity, navigation, believable traffic/PNJ behavior, missions/saves and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient. Source truth and direct player-facing inspection are hard gates.

## Director gates — 2026-08-14 17:08 Brussels

### Shipped anchors

- **#265 Grand-Place Town Hall white-stone walls** — `shipped`, `major_material_identity_gain`. Exact official UrbIS3D geometry/roof retained; source-backed white-stone WALLSURFACE presentation. Director A/B: 57,970 pixels >3 RGB = 6.2901% of 1280×720. Human accepted.
- **#260 Grand-Place official LoD2 ensemble mass 1786758** — `shipped`, `ensemble_gain`. 65,125 pixels >3 RGB = 7.0665%; human accepted.
- **#257 Grand-Place official LoD2 landmark mass 1655673** — `shipped`, `major_silhouette_gain`. ~102,017 pixels >3 RGB = 11.07% of 1280×720.
- **#258 Ixelles Stassart 124 blue-stone frontage** — `shipped`, `local_identity_gain`. Direct-player A/B: 111,611 pixels >=12/255; 460 unresolved-height buildings remain absent.
- **#254 Atomium direct 48° FOV framing** — `shipped`, `major_landmark_presentation_gain`. Same source-bounded player position/pitch; ~43.08% of 1280×720 >8 RGB.
- **#243 bilingual Brussels street-name plaque**, **#242 direct Ixelles entry**, **#241 Bourse roof winding**, **#239 Ixelles compact runtime**, **#230 Atomium direct entry**, **#226 Atomium reflections**, **#217 Bourse white-stone portico**, **#215 Midi/Fonsny brick**, **#214 Atomium stainless** remain production foundations.

### Active / newly adjudicated

- **#268 Atomium pavilion official LoD2 runtime** — `active_draft`, `source_candidate_strong_but_runtime_blocked`. Official Paradigm/UrbIS3D building `1651628` remains the best current Laeken source candidate: 16 WALLSURFACE + 2 ROOFSURFACE, 60 expected source triangles, 40.007 × 27.484 m envelope, 6.674 m source height, center ~6.63 m from the locked Atomium anchor. Generic exact-head gates are green (tests, Game CI, Branch Hygiene, Web Export, Photo Match, Performance), but all three pavilion/hero-specific gates are red. Deterministic runtime fails before evidence upload with `AtomiumPavilionLoD2: source surface topology drifted` in `atomium_pavilion_lod2.gd:67`, then hero construction fails. Keep draft. Diagnose exact extraction/parser topology; do not hand-author repair geometry or relax source locks. If exact official topology cannot be reproduced deterministically, close without merge and pivot.
- **#267 Midi bilingual station identity** — `closed_without_merge`, `player_facing_zero_delta`. Source naming/address are factual and generic CI is green, but deterministic 1280×720 before/after is pixel-identical: `changed=0`, ratio `0.000000`. Closed by Director. Preserve naming evidence for a future station-frontage rebuild; do not inflate typography/contrast/camera to manufacture impact.
- **#269 Grand-Place Town Hall slate roof** — `closed_without_merge`, `source_disciplined_but_human_impact_rejected`. Corrected A/B measured 31,721 pixels >3 RGB = 3.4419%, but direct full-frame review found the material shift too subtle at normal distance. Preserve source/helper evidence; do not merge this presentation now.
- **#261 Ixelles next-identity discovery** — `closed_without_merge`, `evidence_preserved`. Discovery established three eligible in-cell strong-source buildings; prior selection favored Place Stéphanie 8 / building 1737880. Any runtime cue must be rebuilt as a fresh compact exact-current-main lot.
- **#231 shared STIB surface-stop vocabulary** — `closed_without_merge`, `asset_family_accepted_placement_unproven`. Reusable family was technically green and human-visually accepted, but no production stop + actual furniture subset was independently proven. Preserve evidence; future placement requires fresh official proof and a compact current-main rebuild.
- **#223 Midi blue-stone** — `source_disciplined`, `visual_impact_rejected`.
- **#222 Bourse vault proxy** — `source_truth_rejected`, `closed_without_merge`.
- Older Laeken trees/StreetSurface/esplanade/contaminated-height probes remain rejected; long-lived #2/#11 remain evidence/lab only and are never merge units.

## Active ownership map

- **Centre Vertical Slice** — no active runtime PR after Director closed #267. Next lot must be a large, source-bounded Grand-Place/Bourse/Midi correction with obvious normal-distance impact; no return to station-label, micro-frontage, paving-only or proxy-landmark loops.
- **Visual Assets + Atmosphere** — no active PR. #231 is closed evidence, not an active lot. Next shared lot must be fresh exact-current-main and combine unmistakable Brussels identity with defensible placement and meaningful screen area.
- **Ixelles Runtime Slice** — #239/#242/#258 are shipped. No active PR. Next cue must be a fresh compact current-main one-building/material/roofline or defensible street-context lot in the same cell; 460 unresolved-height buildings remain absent.
- **Laeken Hero Impact** — #268 is the sole active runtime owner and is currently blocked on exact-source topology reproduction before any visual acceptance.
- **Impact Director maintenance** — Traffic/Living City/missions/saves/release remain maintenance-only unless a blocking regression or unusually high perceived-impact defect appears.

## Current top 5 perceived-quality bottlenecks

1. **Grand-Place coherent detailed recognition** — `visual_gap_high_but_improving_fast`. Massing and Town Hall wall identity are materially better, but roofs/openings/secondary façades/paving/context still read simplified. Reject micro-material deltas that are only visible under crop.
2. **Bourse roof/interior volumes + immediate frontage** — `visual_gap_high`. Existing improvements are real, but simplified/incomplete structure remains obvious; no proxy pediment or invented landmark dimensions.
3. **Midi station/STIB/public-space identity** — `visual_gap_high`. #267 proved that a factual text cue can still have zero player impact; #231 proved a strong asset can still be placement-blocked. The next Midi gain must improve a real visible plane/space, not just add labels.
4. **Ixelles local identity density** — `identity_gap_medium_high`. Direct access and Stassart 124 are shipped; the same cell still needs another substantial source-backed cue rather than more infrastructure or micro-signage.
5. **Atomium immediate pavilion/site context** — `visual_gap_high`, `runtime_source_blocked`. #268 has a strong official LoD2 candidate but cannot proceed until exact topology is reproducible without authored repair.

## Stream health

- **Centre** — `available_but_needs_large_gain`: excellent shipped Grand-Place foundations, but current Midi label route was closed at zero delta. Next work must clear the anti-micro bar before PR.
- **Visual Assets + Atmosphere** — `available_after_stale_asset_closure`: #231 evidence is preserved but no shared lot is active. Favor unmistakable reusable identity with real placement truth.
- **Ixelles** — `productive_with_no_active_lot`: shipped runtime/access/frontage are healthy; next change should be one large local identity cue from fresh current main.
- **Laeken** — `high_source_potential_but_runtime_red`: #268 remains highest-potential specialist candidate only if its exact source topology contract can be repaired without inventing geometry.

## Shared priorities

1. **Resolve #268 exact-source topology** — if deterministic UrbIS3D pavilion geometry can be reproduced, regenerate hero + direct-player A/B and human-inspect. If not, close immediately; do not deepen evidence research.
2. **Grand-Place/Bourse large source-backed correction** — Centre should select a normal-distance silhouette/context/material cue substantially stronger than recent micro-lots.
3. **Ixelles second local identity cue** — fresh exact-current-main compact lot, same shipped cell, using strong source chain and meaningful direct-player screen area.
4. **Fresh shared Brussels identity cue** — exact placement truth + high reuse; do not revive #231 history without new official evidence.
5. Atmosphere/wet/night only after the selected witness has credible geometry and local identity.

## Production rules

1. Exact current `main` is the only production truth.
2. One active lot per exact problem/domain.
3. Small current-main PRs only; re-check `main` and active PRs immediately before push/PR/merge.
4. Publication-only commits are not new gameplay/visual truth.
5. Prefer Paradigm/UrbIS/UrbIS3D, Brussels Mobility, STIB and official orthophoto/DTM/DSM. OSM is complement, not proof for unresolved geometry/traffic semantics.
6. Preserve lawful provenance/licensing; never distribute reference imagery as textures without permission.
7. Evidence-only work is allowed only when it can unlock a material player-facing correction within one or two lots.
8. Green CI can still be rejected for negligible player impact or weak source truth.
9. Substantive lots require deterministic player-facing evidence, human inspection, relevant tests, branch hygiene and performance when applicable.
10. Pixel delta is evidence, not the objective. Judge recognition, silhouette, street proportions, material response, atmosphere, legibility, motion and gameplay feel.

## Director next-integration priority

**Highest-value conditional candidate remains #268 Atomium pavilion, but it is not integration-ready: exact-source topology currently fails in the dedicated runtime/hero gates. The next useful action is one bounded parser/extraction diagnosis on the same PR. If that exact official geometry becomes reproducible and the 1280×960 + 1280×720 A/B is clearly positive, #268 can return to the front of the queue. If not, close it and move priority immediately to a large Grand-Place/Bourse Centre correction rather than spending another cycle on pavilion evidence.**
