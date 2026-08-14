# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This is the current player-facing production backlog, not a completeness claim.

Current production checkpoint: `62b90d82e79b42c4afa8e99ccd76df9984a3ce36` (publication head after Bourse white-stone portico #217; substantive parent `5a3ef0b81b4fea376f5946fd90bb8f58714c58a7`).

## North star

For every zone ask: **if a real Brussels photo is beside the game capture, what gives the game away in the first three seconds?**

Optimize in this order:

1. 3-second first impression: silhouette, proportions, materials, obvious placeholders.
2. 30-second immersion: street identity, signage, movement, lighting, clutter and transport vocabulary.
3. 10-minute experience: playable continuity, believable traffic/PNJ behavior, missions, saves and performance.

A green technical check is necessary but is not visual approval. Substantive visual lots require deterministic capture and human inspection whenever practical.

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

## Latest shipped visual gains

- **Bourse white-stone portico #217**: `runtime_exists`, `validated_visually`. Current-main replacement inspected at 1280x960; lighter non-metallic stone improves six-column portico separation without obvious clipping or z-fighting. This does **not** make the Bourse visually complete.
- **Midi/Fonsny Fauquenberg brick #215**: `runtime_exists`, `validated_visually`. Source-scaled procedural brick/mortar material replaces flat yellow-brown block response on the bounded façade family; no copyrighted photo texture embedded.
- **Atomium stainless presentation #214**: `runtime_exists`, `validated_visually`. Spheres read brighter/more metallic; presentation tessellation increased while dimensions/topology/DTM anchoring remain unchanged and no panel seams are invented.
- **Bourse sidewalk boundary #213**: `runtime_exists`, `validated_visually`. Official bounded sidewalk edge is more readable without claiming a physical curb height.

## Current top 5 perceived-quality bottlenecks

1. **Bourse still reads as a technical reconstruction.** `runtime_exists`, `visual_gap_high`. The portico material improved, but broken/incomplete roof and pediment forms, missing façade detail, generic openings, adjacent frontage and sparse street context dominate the frame.
2. **Grand-Place arrival is visibly sparse.** `runtime_exists`, `visual_gap_high`, `references_needed`. The gameplay route arrives there, but architecture, paving, roof silhouettes, ground-floor rhythm, signs and street furniture are far below the real place.
3. **Midi identity remains incomplete beyond the new brick family.** `runtime_exists`, `visual_gap_high`. Station frontage, forecourt, tram/bus interface, large bilingual signage, retail frontage and street furniture still lack sufficient specificity.
4. **Ixelles still has no genuine current-main runtime micro-slice.** `geometry_exists`, `visual_gap_high`. Strong 2 m DTM evidence exists, but the player still cannot judge a recognisable Ixelles scene in production.
5. **Atomium hero context is too generic.** `runtime_exists`, `visual_gap_high`. Stainless response improved, but exact yaw/support feet, pavilion detail, immediate landscape/context and richer reflection environment remain major giveaways.

## Ownership map

- **Centre Vertical Slice**: Bourse/Centre/Midi visible slice. #217 is shipped. #165 remains the old unresolved Bourse pediment evidence gate; do not fabricate the pediment.
- **Visual Assets + Atmosphere**: shared materials, furniture, signage, vegetation, lighting/weather/audio. #215 proved the correct pattern: authored reusable asset + immediate runtime integration + capture.
- **Ixelles Runtime Slice**: first visible Ixelles micro-slice. #204 remains the single owner of the five-cell 2 m collision-parity problem, but the PR is stale/evidence-only and must not be merged wholesale.
- **Laeken Hero Impact**: Atomium/Heysel hero presentation. #214 is shipped. #182 remains old support-semantics evidence only; exact support feet/yaw remain unresolved.
- **Impact Director maintenance**: Traffic/Living City/gameplay/release only for regressions or unusually high perceived-impact opportunities.

## Bourse / Centre

### Strong foundations already in production

- UrbIS3D hero mass and six-column portico.
- Fixed geotagged 1280x960 witness camera.
- Official StreetSurfaces and bounded official sidewalk geometry.
- Renderer-only sidewalk boundary articulation.
- Visually accepted white-stone portico material.

### Highest-value remaining work

- **Roof/pediment silhouette and broken interior roof volumes**: `visual_gap_high`. Use source-backed geometry only. #165 owns unresolved pediment evidence; do not invent dimensions.
- **Doors, frames, capitals, sculpture/relief and rear peristyle depth**: `references_needed`, `visual_gap_high`.
- **Immediate adjacent façades in the witness**: `references_needed`, `visual_gap_high`.
- **Hero glass/metal/secondary stone response**: `ready_for_asset_work` where source identity is known.
- **Street furniture, signs, bins, bollards, poles and café clutter**: `references_needed`, `visual_gap_high`.
- **Physical curb height** remains `references_needed`; official 2D alignment is not permission to invent vertical height.

### Preferred next Centre lot

Choose the single largest in-frame geometric/context giveaway that is not already owned. Prefer a source-backed roof/frontage correction or a bounded immediate façade over another evidence inventory. The portico material is done; do not keep polishing it while large silhouette defects remain.

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

### Acquisition target

Lock lawful/geolocated references and official geometry for only the next 300–500 m visible route segment. Improve the cameras before expanding geography.

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
- Immediate Heysel landscape/context, vegetation and furniture: `references_needed`.
- Reflection/lighting environment and additional deterministic hero cameras: `references_needed`.

### Preferred next Laeken lot

Do not let blocked support geometry freeze the stream. If yaw/feet remain unresolved, improve a defensible player-facing discrepancy that does not depend on them: pavilion envelope/detail, immediate context, vegetation, or reflection/lighting response.

## Ixelles

### Evidence already available

- Validated contiguous 2 m DTM evidence with zero measured seam-height/normal discontinuity on the tested block.
- #204 collision source-space parity evidence exists but remains non-production.
- First visible micro-slice selected: `bxl-e149000-n169000-s500`, EPSG:31370 bbox `[149000,169000,149500,169500]`.
- Current data inventory for that cell includes roughly 720 authoritative buildings, 309 street surfaces and 277 street segments.

### Required next runtime proof

1. Recreate only the minimum validated collision/runtime-transform gate from exact current `main`.
2. Mount the selected one-cell 2 m DTM slice.
3. Consume the existing authoritative buildings/streets for that same cell.
4. Add one deterministic camera and lawful/authoritative visual reference.
5. Capture and inspect the result.

No further terrain expansion or broad building-height research before this visible proof. Nonessential unresolved heights should remain conservative instead of blocking the whole slice.

## Jette

- Long-lived specialist branch remains evidence/workspace only.
- Do not merge wholesale.
- Future priority: one small current-main slice such as Miroir or station, with one deterministic camera and street-level references.

## Shared visual asset priorities

### Priority A — immediate Brussels recognition

- blue-stone / limestone / paving / cobble families.
- Belgian brick/plaster variants with plausible scale and roughness.
- STIB stop poles/shelters and transport vocabulary where lawful/source-backed.
- bilingual street-name / wayfinding elements.
- bollards, barriers, railings, bins, benches, bike racks, utility cabinets.
- shopfront, awning, window/door modules.
- road/crossing/loading/parking markings where the underlying traffic semantics are sourced.

### Priority B — living-city credibility

- authored clothing/body/age variation.
- bags, umbrellas, backpacks, phones/workwear.
- parked cars/vans/bikes and delivery props only where placement semantics are defensible.
- café furniture and small street clutter.
- Brussels-scale vegetation families.

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

Prefer **one obvious player-facing improvement** over several low-visibility evidence additions when both are equally safe and source-backed. Pixel delta is evidence, not the target. Judge recognition, silhouette, material response, atmosphere, legibility, motion and gameplay feel.