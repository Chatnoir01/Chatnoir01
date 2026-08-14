# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This file is the player-facing priority backlog, not a completeness claim.

Current production checkpoint: `6e77f41cf095f83a6b227448322ea31a3526ac94` (publication-only Web commit). Substantive production parent: `bc5bf8282597f7996b42f35b8c397ef2733b07e3`, merged PR #230.

## North star

For every zone ask: **if a real Brussels photo or observation is beside the game, what gives the game away in the first three seconds?**

Optimize three horizons:

1. **3 seconds** — silhouette, proportions, materials, unmistakable street/landmark identity, obvious placeholders.
2. **30 seconds** — street furniture, signage, transport vocabulary, motion, clutter, lighting and atmosphere.
3. **10 minutes** — playable continuity, believable traffic/PNJ behavior, missions/saves, navigation and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. A green technical check is necessary but never sufficient. Source truth and human player-facing inspection are hard gates.

## Director gates — 2026-08-14

- **#230 direct Atomium Web spawn**: `shipped`, `player_access_gain`. `?spawn=atomium` now opens the already-shipped official Atomium DTM + stainless hero + deterministic reflection environment from a presentation-only visitor viewpoint. No Atomium geometry or pose fact was invented.
- **#229 Bourse official frontage winding**: `technically_green`, `visual_impact_rejected`, `closed_without_merge`. Current-main rebuild preserved official UrbIS LoD2 geometry and fixed face winding, but human A/B found only ~663 pixels above a 3-RGB delta in the 1280×960 witness (~0.054%). Do not reopen this exact micro-correction. Centre must target a larger source-bounded roof/interior/frontage giveaway.
- **#221 Ixelles first runtime micro-slice**: `keep_draft`, `latest_head_regressed`. Scope remains exactly one cell `bxl-e149000-n169000-s500`, 309 StreetSurfaces, 277 StreetAxes and 260 strong-source-height buildings; 460 unresolved-height buildings remain absent. Latest head `6c94b3dd...` currently fails Branch Hygiene, Micro-slice Runtime and Capture, while general tests, Game CI, Photo Match, Web Export, Performance, Seed and Strong Height gates are green. Do not merge. Fix the same-cell StreetSurface drape/tessellation/runtime regression before any new geography/assets.
- **#231 shared STIB surface-stop vocabulary**: `technically_green`, `human_visual_accepted`, `placement_source_blocked`, `keep_draft`. Exact-current-main reusable stop pole/timetable/bin/shelter/bench/info family passes dedicated visual, tests, Game CI, Branch Hygiene, Web Export, Photo Match and Performance. Human witness is clearly readable without A/B. However its current Midi witness placement is presentation-only: no independently defensible production stop coordinate + actual shelter presence has been anchored yet. Do not fabricate placement. This is the highest-value near-term shared integration candidate once an official STIB stop anchor and furniture-presence proof are paired.
- **#223 Midi blue-stone material**: `source_disciplined`, `visual_impact_rejected`, `keep_draft`. Preserve for closer/source-confirmed reuse; do not retune merely to manufacture pixel delta.
- **#220 Atomium city trees**: `source_coverage_rejected`, `closed_without_merge`. Locked payload had zero valid hero/DTM intersection. Do not revive by weakening gates, flipping axes or fabricating trees.
- **#222 Bourse portico-vault proxy**: `capture_visible`, `source_truth_rejected`, `closed_without_merge`. Semantics were real but landmark dimensions were authored proxies; not production geometry.

## Latest shipped player-facing gains

- **#230 Atomium direct Web spawn** — improves discovery/testability and the 10-minute experience by making the shipped hero directly reachable in-browser.
- **#226 Atomium deterministic reflection environment** — improves stainless readability without changing geometry/topology/pose.
- **#217 Bourse white-stone portico** — stronger six-column separation/readability.
- **#215 Midi/Fonsny Fauquenberg brick** — replaces large flat façade response with source-scaled procedural brick/mortar.
- **#214 Atomium stainless presentation** — brighter metallic response and stronger tessellation while preserving source-bounded dimensions/topology.
- **#213 Bourse sidewalk boundary articulation** — improves official sidewalk edge readability without inventing curb height.

## Current top 5 perceived-quality bottlenecks

1. **Bourse roof/interior volumes + immediate surrounding frontage** — `visual_gap_high`. The hero still reads as prototype in the fixed geotagged witness. #229 proved face-winding is too small a lever; authored landmark proxies remain forbidden.
2. **Grand-Place arrival is visibly sparse/prototype** — `visual_gap_high`, `references_needed`. Architecture, roof silhouettes, paving, openings, signs, furniture and atmosphere remain far below the real place.
3. **Ixelles first micro-slice is not integration-ready** — `runtime_exists_on_pr`, `visual_gap_high`, `ci_regression`. Same-cell runtime is valuable, but latest #221 head is red on runtime/capture/hygiene and must be stabilized before it can become the first credible new playable area.
4. **Midi lacks unmistakable STIB/station/public-space identity** — `visual_gap_high`. Fauquenberg brick is shipped; #231 now proves that shared STIB stop vocabulary can create a clear Brussels cue, but real placement must be anchored before production integration.
5. **Atomium immediate site context/pavilion/supports remain incomplete** — `visual_gap_high`. Stainless, reflections and direct spawn are shipped, but exact yaw/support feet and detailed pavilion/context remain unresolved; do not fabricate them.

## Active ownership map

- **Centre Vertical Slice** — owns Bourse/Centre/Midi visible geography. No current high-impact Bourse runtime PR is integration-ready after #229 rejection. Next lot must be a clearly perceptible, source-bounded roof/interior/adjacent-frontage or Grand-Place/Midi correction; no more tiny face/material deltas.
- **Visual Assets + Atmosphere** — owns shared PBR/furniture/signage/vegetation/lighting/weather/audio. #231 owns STIB surface-stop vocabulary. Its next step is evidence for a real production stop coordinate and the actual furniture present there, not asset retuning or invented placement.
- **Ixelles Runtime Slice** — #221 owns the one-cell runtime micro-slice. Do not create competing Ixelles lots or broaden geography. Fix current runtime/capture/hygiene failures and StreetSurface drape/tessellation on the same cell.
- **Laeken Hero Impact** — #230 is shipped on top of #214/#226. Next work should be source-bounded pavilion/public-realm/context inside validated terrain, not more stainless/reflection polish and not unresolved support geometry.
- **Impact Director maintenance** — Traffic/Living City/missions/saves/release only for regressions, blockers or unusually high perceived-impact opportunities. None currently outranks the four visual streams.

## Bourse / Centre

### Production foundations

- UrbIS3D hero mass and six-column portico.
- Fixed geotagged 1280×960 witness.
- Official StreetSurfaces and bounded sidewalk geometry.
- Visually accepted white-stone portico.
- Source-bounded sidewalk articulation.

### Highest-value next work

- Existing authoritative roof/interior surfaces or measurable envelope constraints that remove the obvious broken/prototype read behind the portico.
- One immediate adjacent frontage with authoritative geometry/height/opening evidence and a substantial footprint in the witness.
- Grand-Place deterministic arrival witness, followed by one coherent full-frame architecture/paving/signage pass rather than another isolated micro-detail.
- Street furniture/signage only when placement is source-defensible and occupies meaningful visual area.
- #165 remains unresolved pediment evidence: never invent dimensions to close it.

## Midi → Anneessens

### Shipped foundation

- Playable mission/checkpoint/save loop.
- Fauquenberg brick presentation on bounded Fonsny façade family.

### Highest-value next work

- **Authentic STIB stop identity**: #231 reusable family is visually accepted. Find an official STIB stop geolocation on the production slice and independently prove which furniture is present (pole-only vs shelter etc.); then integrate only the proven subset.
- Station frontage identity/entries and bilingual station/wayfinding elements.
- Forecourt/tram-bus interface geometry and markings only where source-backed.
- Retail frontage and ground-floor rhythm.
- One deterministic station/route camera showing a substantial before/after.

## Grand-Place / Centre arrival

- Gameplay arrival: `runtime_exists`.
- Visual credibility: `visual_gap_high`.
- Next useful lot: lock one deterministic arrival camera and make the whole foreground/midground coherent — façade rhythm, roof silhouette, paving, signs/furniture — before expanding gameplay geography.

## Ixelles

### Locked scope on #221

- Cell `bxl-e149000-n169000-s500`, EPSG:31370 bbox `[149000,169000,149500,169500]` only.
- Validated 2 m DTM/source hashes.
- 309 authoritative StreetSurfaces.
- 277 StreetAxes.
- 260 strong source-backed building heights.
- 460 unresolved-height buildings remain absent.
- Source-anchored Rue de Stassart → Place Stéphanie witness at pedestrian eye height.

### Current blocker

Latest head `6c94b3dd...` is **not green**: Branch Hygiene, Micro-slice Runtime and Capture fail. Import succeeds; the runtime validation step itself fails. This supersedes earlier green intermediate heads. Do not claim #221 ready.

### Required next proof

1. Stay on the exact same cell/source hashes/camera/height policy.
2. Reproduce and fix the current runtime validation failure first.
3. Complete the bounded StreetSurface densification/drape so official street polygons remain visually above the DTM in the near-field corridor without claiming physical road height.
4. Restore Branch Hygiene + Runtime + Capture + Visible Micro-slice green alongside existing tests/Game CI/Photo Match/Performance.
5. Human-inspect the 1280×960 capture. Road/street surfaces and urban masses must dominate; no green prototype terrain bleed.

No new geography, broad height research, furniture or façade work before this passes.

## Laeken / Atomium

### Shipped foundation

- Official DTM with collision/normals.
- 9-sphere / 20-tube source-bounded core, 102 m / 18 m / 3.30 m.
- Stainless presentation (#214).
- Deterministic reflection environment (#226).
- Direct browser hero entry `?spawn=atomium` (#230), using a presentation-only visitor viewpoint inside the validated DTM tile.
- 26 m circular pavilion-plan evidence.

### Highest-value remaining work

- Pavilion details only where dimensions/semantics are actually established.
- Immediate public-realm/context geometry already present in authoritative data.
- Exact global crystal yaw and three bipod feet remain `references_needed`; support geometry stays blocked.
- Do not revive #220 tree extraction unchanged.

## Shared asset priorities

1. **#231 authentic STIB production placement** — strongest current shared candidate because the family is reusable, visually obvious and technically green. Hard blocker: real stop coordinate + actual furniture presence.
2. Bilingual street-name/wayfinding elements with source-defensible placement.
3. Shopfront/window/awning modules demonstrated in a current production witness.
4. Bollards, barriers, bins, benches, bike racks and utility cabinets where official/reference placement is defensible.
5. Large foreground paving/cobble/asphalt families only when source-confirmed coverage occupies a substantial witness footprint.
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

## Definition of a convincing micro-slice

A bounded slice is not visually convincing until hero/major silhouettes are recognisable, street/ground proportions are defensible, immediate façades are not generic placeholders, key signage/furniture/transport vocabulary is present, materials read at believable scale, deterministic cameras have been compared against references, no huge prototype giveaway survives the first three seconds, and performance remains acceptable.

## Director next-integration priority

**Highest-value near-term candidate: #231 STIB surface-stop vocabulary, but only after the specialist pairs it with an official production stop coordinate and evidence for the actual furniture present at that stop.** If that source anchor cannot be obtained within the next one or two lots, defer it rather than accumulate research and move to the next high-impact visible candidate. #221 Ixelles remains the larger 10-minute milestone but is currently blocked by exact-head runtime/capture/hygiene failures.