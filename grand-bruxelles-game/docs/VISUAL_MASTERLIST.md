# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This is the current player-facing production backlog, not a completeness claim.

Current production checkpoint: `2ad8536960a9a4cf4fde42bd922f2e73d8239ed6` (Web publication head after shipped Atomium reflection environment #226; substantive parent `ae7b29755e34c1bb9005c79fece7ead1dc1cedd1`).

## North star

For every zone ask: **if a real Brussels photo is beside the game capture, what gives the game away in the first three seconds?**

Optimize in this order:

1. 3-second first impression: silhouette, proportions, materials, obvious placeholders.
2. 30-second immersion: street identity, signage, movement, lighting, clutter and transport vocabulary.
3. 10-minute experience: playable continuity, believable traffic/PNJ behavior, missions, saves and performance.

A green technical check is necessary but is not visual approval. Source truth is also a hard gate: a visible authored proxy for unresolved landmark geometry is not production-ready merely because it looks better.

## Current Director gates — 2026-08-14

- **#225 Bourse official frontage winding**: `technically_green`, `visual_review_needed`, `current_main_rebuild_needed`. Exact-head CI on `c93477c...` is green and the correction preserves all official UrbIS LoD2 vertices/triangles while orienting wall faces outward and roof faces upward. However it originated from production `4c48c48...`; `main` has since shipped Atomium #226. Do not merge stale. Recreate the same bounded payload from exact current `main`, regenerate the deterministic Bourse witness and require direct A/B inspection. Reject if holes/silhouette regressions appear or if impact is negligible.
- **#221 Ixelles first runtime micro-slice**: `runtime_exists_on_pr`, `capture_rejected`, `keep_draft`. Technical runtime/collision/height/capture gates are green for one cell, 309 StreetSurfaces, 277 StreetAxes and 260 strong-source-height buildings; 460 unresolved-height buildings remain correctly absent. Source-anchored camera/LOS fixed the former centre-filling green wall, but human review still sees irregular green DTM patches bleeding through near-field StreetSurfaces. Stay on the same cell; densify/tessellate only the existing official StreetSurface overlay and resample the same DTM at added renderer vertices before another capture.
- **#223 Midi blue-stone material**: `source_disciplined`, `visual_impact_rejected`, `keep_draft`. Exact-head CI is green, but the distant 1280x720 witness is difficult to distinguish without A/B. Preserve the reusable family for a closer/source-confirmed reuse case; do not retune merely to increase pixel delta.
- **#227 Bourse blue-stone foreground**: `source_disciplined`, `visual_impact_rejected`, `closed_without_merge`. The five official sidewalk polygons are correctly bounded and the City source confirms blue-stone use, but the covered band is too small at the hero camera to create an unmistakable player-facing gain. Do not expand material coverage beyond source geometry merely to manufacture impact.
- **#220 Atomium official city trees**: `source_coverage_rejected`, `closed_without_merge`. Deterministic diagnostics proved the locked 8,236-point payload has `radius420=0`, `dtm_bbox=0`, `intersection=0` against the validated Atomium hero terrain. Do not lower the gate, flip axes, fabricate trees or expand terrain just to force vegetation.
- **#222 Bourse portico vault**: `capture_visible`, `source_truth_rejected`, `closed_without_merge`. The effect was visible, but authored proxy radii/heights/depth/arch proportions exceeded what the heritage source proves. Preserve as an experiment only.

## Latest shipped visual gains

- **Atomium reflection environment #226**: `runtime_exists`, `validated_visually`. Deterministic procedural sky adds reflected-light structure to the shipped stainless spheres while preserving accepted ambient/sun readability, DTM anchoring, geometry/topology and no-seam/no-support invariants.
- **Bourse white-stone portico #217**: `runtime_exists`, `validated_visually`. Lighter non-metallic stone improves six-column portico separation without obvious clipping or z-fighting.
- **Midi/Fonsny Fauquenberg brick #215**: `runtime_exists`, `validated_visually`. Source-scaled procedural brick/mortar replaces flat block response on the bounded façade family; no copyrighted photo texture embedded.
- **Atomium stainless presentation #214**: `runtime_exists`, `validated_visually`. Spheres read brighter/more metallic; presentation tessellation increased while dimensions/topology/DTM anchoring remain unchanged and no panel seams are invented.
- **Bourse sidewalk boundary #213**: `runtime_exists`, `validated_visually`. Official bounded sidewalk edge is more readable without claiming a physical curb height.

## Current top 5 perceived-quality bottlenecks

1. **Bourse roof/interior volumes + immediate frontage** — `runtime_exists`, `visual_gap_high`. Authored landmark proxies are forbidden. #225 is the best bounded source-derived frontage candidate but must be rebuilt current-main and visually inspected.
2. **Grand-Place arrival remains visibly sparse** — `runtime_exists`, `visual_gap_high`, `references_needed`. Architecture, paving, roof silhouettes, ground-floor rhythm, signs and street furniture remain far below the real place.
3. **Ixelles street surface/terrain integration is not yet production-believable** — `runtime_exists_on_pr`, `visual_gap_high`. #221 proves one-cell runtime and source-anchored camera, but near-field DTM bleed still makes the street read like a prototype.
4. **Midi identity remains incomplete beyond Fauquenberg brick** — `runtime_exists`, `visual_gap_high`. Station frontage, forecourt, tram/bus interface, bilingual signage, retail frontage and street furniture remain insufficient. Material micro-tuning alone is no longer the best lever.
5. **Atomium hero context still lacks source-backed site structure** — `runtime_exists`, `visual_gap_high`. Stainless + reflections improved strongly, but exact yaw/support feet, pavilion detail and immediate landscape/context remain major giveaways. Tree lot #220 is invalid for the current bounded terrain and must not be revived unchanged.

## Ownership map

- **Centre Vertical Slice**: Bourse/Centre/Midi visible slice. #225 owns the current source-derived Bourse frontage-face correction, but its old-base PR must be recreated from current `main` before integration. #165 remains old unresolved pediment evidence; never invent pediment dimensions.
- **Visual Assets + Atmosphere**: shared materials, furniture, signage, vegetation, lighting/weather/audio. #223 remains impact-rejected; #227 is closed. Pivot to unmistakable high-reuse identity cues: source-backed street furniture/STIB vocabulary, shopfront/window/awning families, or large foreground ground materials where source coverage truly occupies the witness.
- **Ixelles Runtime Slice**: #221 owns the first visible one-cell runtime micro-slice. Keep exact same cell/source hashes/height policy and fix StreetSurface drape/tessellation before adding assets or geography.
- **Laeken Hero Impact**: #226 is shipped. #220 is closed as source-coverage incompatible. Next hero work must stay inside validated terrain and use source-bounded pavilion/context or carefully controlled lighting/reflection improvements; do not fabricate support/yaw geometry.
- **Impact Director maintenance**: Traffic/Living City/gameplay/release only for regressions or unusually high perceived-impact opportunities.

## Bourse / Centre

### Strong foundations already in production

- UrbIS3D hero mass and six-column portico.
- Fixed geotagged 1280x960 witness camera.
- Official StreetSurfaces and bounded official sidewalk geometry.
- Renderer-only sidewalk boundary articulation.
- Visually accepted white-stone portico material.

### Highest-value remaining work

- **Source-derived adjacent frontage readability**: #225 is a bounded candidate. Preserve official vertices/triangles; only fix deterministic face orientation/culling if the current-main witness proves a meaningful gain.
- **Broken/incomplete interior roof/portico volumes**: `visual_gap_high`. #222 proved the visual need but cannot ship authored proxy dimensions. Prefer existing UrbIS/LoD2 surfaces or measurable source constraints.
- **Roof/pediment silhouette**: `visual_gap_high`. #165 owns unresolved pediment evidence; do not invent dimensions.
- **Doors, capitals, sculpture/relief and rear peristyle depth**: `references_needed`, `visual_gap_high`.
- **Street furniture, signs, bins, bollards, poles and café clutter**: `references_needed`, `visual_gap_high`.
- **Physical curb height** remains `references_needed`; official 2D alignment is not permission to invent vertical height.

### Preferred next Centre lot

Rebuild #225 from exact current `main`, rerun CI/capture, and require human A/B. If it is weak or exposes topology holes, close/pivot instead of spending another lot polishing it.

## Midi → Anneessens

### Shipped foundation

- Playable mission/checkpoint/save loop.
- Source-scaled Fauquenberg brick presentation on the bounded Fonsny façade family.

### Highest-value missing work

- Station frontage identity and entries: `references_needed`, `visual_gap_high`.
- Forecourt lanes/curbs/tram-bus interfaces: `references_needed`, `visual_gap_high`.
- Large bilingual station/STIB/wayfinding elements: `references_needed`.
- Retail frontage and ground-floor rhythm: `references_needed`, `visual_gap_high`.
- Street furniture and believable parked/delivery context: `references_needed`.
- Deterministic station-exit / route / Anneessens cameras: `missing`.

#223 blue-stone character is preserved as a reusable authored material experiment, but it is not the next integration candidate at the current distant witness.

## Grand-Place / Centre arrival

- Gameplay arrival: `runtime_exists`.
- Architectural and streetscape credibility: `visual_gap_high`, `references_needed`.
- Next useful proof: one deterministic arrival camera, then make the entire frame coherent before adding more gameplay geography.
- Priority reference families: façade rhythm, roof silhouettes, paving, openings, signs, furniture and evening/overcast lighting.

## Laeken / Atomium / Heysel

### Shipped foundation

- Official DTM runtime with normals/collision.
- 9-sphere / 20-tube source-bounded hero core: 102 m total height, 18 m spheres, 3.30 m tubes.
- Brighter stainless sphere response and higher presentation tessellation (#214).
- Deterministic reflection environment improving stainless readability (#226).
- 26 m circular base-pavilion plan evidence.

### Highest-value remaining work

- Exact global crystal yaw: `references_needed`, `visual_gap_high`.
- Three bipod foot positions/bearings: `references_needed`, `visual_gap_high`.
- Support geometry: blocked until pose evidence is defensible.
- Pavilion height, glazing, roof, entries/stairs: partially `references_found`, still `visual_gap_high`.
- Immediate Heysel landscape/context and furniture: `visual_gap_high`.
- Additional deterministic hero cameras / source-matched context: `references_needed`.

#220 tree payload must not be reused unchanged: its locked source slice does not intersect the validated hero terrain/radius.

## Ixelles

### Current runtime foundation on #221

- One selected cell: `bxl-e149000-n169000-s500`, EPSG:31370 bbox `[149000,169000,149500,169500]`.
- Validated 2 m DTM/source hashes.
- 309 authoritative StreetSurfaces.
- 277 StreetAxes/street segments.
- 260 buildings with strong source-backed height candidates.
- 460 unresolved-height buildings remain absent rather than receiving heuristic heights.
- Runtime/collision/capture gates technically pass.
- Camera is now source-anchored to Rue de Stassart / Place Stéphanie axes with validated 1.72 m eye height and near-field LOS clearance.

### Required next proof

1. Keep exact same cell, DTM hashes, camera anchors and strong-height policy.
2. Densify/tessellate the existing official StreetSurface overlay inside the exact source polygons.
3. Resample the same DTM `sample_height()` at the added renderer vertices; keep only renderer depth bias, with no physical road-height claim.
4. Regenerate the same 1280x960 witness and performance gate.
5. Require human inspection showing continuous road/street surfaces with no prototype green terrain bleed dominating the near field.

No more geography, broad height research or street-furniture work before this passes.

## Shared visual asset priorities

### Priority A — unmistakable Brussels identity

- source-backed STIB stop poles/shelters and transport vocabulary with lawful branding treatment.
- bilingual street-name / wayfinding elements.
- bollards, barriers, railings, bins, benches, bike racks and utility cabinets.
- shopfront, awning, window/door modules.
- foreground paving/cobble/asphalt families only where source-confirmed geometry occupies a substantial witness footprint.
- road/crossing/loading/parking markings only where underlying traffic semantics are sourced.

### Priority B — living-city credibility

- authored clothing/body/age variation.
- bags, umbrellas, backpacks, phones/workwear.
- parked cars/vans/bikes and delivery props only where placement semantics are defensible.
- café furniture and small street clutter.
- Brussels-scale vegetation families only when source placement intersects validated terrain/context.

### Priority C — atmosphere

- controlled overcast daylight target.
- sunny daylight target.
- wet paving/asphalt response.
- rain/night exposure and reflections.
- storefront/window emission.
- traffic/STIB/crowd/rain ambience library with clear licensing/provenance.

## Reference and production rules

1. Prefer Paradigm/UrbIS/UrbIS3D, Brussels Mobility, STIB and official orthophoto/DTM/DSM.
2. Use OSM as complement, not proof for unresolved geometry or traffic semantics.
3. Record lawful photo-reference URL/metadata, approximate camera pose where known, date if relevant, and exactly what the image proves.
4. Do not distribute copyrighted reference imagery as game textures unless licensing explicitly permits it.
5. Acquire references for the exact hero discrepancy or 300–500 m slice being built, not giant random image dumps.
6. Evidence-only work is acceptable only when it is expected to unlock visible/audible/playable runtime change within one or two lots.
7. One active lot per exact problem/domain. Re-check `main` and active PRs before push and merge.
8. A technically green lot can still be rejected for player impact or source truth.

## Definition of a visually convincing micro-slice

A bounded slice is not visually convincing until:

- hero/major silhouette is recognisable;
- street/ground/sidewalk proportions are defensible;
- immediate façades are not generic placeholders;
- key signage/furniture/transport vocabulary is present;
- materials have believable scale/roughness/normal response;
- vegetation and street activity fit the references;
- deterministic cameras have been compared against real references;
- top visible discrepancies are fixed or explicitly blocked by missing evidence;
- performance remains acceptable;
- a human reviewer does not identify one huge prototype giveaway in the first three seconds.

## Direction rule for future lots

Prefer **one obvious player-facing improvement** over several low-visibility evidence additions when both are equally safe and source-backed. Pixel delta is evidence, not the target. Judge recognition, silhouette, material response, atmosphere, legibility, motion and gameplay feel. Never trade source truth for a nicer screenshot.