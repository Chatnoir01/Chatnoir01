# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This file is the player-facing priority backlog, not a completeness claim.

Current production checkpoint: `1653b9ceb79f11d14c417706c21afaddef18eaaf` (Direction-only merge). Latest substantive player-facing production parent remains `bc5bf8282597f7996b42f35b8c397ef2733b07e3`, merged PR #230; publication-only Web commit `6e77f41cf095f83a6b227448322ea31a3526ac94` sits below the Direction refresh.

## North star

For every zone ask: **if a real Brussels photo or observation is beside the game, what gives the game away in the first three seconds?**

Optimize three horizons:

1. **3 seconds** — silhouette, proportions, materials, unmistakable street/landmark identity, obvious placeholders.
2. **30 seconds** — street furniture, signage, transport vocabulary, motion, clutter, lighting and atmosphere.
3. **10 minutes** — playable continuity, believable traffic/PNJ behavior, missions/saves, navigation and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient. Source truth and human player-facing inspection are hard gates.

## Director gates — 2026-08-14

- **#236 official 2024 Atomium orthophoto drape**: `technically_green`, `high_impact_candidate`, `capture_required`, `keep_draft`. Exact-current-main head `d1471806...` is green on general tests, Game CI, Branch Hygiene, Web Export, Photo Match and Performance. Official Paradigm/Brussels-Capital Region 2024 RGB orthophoto, EPSG:31370 bbox `[147300,173650,149100,176750]`, is source-disciplined and CC0. Do not merge until a dedicated deterministic Atomium witness proves UV orientation, source-bound fallback seam, no z-fighting/float, and a clear player-facing gain.
- **#221 Ixelles first runtime micro-slice**: `targeted_visual_blocker_resolved`, `all_functional_gates_green`, `branch_hygiene_stale`, `rebuild_current_main`. Latest evidence head `2e1a9fab...` keeps exactly one cell `bxl-e149000-n169000-s500`, 309 StreetSurfaces, 277 StreetAxes, 260 strong-source-height buildings and 460 unresolved-height buildings absent. Drape diagnostics: 51,188 source/DTM intersections, 73,486 triangles, `outside_source=0`, `unsupported=0`, `min_clearance=+0.03485 m`. Human inspection reports the broad green DTM breakthrough removed; roadway now reads continuously. Do not merge the long-lived #221 history. Rebuild the accepted payload compactly from exact current `main`, reproduce the same capture, then integrate if all gates including Branch Hygiene are green.
- **#231 shared STIB surface-stop vocabulary**: `technically_green`, `human_visual_accepted`, `placement_source_blocked`, `keep_draft`. Reusable stop pole/timetable/bin/shelter/bench/info family is accepted; do not retune it. Hard blocker is a real production stop coordinate plus independently defensible evidence for which furniture is actually present there. Integrate only the proven subset.
- **#235 Bourse smart bins**: `source_disciplined`, `visual_impact_rejected`, `closed_without_merge`. Placement/source was defensible, but the witness still read as a generic small bin. Do not enlarge/recolor to manufacture identity impact.
- **#229 Bourse official frontage winding**: `technically_green`, `visual_impact_rejected`, `closed_without_merge`. Current-main rebuild preserved official UrbIS LoD2 geometry but human A/B found only ~0.054% of the 1280×960 witness materially changed. Do not reopen this exact micro-correction.
- **#223 Midi blue-stone material**: `source_disciplined`, `visual_impact_rejected`, `keep_draft`. Preserve for closer/source-confirmed reuse; do not retune for pixel delta.
- **#220 Atomium city trees**: `source_coverage_rejected`, `closed_without_merge`. Locked payload had zero valid hero/DTM intersection. Do not revive by weakening gates, flipping axes or fabricating trees.
- **#222 Bourse portico-vault proxy**: `capture_visible`, `source_truth_rejected`, `closed_without_merge`. Semantic existence was real but landmark dimensions were authored proxies; never production geometry.

## Latest shipped player-facing gains

- **#230 Atomium direct Web spawn** — improves discovery/testability and the 10-minute experience by making the shipped hero directly reachable in-browser.
- **#226 Atomium deterministic reflection environment** — improves stainless readability without changing geometry/topology/pose.
- **#217 Bourse white-stone portico** — stronger six-column separation/readability.
- **#215 Midi/Fonsny Fauquenberg brick** — replaces large flat façade response with source-scaled procedural brick/mortar.
- **#214 Atomium stainless presentation** — brighter metallic response and stronger tessellation while preserving source-bounded dimensions/topology.
- **#213 Bourse sidewalk boundary articulation** — improves official sidewalk edge readability without inventing curb height.

## Current top 5 perceived-quality bottlenecks

1. **Bourse roof/interior volumes + immediate surrounding frontage** — `visual_gap_high`. The hero still reads as prototype in the fixed witness. Recent face/material micro-lots were too weak; authored landmark proxies remain forbidden.
2. **Grand-Place arrival is visibly sparse/prototype** — `visual_gap_high`, `references_needed`. Architecture, roof silhouettes, paving, openings, signs, furniture and atmosphere remain far below the real place.
3. **Ixelles first micro-slice is visually improved but not yet production-clean** — `runtime_exists_on_pr`, `targeted_drape_resolved`, `current_main_rebuild_needed`. This is now the highest-confidence 10-minute expansion candidate.
4. **Midi lacks unmistakable STIB/station/public-space identity** — `visual_gap_high`. Fauquenberg brick is shipped; #231 proves shared STIB stop vocabulary can create a clear Brussels cue, but placement must be sourced.
5. **Atomium immediate site context/pavilion/supports remain incomplete** — `visual_gap_high`. Stainless, reflections and direct spawn are shipped. #236 is the strongest current context candidate but still lacks its own deterministic visual acceptance evidence.

## Active ownership map

- **Centre Vertical Slice** — owns Bourse/Centre/Midi visible geography. No high-impact Centre runtime PR is integration-ready. Next lot must be a clearly perceptible, source-bounded roof/interior/adjacent-frontage or Grand-Place/Midi correction; no more tiny face/material deltas.
- **Visual Assets + Atmosphere** — owns shared PBR/furniture/signage/vegetation/lighting/weather/audio. #231 owns STIB surface-stop vocabulary. Next step is stop/furniture placement evidence, not asset retuning. #235 is closed/rejected.
- **Ixelles Runtime Slice** — #221 remains evidence/implementation owner of one-cell micro-slice. The targeted drape blocker is resolved; next action is a compact exact-current-main replacement reproducing the accepted payload/capture. No new geography/assets/heights before that ships.
- **Laeken Hero Impact** — #236 owns the official orthophoto ground-context problem. Keep draft until dedicated hero/direct-player captures are generated and human-inspected. #214/#226/#230 remain shipped foundation.
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
- One immediate adjacent frontage with authoritative geometry/height/opening evidence and substantial screen area.
- Grand-Place deterministic arrival witness, then one coherent full-frame architecture/paving/signage correction rather than another isolated micro-detail.
- #165 remains unresolved pediment evidence: never invent dimensions to close it.

## Midi → Anneessens

### Shipped foundation

- Playable mission/checkpoint/save loop.
- Fauquenberg brick presentation on bounded Fonsny façade family.

### Highest-value next work

- **Authentic STIB stop identity**: #231 reusable family is visually accepted. Find an official STIB stop geolocation on the production slice and independently prove which furniture is present; integrate only the proven subset.
- Station frontage identity/entries and bilingual station/wayfinding elements.
- Forecourt/tram-bus interface geometry and markings only where source-backed.
- Retail frontage and ground-floor rhythm.
- One deterministic station/route camera showing a substantial before/after.

## Grand-Place / Centre arrival

- Gameplay arrival: `runtime_exists`.
- Visual credibility: `visual_gap_high`.
- Next useful lot: lock one deterministic arrival camera and make the whole foreground/midground coherent — façade rhythm, roof silhouette, paving, signs/furniture — before expanding gameplay geography.

## Ixelles

### Locked scope

- Cell `bxl-e149000-n169000-s500`, EPSG:31370 bbox `[149000,169000,149500,169500]` only.
- Validated 2 m DTM/source hashes; 63,001 terrain samples / 125,000 terrain triangles.
- 309 authoritative StreetSurfaces; 277 StreetAxes.
- 260 strong source-backed building heights.
- 460 unresolved-height buildings remain absent.
- Source-anchored Rue de Stassart → Place Stéphanie witness at 1.72 m eye height.

### Current proof

Latest evidence head `2e1a9fab...`: Runtime, Capture, Visible Micro-slice, Performance, Game CI, Photo Match, Web Export, Seed, Strong Heights and general tests are green. Branch Hygiene is red only because the long-lived #221 branch is stale. StreetSurface drape now intersects the exact source polygons with DTM triangles and resamples presentation vertices; human inspection reports the former broad green roadway breakthrough gone.

### Required next proof

1. Do not merge #221 history.
2. Rebuild the accepted one-cell runtime/drape/camera payload compactly from exact current `main`.
3. Preserve all source hashes, 260/460 building-height policy, camera anchors and renderer-only 0.035 m drape bias.
4. Re-run Branch Hygiene + Runtime + Capture + Visible Micro-slice + Performance + Game CI + Photo Match.
5. Human A/B must reproduce the same continuous-roadway result before integration.

No new geography, broad height research, furniture or façade work before this ships.

## Laeken / Atomium

### Shipped foundation

- Official DTM with collision/normals.
- 9-sphere / 20-tube source-bounded core, 102 m / 18 m / 3.30 m.
- Stainless presentation (#214).
- Deterministic reflection environment (#226).
- Direct browser hero entry `?spawn=atomium` (#230).
- 26 m circular pavilion-plan evidence.

### Active candidate — #236

Official 2024 RGB orthophoto drape over the already-valid Atomium DTM can replace the flat green ground context with lawns/paths/roads already present in the source image, without inventing geometry or vegetation. Generic CI is green, but no dedicated deterministic orthophoto witness has yet proven UV orientation, seam/fallback quality or player-facing benefit. Keep draft until that capture exists and is human-accepted.

### Highest-value remaining work

- #236 dedicated hero/direct-player evidence and human A/B.
- Pavilion details only where dimensions/semantics are actually established.
- Immediate public-realm/context geometry already present in authoritative data.
- Exact global crystal yaw and three bipod feet remain `references_needed`; support geometry stays blocked.

## Shared asset priorities

1. **#231 authentic STIB production placement** — strongest current shared candidate because the family is reusable, visually obvious and technically green. Hard blocker: real stop coordinate + actual furniture presence.
2. Bilingual street-name/wayfinding elements with source-defensible placement.
3. Shopfront/window/awning modules demonstrated in a current production witness.
4. Bollards, barriers, bins, benches, bike racks and utility cabinets where placement is defensible and the combined scene identity is meaningful; do not repeat #235 as a standalone micro-win.
5. Large foreground paving/cobble/asphalt families only when source-confirmed coverage occupies a substantial witness footprint.
6. Controlled overcast/wet/night atmosphere after major geometry/street-identity blockers are under control.

## Production rules

1. Exact current `main` is the only production truth.
2. One active lot per exact problem/domain.
3. Small current-main PRs only; re-check `main` and active PRs immediately before push/PR/merge.
4. Publication-only commits are not new gameplay/visual truth.
5. Prefer Paradigm/UrbIS/UrbIS3D, Brussels Mobility, STIB and official orthophoto/DTM/DSM. OSM is complement, not proof for unresolved geometry/traffic semantics.
6. Preserve lawful provenance/licensing; never distribute reference imagery as textures without permission.
7. Evidence-only work is allowed only if it can unlock a material player-facing correction within one or two lots.
8. Green CI can still be rejected for negligible player impact or weak source truth.
9. Substantive lots require deterministic player-facing evidence, human inspection, relevant tests, Branch Hygiene and Performance when applicable.
10. Pixel delta is evidence, not the objective. Judge recognition, silhouette, street proportions, material response, atmosphere, legibility, motion and gameplay feel.

## Definition of a convincing micro-slice

A bounded slice is not visually convincing until hero/major silhouettes are recognisable, street/ground proportions are defensible, immediate façades are not generic placeholders, key signage/furniture/transport vocabulary is present, materials read at believable scale, deterministic cameras have been compared against references, no huge prototype giveaway survives the first three seconds, and performance remains acceptable.

## Director next-integration priority

**Highest-confidence next integration candidate: a compact exact-current-main replacement of the accepted #221 Ixelles one-cell runtime/drape payload.** The player-facing blocker is already visually resolved and all functional exact-head gates are green; only the stale branch history prevents production integration. Rebuild without feature expansion and reproduce the deterministic capture.

**Highest-upside secondary candidate: #236 official Atomium orthophoto**, but only after a dedicated deterministic hero/direct-player capture proves UV/seam correctness and a clear visual gain.

#231 STIB remains the strongest shared-asset candidate once real stop/furniture placement truth is established.