# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This is the player-facing direction backlog, not a completeness claim.

Current production checkpoint: `a0540142bfe7bb2490774ba3d5f109aefc2caf57` (Direction/docs only). Latest substantive player-facing merge beneath it remains `3c2941a11dca4af78f81b4f651365887a8e42f15` (#265 Grand-Place Town Hall white-stone walls), with Web publication `23e00aa33592ef0e6883ea429802336e3490bbc4`.

## North star

Ask at every zone: **if a real Brussels photo or observation is beside the game, what gives the game away in the first three seconds?**

Optimize three horizons:

1. **3 seconds** — silhouette, proportions, materials, landmark/street identity, obvious placeholders.
2. **30 seconds** — signage, transport vocabulary, furniture, motion, clutter, lighting and atmosphere.
3. **10 minutes** — playable continuity, navigation, believable traffic/PNJ behavior, missions/saves and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient. Source truth and direct player-facing inspection are hard gates.

## Director gates — 2026-08-14 16:13 Brussels

### Shipped anchors

- **#265 Grand-Place Town Hall white-stone walls** — `shipped`, `major_material_identity_gain`. Exact official UrbIS3D geometry/roof retained; source-backed white-stone WALLSURFACE presentation. Director A/B: 57,970 pixels >3 RGB = 6.2901% of 1280×720. Human accepted.
- **#260 Grand-Place official LoD2 ensemble mass 1786758** — `shipped`, `ensemble_gain`. 65,125 pixels >3 RGB = 7.0665%; human accepted.
- **#257 Grand-Place official LoD2 landmark mass 1655673** — `shipped`, `major_silhouette_gain`. ~102,017 pixels >3 RGB = 11.07% of 1280×720.
- **#258 Ixelles Stassart 124 blue-stone frontage** — `shipped`, `local_identity_gain`. Direct-player A/B: 111,611 pixels >=12/255; 460 unresolved-height buildings remain absent.
- **#254 Atomium direct 48° FOV framing** — `shipped`, `major_landmark_presentation_gain`. Same source-bounded player position/pitch; ~43.08% of 1280×720 >8 RGB.
- **#243 bilingual Brussels street-name plaque**, **#242 direct Ixelles entry**, **#241 Bourse roof winding**, **#239 Ixelles compact runtime**, **#230 Atomium direct entry**, **#226 Atomium reflections**, **#217 Bourse white-stone portico**, **#215 Midi/Fonsny brick**, **#214 Atomium stainless** remain production foundations.

### Active / newly adjudicated

- **#268 Atomium pavilion official LoD2 source gate** — `active_draft`, `source_gate_passed`, `highest_value_next_runtime_candidate`. Official Paradigm/UrbIS3D building `1651628`, package SHA-256 `ed94f066fc2c869d8b2cb5755a6116d839111ec6d0f03239e1af8a6c9272ddbe`, CC0, EPSG:31370. Exact extraction: 16 WALLSURFACE + 2 ROOFSURFACE + 1 GROUNDSURFACE, 60 triangles, 40.007 × 27.484 m envelope, 6.674 m source height, center ~6.63 m from locked Atomium anchor. Conservative 120 m / 48° / 16:9 apparent-area proxy = 1.637%. This is evidence-only today but directly unlocks one runtime lot: mount exact official geometry on the same PR lineage and require deterministic 1280×960 hero + 1280×720 `?spawn=atomium` A/B. No DSM height, yaw, support feet, vegetation or authored pavilion dimensions.
- **#267 Midi bilingual station identity** — `active_draft`, `dedicated_visual_red`. Official SNCB/NMBS bilingual naming and Fonsny address are source-backed; general test, Game CI, Branch Hygiene, Web Export, Photo Match and Performance are green. Dedicated 1280×720 A/B currently measures `changed=0`. Keep the 23k/2.5% anti-micro gate. Diagnose visibility/occlusion/local-transform/toggle on this same PR; do not enlarge authored text or move the camera to manufacture impact. Close if a truthful corrected witness remains negligible.
- **#269 Grand-Place Town Hall slate roof** — `closed_without_merge`, `source_disciplined_but_human_impact_rejected`. Initial zero-delta run was a test-harness bug (`look_at()` before the camera entered the tree); Director fixed the harness only. Corrected exact-head CI then went fully green and measured 31,721 pixels >3 RGB = 3.4419% and 20,746 >8 RGB = 2.2511%. Direct full-frame human review still found the material shift too subtle and mainly readable under cropped A/B, triggering the PR's own rejection rule. Preserve source/helper evidence; do not merge this presentation now.
- **#261 Ixelles next-identity discovery** — `closed_without_merge`, `evidence_preserved`. Discovery established three eligible in-cell strong-source buildings; later selection work favored Place Stéphanie 8 / building 1737880. Any runtime cue must be rebuilt as a new compact exact-current-main lot; do not revive the stale discovery history.
- **#231 shared STIB surface-stop vocabulary** — `technically_green`, `human_visual_accepted`, `placement_source_deferred`. Keep draft only while a real stop + actual furniture subset can be proven. Do not infer shelter/bench/info/yaw/curb semantics.
- **#223 Midi blue-stone** — `source_disciplined`, `visual_impact_rejected`.
- **#222 Bourse vault proxy** — `source_truth_rejected`, `closed_without_merge`.
- Older Laeken trees/StreetSurface/esplanade/contaminated-height probes remain rejected; long-lived #2/#11 remain evidence/lab only and are never merge units.

## Active ownership map

- **Centre Vertical Slice** — #267 owns the current Midi station-identity question. Grand-Place shipped #257/#260/#265; no active Grand-Place runtime lot after #269 rejection. Next Centre lot must be a materially stronger Grand-Place/Bourse/Midi cue, not another micro-material pass.
- **Visual Assets + Atmosphere** — shared #231 STIB family remains preserved but placement-deferred. No duplicate station-identity lot while #267 is active.
- **Ixelles Runtime Slice** — #239/#242/#258 are shipped. #261 is closed; next quality cue requires a fresh current-main compact PR if pursued.
- **Laeken Hero Impact** — #268 is the sole high-value active Atomium context owner. It has passed the source pre-gate and must now convert to player-facing runtime evidence within one lot or close.
- **Impact Director maintenance** — Traffic/Living City/missions/saves/release remain maintenance-only unless a blocking regression or unusually high perceived-impact defect appears.

## Current top 5 perceived-quality bottlenecks

1. **Grand-Place coherent detailed recognition** — `visual_gap_high_but_improving_fast`. Massing and Town Hall wall identity are materially better, but roofs/openings/secondary façades/paving/context still read simplified. Reject micro-material deltas that are only visible under crop.
2. **Bourse roof/interior volumes + immediate frontage** — `visual_gap_high`. Existing improvements are real, but simplified/incomplete structure remains obvious; no proxy pediment or invented landmark dimensions.
3. **Midi station/STIB/public-space identity** — `visual_gap_high`. #267 is currently red at the player-facing gate; #231 is placement-blocked. A truthful, readable station/transport cue remains valuable if it can survive normal-distance A/B.
4. **Ixelles local identity density** — `identity_gap_medium_high`. Direct access and Stassart 124 are shipped; the same cell still needs another substantial source-backed cue rather than more infrastructure or micro-signage.
5. **Atomium immediate pavilion/site context** — `visual_gap_high`, now with a strong source unlock. #268 has found exact official LoD2 pavilion geometry; this is the clearest current opportunity to replace generic base context without inventing dimensions.

## Stream health

- **Centre** — `productive_but_current_candidate_red`: recent shipped Grand-Place gains were excellent, but #269 was human-rejected and #267 currently has zero visible delta. Pivot rather than lower gates.
- **Visual Assets + Atmosphere** — `disciplined_but_source_blocked`: shared identity work is useful, but do not keep STIB alive by inertia or duplicate #267.
- **Ixelles** — `productive_with_no_active_runtime_lot`: shipped runtime/access/frontage are healthy; next change should be one large local identity cue from fresh current main.
- **Laeken** — `high_confidence_source_unlock`: #268 is the best current specialist lead because it converts a previously unresolved pavilion-height problem into exact official LoD2 geometry with measurable projected area.

## Shared priorities

1. **Atomium pavilion exact LoD2 runtime from #268** — highest confidence/impact next candidate, subject to hero + direct-player A/B and human inspection.
2. **Grand-Place coherent recognition** — choose a large source-backed cue that is more obvious than the rejected slate pass; no object-count or micro-material loop.
3. **Midi station identity** — debug #267 without weakening its gate; close if normal-distance impact remains zero/negligible.
4. **Ixelles second local identity cue** — fresh exact-current-main compact lot only, same shipped cell.
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

**Highest-value next candidate: convert #268's exact official Atomium pavilion LoD2 source gate into a bounded runtime hero/direct-player A/B on the same candidate. The source confidence is high, the envelope is substantial, the candidate is centered on the locked Atomium base, and the projected-area pre-gate clears the anti-micro threshold. No merge until player-facing captures and human inspection pass. If #268 underperforms visually, pivot immediately to a larger Grand-Place/Bourse/Midi cue rather than deepen evidence research.**
