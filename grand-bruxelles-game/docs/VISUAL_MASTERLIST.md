# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This file is the player-facing priority backlog, not a completeness claim.

Current production checkpoint: `5c306cdae9fe5439bd3bd87796ae1730cf0aefc7` (publication-only Web commit). Latest substantive production parent: `15bf915c5b18394bbd0766b365ffac77f1d23b62`, merged PR #243.

## North star

Ask at every zone: **if a real Brussels photo or observation is beside the game, what gives the game away in the first three seconds?**

Optimize three horizons:

1. **3 seconds** — silhouette, proportions, materials, landmark/street identity, obvious placeholders.
2. **30 seconds** — signage, transport vocabulary, furniture, motion, clutter, lighting and atmosphere.
3. **10 minutes** — playable continuity, navigation, believable traffic/PNJ behavior, missions/saves and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient. Source truth and direct player-facing inspection are hard gates.

## Director gates — 2026-08-14

- **#243 bilingual Brussels street-name plaque**: `shipped`, `shared_identity_gain`. Reusable authored FR/NL plaque family is in production after deterministic Bourse witness and human visual acceptance. The factual pair `RUE DE LA BOURSE / BEURSSTRAAT` is source-backed; panel geometry/color/type/PBR remain authored presentation values. Permanent surveyed placement is still a separate source-truth question.
- **#242 direct Ixelles player/Web entry**: `shipped`, `player_access_gain`. `?spawn=ixelles` mounts the already-shipped one-cell micro-slice and anchors the player on the accepted Rue de Stassart -> Place Stephanie source witness with the 260/460 no-invention height contract intact.
- **#241 Bourse official roof winding**: `shipped`, `source_preserving_roof_gain`. Existing UrbIS3D `ROOFSURFACE` vertices/triangles are preserved while exterior roof winding is normalized upward for deterministic culling. This improves the high-impact roof/interior layer without authored landmark dimensions; Bourse remains incomplete.
- **#239 Ixelles compact visible micro-slice**: `shipped`, `runtime_foundation_gain`. One cell only: `bxl-e149000-n169000-s500`, 2 m DTM, 309 StreetSurfaces, 277 StreetAxes, 260 strong-source-height buildings, 460 unresolved-height buildings absent.
- **#244 Atomium StreetSurface context**: `source_disciplined`, `visual_impact_rejected`, `closed_without_merge`. 84 official source features produced only sparse dark slivers in the hero witness (~0.0417% pixels >5 RGB). Preserve extraction evidence; do not inflate material/coverage to manufacture impact.
- **#231 shared STIB surface-stop vocabulary**: `technically_green`, `human_visual_accepted`, `placement_source_blocked`, `keep_draft`. Reusable family is accepted; production placement still needs an official stop anchor and independent evidence for the furniture actually present there.
- **#223 Midi blue-stone material**: `source_disciplined`, `visual_impact_rejected`, `keep_draft`. Preserve for closer/source-confirmed reuse; do not retune merely to increase pixel delta.
- **#220 Atomium trees**: `source_coverage_rejected`, `closed_without_merge`. Do not revive by weakening gates or fabricating placement.
- **#222 Bourse vault proxy**: `source_truth_rejected`, `closed_without_merge`. Visually stronger but depended on authored landmark dimensions; not production geometry.

## Latest shipped player-facing gains

- **#243 bilingual Brussels street-name plaque** — immediately increases Brussels street-language identity and is reusable across source-confirmed placements.
- **#242 direct Ixelles Web/player spawn** — converts the shipped Ixelles foundation into a destination the player can directly inspect.
- **#241 Bourse roof winding normalization** — source-preserving improvement on the hero roof/interior layer.
- **#239 Ixelles compact runtime micro-slice** — first clean production runtime foundation for a real bounded Ixelles cell.
- **#230 Atomium direct Web spawn** — landmark becomes immediately reachable/testable.
- **#226 Atomium deterministic reflection environment** — stronger stainless response without geometry changes.
- **#217 Bourse white-stone portico** — stronger six-column separation/readability.
- **#215 Midi/Fonsny Fauquenberg brick** — source-scaled procedural brick replaces a large flat façade response.
- **#214 Atomium stainless presentation** — brighter metallic response and stronger presentation tessellation.

## Current top 5 perceived-quality bottlenecks

1. **Grand-Place arrival is visibly sparse/prototype** — `visual_gap_high`, `references_needed`. It is now the strongest unowned full-frame opportunity: architecture, roof silhouettes, paving, frontage rhythm, bilingual signs/furniture and atmosphere remain far below the real place.
2. **Bourse roof/interior volumes + immediate surrounding frontage** — `visual_gap_high`. #241 improves the authoritative roof layer, but the fixed hero witness still exposes simplified/incomplete interior/roof/frontage structure. No proxy pediment or authored landmark dimensions.
3. **Midi lacks unmistakable STIB/station/public-space identity** — `visual_gap_high`. #215 brick is shipped and #231 proves a strong reusable transit cue, but real stop/furniture placement truth is still unresolved.
4. **Ixelles is directly playable but visually generic beyond terrain/streets/massing** — `player_access_shipped`, `identity_gap_high`. Next lot should add exactly one source-backed, high-impact local identity cue in the existing cell/player view; no new geography or unresolved heights.
5. **Atomium immediate context/pavilion/supports remain incomplete** — `visual_gap_high`. Stainless, reflections and direct spawn are shipped; #244 proved generic StreetSurface context is too weak. Exact support/yaw facts remain blocked and must not be fabricated.

## Active ownership map

- **Centre Vertical Slice** — owns Bourse/Centre/Midi visible geography. #241 is shipped. Next substantive lot should target Grand-Place arrival or another clearly large source-bounded Bourse/Midi giveaway; no return to imperceptible frontage micro-lots.
- **Visual Assets + Atmosphere** — owns shared PBR/furniture/signage/vegetation/lighting/weather/audio. #243 is shipped. #231 still owns the accepted STIB stop family; next step is placement/furniture source truth, not styling.
- **Ixelles Runtime Slice** — #239 and #242 are shipped. Next lot stays in the same cell and adds one player-visible source-backed identity cue only; no terrain research, extra cells or 460 unresolved buildings.
- **Laeken Hero Impact** — #230/#226/#214 are shipped. #244 is rejected. Next hero lot must be current-main and source-bounded, preferably pavilion/public-realm/context with meaningful screen area.
- **Impact Director maintenance** — Traffic/Living City/missions/saves/release only for blockers/regressions or unusually high perceived-impact opportunities.

## Centre / Bourse / Grand-Place

### Bourse foundations

- UrbIS3D hero mass and six-column portico.
- Fixed geotagged 1280×960 witness.
- Official StreetSurfaces and bounded sidewalk geometry.
- Visually accepted white-stone portico.
- Source-bounded sidewalk articulation.
- Source-preserving upward roof-surface winding (#241).

### Highest-value next work

- Existing authoritative roof/interior surfaces or measurable envelope constraints that remove obvious prototype read behind the portico.
- A frontage/context correction with materially large screen area, not another ~0.05% micro-delta.
- **Grand-Place deterministic arrival witness + one coherent full-frame correction** is now a preferred pivot when Bourse source facts stall.
- #165 pediment remains unresolved; never invent dimensions.

## Midi → Anneessens

### Shipped foundation

- Playable mission/checkpoint/save loop.
- Fauquenberg brick presentation on bounded Fonsny façade family.

### Highest-value next work

- **Authentic STIB stop identity**: #231 family is visually accepted. Pair an official production stop geolocation with independent evidence of the actual furniture present there; integrate only the proven subset.
- Station frontage identity/entries and bilingual wayfinding.
- Forecourt/tram-bus interface geometry/markings only where source-backed.
- Retail frontage and ground-floor rhythm.

## Grand-Place / Centre arrival

- Gameplay arrival exists.
- Visual credibility remains `visual_gap_high` and is now the strongest clean full-frame opportunity.
- Next useful lot: lock a deterministic production arrival camera, then improve one coherent source-backed foreground/midground giveaway — massing/frontage/paving/signage — rather than another isolated micro-detail.

## Ixelles

### Shipped scope — #239 + #242

- Cell `bxl-e149000-n169000-s500`, EPSG:31370 bbox `[149000,169000,149500,169500]` only.
- Locked 2 m DTM/source hashes; 63,001 terrain samples / 125,000 terrain triangles.
- 309 authoritative StreetSurfaces and 277 StreetAxes.
- 260 strong source-backed building heights; 460 unresolved-height buildings absent.
- Source-anchored Rue de Stassart axis `71374:1` → Place Stephanie axis `71306:2`.
- Accepted one-cell roadway drape and direct player/Web entry `?spawn=ixelles`.

### Highest-value next work

1. Human-judge the direct player view as the baseline for all future Ixelles visual work.
2. Add exactly one high-impact identity cue with defensible source support: immediate frontage/material/vegetation/street context.
3. Require a 1280×720 player before/after; reject if impact requires A/B magnification.
4. Keep geography, DTM, camera anchor and 260/460 height policy unchanged.

## Laeken / Atomium

### Shipped foundation

- Official DTM with collision/normals.
- 9-sphere / 20-tube source-bounded core, 102 m / 18 m / 3.30 m.
- Stainless presentation (#214).
- Deterministic reflection environment (#226).
- Direct browser hero entry `?spawn=atomium` (#230).
- 26 m circular pavilion-plan evidence.

### Highest-value remaining work

- Pavilion details only where actual dimensions/semantics are established.
- Immediate public-realm/context geometry or imagery only when it occupies meaningful hero/player screen area and has dedicated A/B evidence.
- Exact global crystal yaw and three bipod feet remain `references_needed`; support geometry stays blocked.
- Do not revive #220 or #244 unchanged.

## Shared asset priorities

1. **#231 authentic STIB production placement** — highest-value ready family if stop coordinate + actual furniture presence can be proven quickly.
2. **Bilingual street-name/wayfinding placement** — #243 family is shipped; future placements require factual name + defensible scene anchor.
3. Shopfront/window/awning modules demonstrated in a current production witness.
4. Brussels/STIB/public-space furniture where official/reference placement is defensible and visually unmistakable.
5. Larger foreground paving/cobble/asphalt families only when source-confirmed coverage occupies substantial screen area.
6. Controlled overcast/wet/night atmosphere after major geometry/street-identity blockers in the chosen witness are under control.

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

**Highest-value current candidate: #231 STIB surface-stop vocabulary, but only after a real production stop anchor and actual furniture-presence proof are paired.** If that source truth cannot be closed within one or two lots, defer #231 and pivot to the new clean opportunity: a deterministic Grand-Place arrival witness followed by one coherent source-backed full-frame correction. Ixelles is now a shipped/player-accessible baseline, so it no longer blocks integration; its next work is quality, not infrastructure.