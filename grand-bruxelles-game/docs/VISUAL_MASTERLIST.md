# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This is the current player-facing production backlog, not a completeness claim.

Current production checkpoint: `0efa00c59739b06540bbc0f26af1819c2eed8b46` (Direction/masterlist head; latest shipped visual runtime below it includes Bourse #217, Midi #215 and Atomium #214).

## North star

For every zone ask: **if a real Brussels photo is beside the game capture, what gives the game away in the first three seconds?**

Optimize in this order:

1. 3-second first impression: silhouette, proportions, materials, obvious placeholders.
2. 30-second immersion: street identity, signage, movement, lighting, clutter and transport vocabulary.
3. 10-minute experience: playable continuity, believable traffic/PNJ behavior, missions, saves and performance.

A green technical check is necessary but is not visual approval. Source truth is also a hard gate: a visible authored proxy for unresolved landmark geometry is not production-ready merely because it looks better.

## Current Director gates — 2026-08-14

- **#222 Bourse portico vault**: `capture_visible`, `source_truth_rejected`, `keep_draft`. Direct 1280x960 comparison against shipped #217 changes about 14,428 pixels above a 3-RGB threshold (~1.174%), and the interior reads more complete. However the heritage source proves only the semantic existence of two additional Corinthian columns and a coffered barrel vault; the PR uses authored proxy radii/heights/depth/arch proportions. Do not merge unresolved landmark dimensions. Preserve the experiment and pivot to source-bounded UrbIS/LoD2 surfaces, measurable envelope constraints or another defensible immediate frontage.
- **#223 Midi blue-stone character**: `source_disciplined`, `visual_impact_rejected`, `keep_draft`. Exact-head CI is green, but the 1280x720 witness changes only about 3,046 pixels above an 8-RGB threshold (~0.331%) and is difficult to notice without A/B comparison. Preserve the material family for a closer/reuse case; do not spend another lot retuning it just to increase pixel delta.
- **#221 Ixelles first runtime micro-slice**: `runtime_exists_on_pr`, `capture_rejected`, `keep_draft`. Technical runtime/collision/height/capture gates are green for one cell, 309 StreetSurfaces, 277 StreetAxes and 260 strong-source-height buildings; 460 unresolved-height buildings remain correctly absent. Human inspection rejects the current witness because a large undifferentiated green terrain mass dominates the centre/foreground and Place Stéphanie does not read as a Brussels street. Stay on the same cell; fix street-aligned camera/near-field terrain visibility before merge.
- **#220 Atomium official city trees**: `ci_blocked`, `keep_draft`. The hero core builds, but the tree pass fails before capture with `no source tree intersects the official hero terrain`. The tree Lambert-to-local conversion matches AtomiumDTMTerrain. Source bbox overlaps the DTM bbox, but the Atomium is only ~89.75 m north of the DTM tile's southern edge, so a 420 m hero radius is not fully represented by the bounded terrain. Compute deterministic Lambert-space / DTM-bbox / intersection counts; never weaken the gate or fabricate tree positions merely to make vegetation appear.

**No current visual PR is integration-ready.** Keeping `main` clean is higher value than shipping technically green but source-weak, imperceptible or visually failed lots.

## Status vocabulary

- `missing`: absent from production.
- `references_needed`: no defensible source/reference locked yet.
- `references_found`: enough source evidence exists for the bounded question.
- `geometry_exists`: geometry/data exists but is not necessarily visible or final.
- `runtime_exists`: visible/consumed in production runtime.
- `visual_gap_high`: immediately harms recognition or credibility.
- `ready_for_asset_work`: enough reference exists to author the next bounded asset/material.
- `ready_for_photo_match`: deterministic camera/reference exists.
- `validated_visually`: human-reviewed capture accepted for the current milestone.
- `source_truth_rejected`: visual effect may be useful, but production geometry/semantics exceed what evidence proves.
- `visual_impact_rejected`: technically/source-correct work is too subtle at the production witness to justify the next merge.
- `capture_rejected`: runtime works, but the human-reviewed player view fails the current visual milestone.

## Latest shipped visual gains

- **Bourse white-stone portico #217**: `runtime_exists`, `validated_visually`. Lighter non-metallic stone improves six-column portico separation without obvious clipping or z-fighting. This does not make the Bourse visually complete.
- **Midi/Fonsny Fauquenberg brick #215**: `runtime_exists`, `validated_visually`. Source-scaled procedural brick/mortar replaces flat block response on the bounded façade family; no copyrighted photo texture embedded.
- **Atomium stainless presentation #214**: `runtime_exists`, `validated_visually`. Spheres read brighter/more metallic; presentation tessellation increased while dimensions/topology/DTM anchoring remain unchanged and no panel seams are invented.
- **Bourse sidewalk boundary #213**: `runtime_exists`, `validated_visually`. Official bounded sidewalk edge is more readable without claiming a physical curb height.

## Current top 5 perceived-quality bottlenecks

1. **Bourse roof/interior volumes and landmark detail** — `runtime_exists`, `visual_gap_high`. #222 demonstrates that the portico interior is a large giveaway, but authored proxy landmark dimensions are forbidden. Next correction must be source-bounded.
2. **Grand-Place arrival remains visibly sparse** — `runtime_exists`, `visual_gap_high`, `references_needed`. Architecture, paving, roof silhouettes, ground-floor rhythm, signs and street furniture remain far below the real place.
3. **Ixelles runtime view is not yet recognisable** — `runtime_exists_on_pr`, `visual_gap_high`. #221 finally mounts a real one-cell runtime slice, but the current ground-level witness is visually dominated by terrain and is not acceptable yet.
4. **Midi identity remains incomplete beyond Fauquenberg brick** — `runtime_exists`, `visual_gap_high`. Station frontage, forecourt, tram/bus interface, bilingual signage, retail frontage and street furniture remain insufficient. #223 is too subtle to be the next win.
5. **Atomium hero context remains generic** — `runtime_exists`, `visual_gap_high`. Stainless response is improved, but support pose, pavilion detail, landscape/context and reflection environment remain major giveaways. #220 tree context is currently incompatible or incorrectly filtered against the bounded hero terrain and must not be forced through.

## Ownership map

- **Centre Vertical Slice**: Bourse/Centre/Midi visible slice. #222 owns the current Bourse interior experiment but is source-truth rejected; do not merge or expand authored proxy landmark geometry. #165 remains the old unresolved pediment evidence gate.
- **Visual Assets + Atmosphere**: shared materials, furniture, signage, vegetation, lighting/weather/audio. #223 is impact-rejected at the current witness; pivot to a larger-footprint/high-identity reusable family without overlapping geographic owners.
- **Ixelles Runtime Slice**: #221 owns the first visible one-cell runtime micro-slice. Keep the same cell and fix camera/ground readability; no geography expansion or heuristic heights.
- **Laeken Hero Impact**: #220 owns official-tree context diagnosis. Stay on the same PR until intersection diagnostics prove whether the lot is viable; otherwise shelve and pivot inside the validated hero terrain.
- **Impact Director maintenance**: Traffic/Living City/gameplay/release only for regressions or unusually high perceived-impact opportunities.

## Bourse / Centre

### Strong foundations already in production

- UrbIS3D hero mass and six-column portico.
- Fixed geotagged 1280x960 witness camera.
- Official StreetSurfaces and bounded official sidewalk geometry.
- Renderer-only sidewalk boundary articulation.
- Visually accepted white-stone portico material.

### Highest-value remaining work

- **Broken/incomplete interior roof/portico volumes**: `visual_gap_high`. #222 confirms the visual need but its authored proxy dimensions cannot ship. Prefer existing UrbIS/LoD2 surfaces or measurable source constraints.
- **Roof/pediment silhouette**: `visual_gap_high`. #165 owns unresolved pediment evidence; do not invent dimensions.
- **Immediate adjacent façades**: `references_needed`, `visual_gap_high`.
- **Doors, capitals, sculpture/relief and rear peristyle depth**: `references_needed`, `visual_gap_high`.
- **Street furniture, signs, bins, bollards, poles and café clutter**: `references_needed`, `visual_gap_high`.
- **Physical curb height** remains `references_needed`; official 2D alignment is not permission to invent vertical height.

### Preferred next Centre lot

Use source-bounded existing geometry or a bounded immediate façade/frontage correction. Do not return to tiny rear-entry polish or broaden #222 proxy architecture.

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
- 26 m circular base-pavilion plan evidence.

### Highest-value remaining work

- Exact global crystal yaw: `references_needed`, `visual_gap_high`.
- Three bipod foot positions/bearings: `references_needed`, `visual_gap_high`.
- Support geometry: blocked until pose evidence is defensible.
- Pavilion height, glazing, roof, entries/stairs: partially `references_found`, still `visual_gap_high`.
- Immediate Heysel landscape/context and furniture: `visual_gap_high`.
- Reflection/lighting environment and additional deterministic hero cameras: `references_needed`.

### #220 tree gate

Before any change, count official source points (a) inside the 420 m Atomium radius in EPSG:31370, (b) inside the exact DTM EPSG:31370 bbox, and (c) in their intersection. If intersection is truly zero, shelve the lot rather than expanding terrain only to create vegetation. If nonzero, fix the extraction/filter discrepancy and capture the result.

## Ixelles

### Current runtime foundation on #221

- One selected cell: `bxl-e149000-n169000-s500`, EPSG:31370 bbox `[149000,169000,149500,169500]`.
- Validated 2 m DTM/source hashes.
- 309 authoritative StreetSurfaces.
- 277 StreetAxes/street segments.
- 260 buildings with strong source-backed height candidates.
- 460 unresolved-height buildings remain absent rather than receiving heuristic heights.
- Runtime/collision/capture gates technically pass.

### Required next proof

1. Keep the exact same cell/data policy.
2. Re-anchor the deterministic camera to a source-confirmed street corridor at ~1.6–1.8 m eye height.
3. Verify sampled terrain at camera/target and add a near-field line-of-sight terrain-occlusion guard.
4. If terrain still dominates after correct street alignment, inspect only terrain/street draping and vertical-reference transform.
5. Regenerate 1280x960 capture and require human visual acceptance before merge.

No more terrain expansion or broad building-height research before this visible proof.

## Shared visual asset priorities

### Priority A — immediate Brussels recognition

- foreground paving/cobble/asphalt families with source-confirmed identity and clearly visible witness footprint.
- STIB stop poles/shelters and transport vocabulary where lawful/source-backed.
- bilingual street-name / wayfinding elements.
- bollards, barriers, railings, bins, benches, bike racks, utility cabinets.
- shopfront, awning, window/door modules.
- road/crossing/loading/parking markings only where underlying traffic semantics are sourced.

### Priority B — living-city credibility

- authored clothing/body/age variation.
- bags, umbrellas, backpacks, phones/workwear.
- parked cars/vans/bikes and delivery props only where placement semantics are defensible.
- café furniture and small street clutter.
- Brussels-scale vegetation families where source placement/context is compatible with validated terrain.

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