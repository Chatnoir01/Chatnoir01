# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This file is the player-facing priority backlog, not a completeness claim.

Current production checkpoint: `c7796074fb50fe5578defad1b74b47fd997443f9` (publication-only Web commit). Substantive production parent: `e777e3ec2e3e0e709a897b65315ce13c9027872a`, merged PR #239.

## North star

Ask at every zone: **if a real Brussels photo or observation is beside the game, what gives the game away in the first three seconds?**

Optimize three horizons:

1. **3 seconds** — silhouette, proportions, materials, landmark/street identity, obvious placeholders.
2. **30 seconds** — signage, transport vocabulary, furniture, motion, clutter, lighting and atmosphere.
3. **10 minutes** — playable continuity, navigation, believable traffic/PNJ behavior, missions/saves and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient. Source truth and direct player-facing inspection are hard gates.

## Director gates — 2026-08-14

- **#239 Ixelles compact visible micro-slice**: `shipped`, `runtime_foundation_gain`. Exact-current-main replacement of long-lived #221 is now production truth. One cell only: `bxl-e149000-n169000-s500`, 2 m DTM, 309 StreetSurfaces, 277 StreetAxes, 260 strong-source-height buildings, 460 unresolved-height buildings absent. StreetSurface/DTM drape is visually accepted for the targeted bleed-through blocker. Next lot is direct player/Web access only; no new geography/assets.
- **#221 Ixelles long-lived micro-slice**: `superseded`, `closed_without_merge`. Evidence/history only; never reopen or merge its history.
- **#238 Bourse frontage 1645621**: `source_disciplined`, `visual_impact_rejected`, `closed_without_merge`. Human A/B found only ~665 pixels above an 8-RGB delta in the 1280×960 witness (~0.0541%). Preserve LoD2 evidence; do not inflate contrast/scale or invent openings to manufacture impact.
- **#231 shared STIB surface-stop vocabulary**: `technically_green`, `human_visual_accepted`, `placement_source_blocked`, `keep_draft`. Asset family is accepted; production placement still needs an official stop anchor and independent evidence of the furniture actually present there.
- **#236 Atomium 2024 orthophoto**: `closed_without_merge`. Source-bounded concept remains potentially valuable, but this exact PR is not production truth. Any retry must be current-main, dedicated-capture driven and visibly accepted.
- **#223 Midi blue-stone material**: `source_disciplined`, `visual_impact_rejected`, `keep_draft`. Preserve for closer/source-confirmed reuse; do not retune simply to increase pixel delta.
- **#230 direct Atomium Web spawn**: `shipped`, `player_access_gain`. `?spawn=atomium` opens the shipped official DTM + stainless hero + deterministic reflection environment without inventing landmark geometry.
- **#220 Atomium trees**: `source_coverage_rejected`, `closed_without_merge`. Do not revive by weakening gates or fabricating placement.
- **#222 Bourse vault proxy**: `source_truth_rejected`, `closed_without_merge`. Visually stronger but relied on authored landmark dimensions; not production geometry.

## Latest shipped player-facing gains

- **#239 Ixelles compact runtime micro-slice** — first clean production runtime foundation for a real bounded Ixelles cell; next step is direct player access.
- **#230 Atomium direct Web spawn** — landmark becomes immediately reachable/testable.
- **#226 Atomium deterministic reflection environment** — stronger stainless response without geometry changes.
- **#217 Bourse white-stone portico** — stronger six-column separation/readability.
- **#215 Midi/Fonsny Fauquenberg brick** — source-scaled procedural brick replaces a large flat façade response.
- **#214 Atomium stainless presentation** — brighter metallic response and stronger presentation tessellation.

## Current top 5 perceived-quality bottlenecks

1. **Bourse roof/interior volumes + immediate surrounding frontage** — `visual_gap_high`. Recent micro-frontage lots #229/#238 proved too small a lever. Next Centre lot must affect a materially larger silhouette/area without proxy landmark dimensions.
2. **Grand-Place arrival is visibly sparse/prototype** — `visual_gap_high`, `references_needed`. Architecture, roof silhouettes, paving, openings, signs, furniture and atmosphere remain far below the real place.
3. **Ixelles is in production but not yet directly player-accessible** — `runtime_foundation_shipped`, `player_access_missing`. #239 solved the bounded runtime/road drape foundation; next highest-value step is `?spawn=ixelles` or equivalent production-player entry with deterministic 1280×720 evidence.
4. **Midi lacks unmistakable STIB/station/public-space identity** — `visual_gap_high`. #215 brick is shipped and #231 proves a strong reusable transit cue, but stop/furniture placement truth is still unresolved.
5. **Atomium immediate context/pavilion/supports remain incomplete** — `visual_gap_high`. Stainless, reflections and direct spawn are shipped; exact support/yaw facts remain blocked and context needs another source-bounded approach.

## Active ownership map

- **Centre Vertical Slice** — Bourse/Centre/Midi visible geography. #238 is closed for negligible impact. Next lot must be a clearly perceptible source-bounded roof/interior/context, Grand-Place arrival, or Midi frontage/forecourt correction.
- **Visual Assets + Atmosphere** — shared PBR/furniture/signage/vegetation/lighting/weather/audio. #231 owns STIB surface-stop vocabulary; next step is placement/furniture source truth, not asset retuning.
- **Ixelles Runtime Slice** — #239 is shipped. Next lot owns direct player/Web access to the exact same cell; no new geometry/content until that access is shipped and inspected.
- **Laeken Hero Impact** — #230/#226/#214 are shipped. #236 is closed. Next hero lot must be current-main and source-bounded, preferably pavilion/public-realm/context that fits validated terrain.
- **Impact Director maintenance** — Traffic/Living City/missions/saves/release only for blockers/regressions or unusually high perceived-impact opportunities.

## Bourse / Centre

### Production foundations

- UrbIS3D hero mass and six-column portico.
- Fixed geotagged 1280×960 witness.
- Official StreetSurfaces and bounded sidewalk geometry.
- Visually accepted white-stone portico.
- Source-bounded sidewalk articulation.

### Highest-value next work

- Existing authoritative roof/interior surfaces or measurable envelope constraints that remove the obvious prototype read behind the portico.
- A frontage/context correction with materially larger screen area than #238.
- Establish/lock a deterministic Grand-Place arrival witness and improve one coherent architecture/paving/signage giveaway there.
- Midi station frontage/entry/forecourt/wayfinding only when source-backed and clearly visible.
- #165 pediment remains unresolved; never invent dimensions.

## Midi → Anneessens

### Shipped foundation

- Playable mission/checkpoint/save loop.
- Fauquenberg brick presentation on bounded Fonsny façade family.

### Highest-value next work

- **Authentic STIB stop identity**: #231 family is visually accepted. Find an official production stop geolocation and independently prove which furniture exists there; integrate only the proven subset.
- Station frontage identity/entries and bilingual wayfinding.
- Forecourt/tram-bus interface geometry/markings only where source-backed.
- Retail frontage and ground-floor rhythm.

## Grand-Place / Centre arrival

- Gameplay arrival exists.
- Visual credibility remains `visual_gap_high`.
- Next useful lot: one deterministic arrival camera plus one coherent full-frame correction — massing/paving/frontage/signage — rather than another micro-detail.

## Ixelles

### Shipped scope — #239

- Cell `bxl-e149000-n169000-s500`, EPSG:31370 bbox `[149000,169000,149500,169500]` only.
- Locked 2 m DTM/source hashes; 63,001 terrain samples / 125,000 terrain triangles.
- 309 authoritative StreetSurfaces and 277 StreetAxes.
- 260 strong source-backed building heights; 460 unresolved-height buildings absent.
- Source-anchored Rue de Stassart axis `71374:1` → Place Stéphanie axis `71306:2`, eye height 1.72 m.
- Renderer-only StreetSurface drape bias 0.035 m; no physical road-height claim.
- Accepted drape diagnostics: 51,188 source/DTM intersections, 73,486 drape triangles, outside_source=0, unsupported=0, min_clearance ≈ +0.03485 m.

### Next proof

1. Add a compact exact-current-main direct player/Web entry to the shipped slice; reuse existing runtime scripts/data.
2. Produce deterministic 1280×720 production-player evidence with safe terrain clearance and clear location label.
3. Human-inspect the direct player view.
4. Only after direct access ships, add one source-backed high-impact identity cue at a time on the same cell.

No terrain research, new cells, heuristic-height promotion or broad asset expansion before direct access is shipped.

## Laeken / Atomium

### Shipped foundation

- Official DTM with collision/normals.
- 9-sphere / 20-tube source-bounded core, 102 m / 18 m / 3.30 m.
- Stainless presentation (#214).
- Deterministic reflections (#226).
- Direct browser entry `?spawn=atomium` (#230).
- 26 m circular pavilion-plan evidence.

### Highest-value remaining work

- Pavilion details only where dimensions/semantics are established.
- Immediate public-realm/context geometry already available in authoritative data.
- Any orthophoto/context retry must be exact-current-main with dedicated deterministic hero/player capture and human approval.
- Exact global yaw and bipod feet remain `references_needed`; do not fabricate.

## Shared asset priorities

1. **#231 authentic STIB production placement** — strongest shared candidate once real stop coordinate + actual furniture presence are proven.
2. Bilingual street/wayfinding elements with source-defensible placement.
3. Shopfront/window/awning modules demonstrated in a production witness.
4. Street furniture where placement is defensible and screen presence is meaningful.
5. Larger foreground paving/cobble/asphalt only when source-confirmed coverage occupies substantial witness area.
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
9. Substantive lots require deterministic player-facing evidence, human inspection, relevant tests, branch hygiene and performance when applicable.
10. Pixel delta is evidence, not the objective.

## Director next-integration priority

**Highest-value near-term candidate: direct player/Web access to the shipped #239 Ixelles micro-slice.** It converts a technically credible runtime foundation into a real 10-minute player-facing destination at low cost and low source risk. Parallel shared candidate #231 remains blocked on stop/furniture placement truth; Centre must produce a substantially larger visual gain than #238 before integration.