# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. Optimize player-perceived Brussels quality, not commit count.

Current production checkpoint: `9986ee9d04e30bf2d027e8b6590d47054dce14ab` (#317 documentation-only). Latest substantive player-facing merge remains `131449b2aee9fcb29b1445e9fc1e4f5d51fbead3` (#314 Ixelles 2×2 source-backed streaming cluster), followed by publication-only `4a4ae52b1230f99ae1b836afa6fe4bbe7a97f287`. Focused source/tooling foundation #309 remains available for targeted Midi/Fonsny work.

## North star

Judge three horizons: **3-second recognition**, **30-second immersion**, **10-minute playable continuity**. Use **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI, source correctness and pixel delta are evidence, never the objective.

## Director checkpoint — 2026-08-15 01:10 Brussels

### Fresh production truth and rejects

- **#314 Ixelles 2×2 source-backed streaming cluster** — `shipped_10min_coverage_gain_with_human_qa_debt`. Four contiguous UrbIS cells are production truth. Original Ixelles cell keeps full DTM + strong-height runtime; three neighbors remain plan-only official StreetSurface geometry. No fifth cell or new streaming feature is allowed until direct sustained Web/phone traversal proves pop, plan-only transitions, memory/performance, collision tiering, unload/reload and driven-vehicle following are acceptable.
- **#309 Midi/Fonsny hole-aware UrbIS3D extractor** — `shipped_source_tooling_foundation`. Exact building 1633645 remains available with 889 faces, 3,428 triangles, 13.6076 m source height, 852 WALLSURFACE + 34 ROOFSURFACE, Paradigm/UrbIS3D EPSG:31370 CC0 and locked package SHA-256 `a760fdff222ae9431113f82fe1c8f942a9fe2bda40e32064c627ae8d3a21110f`. Whole-building use is rejected; only source-semantic subsets that improve station recognition qualify.
- **#312 Midi/Fonsny whole-building LoD2 replacement** — `closed_without_merge_human_recognition_reject`. A/B was enormous (69.2238% >3 RGB; 67.2808% >8 RGB) but human full-frame inspection found the result less recognisable: fragmented low grey masses replaced a readable authored station frontage. Never rescue with camera/FOV/scale/material manipulation.
- **#313 Ixelles Stassart 131 identity** — `closed_without_merge_human_recognition_reject`. 261,023 meaningful pixels changed, yet the result read as a generic flat light-grey slab rather than recognisable heritage. Pixel area cannot overrule recognition.
- **#316 Atomium official sidewalk runtime** — `closed_without_merge_player_frame_zero`. Projection gate had predicted 13.5802% exclusive player-wedge coverage, but the exact-source actual `spawn=atomium` runtime A/B changed **0 / 921,600 pixels** >3 and >8. End Atomium sidewalk research; no camera/material/threshold rescue.
- **#318 Bourse source-face roof smoothing** — `closed_without_merge_anti_micro`. Source contract was valid: 231 roof faces, 838 triangles, 39 source-face smoothing opportunities; runtime preserved geometry and smoothed 117 vertex occurrences. Normal-eye 1280×720 A/B changed only **131 pixels >3 RGB = 0.0142%**, 41 >8 RGB = 0.0044%, bbox `[533,2,735,66]`. Do not revive roof-normal smoothing.
- **#319 Bourse exterior-base GROUNDSURFACE visibility** — `closed_without_merge_player_frame_zero`. Exact base reproduced the logical regression and exact head passed it while preserving 66 source triangles and wall/roof visibility. All broad gates were green, but normal-player exact base/head A/B changed **0 / 921,600 pixels >3; 0 >8; bbox none**. Correct invariant, zero player value; defer indefinitely unless a future view exposes it as a concrete defect.
- **#320 STIB Suède / Zweden runtime** — `closed_without_merge_anti_micro`. Runtime contract itself passed with official stop 2539, bilingual `Suède/Zweden` identity and queue=3 using existing transit behavior. Deterministic normal-distance witness changed only **1,223 pixels = 0.1327% >3 RGB** and failed its own visual gate. Do not enlarge the marker, move the camera or lower the threshold to rescue it. The source point remains historically useful only if a future broader transit/public-space lot makes it naturally visible.
- **#310 Atomium RoadArea** — remains `closed_without_merge_player_frame_zero`: hero QA 2.6837%, actual direct-player frame 0.0000%.

### Active Director decisions

- **Centre / Midi first** — recent Bourse #318/#319 attempts prove hidden/shading/invariant micro-fixes are poor use of the Centre slot. The next Centre lot must improve **street-level Bruxelles-Midi/Fonsny recognition** while preserving the readable authored station frontage. Preferred path: a defensible source-bounded Fonsny-facing envelope/roof/arrival/forecourt subset from existing official geometry that replaces a clearly visible placeholder region without wholesale LoD2 replacement. Require a normal-player projected-area estimate and qualitative recognition hypothesis before coding.
- **Bourse second** — only a large exposed roof/interior/frontage/silhouette discrepancy qualifies. No roof-normal smoothing, hidden floor/base, depth micro-fix, subtle material tweak or unresolved pediment fabrication.
- **Ixelles** — streaming infrastructure remains hard-frozen at four cells. First pay direct sustained traversal QA; after that, only one same-coverage identity cue with strong architectural/street recognition may run.
- **Laeken** — repeated source-valid ground/context paths (#310/#316, and older pavilion/road attempts) have produced zero real direct-player impact. Stream must idle until a fundamentally different candidate can demonstrate material visibility in the actual direct-spawn frame before implementation.
- **Visual Assets + Atmosphere** — isolated STIB stop identity #320 is too small. Pivot to one reusable Brussels cue with large normal-distance presence or audible immersion value: broad bilingual/public-transport vocabulary on naturally visible production planes, a reusable Brussels-specific façade/material family, or lawful ambient/audio layer. No evidence-only continuation.
- **#11/#2** — long-lived specialist workspaces only; never merge wholesale.

## Active ownership map

- **Centre Vertical Slice** — owns Bourse/Centre/Midi visible slice. No active runtime PR after #319 closure. Exclusive next problem: large, targeted Midi/Fonsny recognition gain; Bourse only if Midi has no defensible positive subset.
- **Visual Assets + Atmosphere** — owns shared PBR/materials/furniture/signage/vegetation/lighting/weather/audio. No active runtime PR after #320 closure. Next lot must be reusable and materially visible/audible.
- **Ixelles Runtime Slice** — owns Ixelles identity and the shipped four-cell production cluster. Streaming expansion is frozen; direct sustained traversal QA is the immediate obligation.
- **Laeken Hero Impact** — owns Atomium/Heysel presentation. No active runtime PR. Ground/road/sidewalk context loops are closed; do not reopen without a fundamentally different player-visible candidate.
- **Director maintenance** — traffic/Living City/missions/saves/release only for concrete blocker/regression or unusually high perceived-impact opportunity. Current maintenance duty is stabilization/human QA, not new subsystems.

## Top 5 perceived-quality bottlenecks

1. **Bruxelles-Midi frontage / arrival / transport identity** — `3sec_very_high`. Current authored frontage remains more readable than wholesale exact LoD2, but surrounding massing/arrival identity is still placeholder-like. Highest-value target is a selective exact-source correction that improves recognition without destroying the readable station face.
2. **10-minute streaming continuity proof after #314** — `10min_high`. Four-cell production coverage is larger, but direct Web/phone traversal still owes proof for pop, plan-only boundaries, memory/performance feel, DTM collision transitions, unload/reload and vehicle following.
3. **Bourse exposed roof/interior/frontage coherence** — `3sec_high`. Landmark remains simplified, but #318/#319 demonstrate that hidden surface and normal-only work is negligible. Only a visibly exposed structural or silhouette correction qualifies.
4. **Ixelles local identity density** — `30sec_medium_high`. Coverage expanded faster than recognisable identity. Recent large-delta #313 still looked generic; next cue must read as Ixelles/Brussels, not merely occupy pixels.
5. **Reusable Brussels transit/signage/atmosphere vocabulary** — `3sec_30sec_medium_high`. #320 proved that one small stop marker is insufficient. Seek a cue whose scale/reuse/placement naturally affects multiple player moments, including audio where appropriate.

## Stream health

- **Centre** — `drifting_into_micro_fixes_then_redirected`. #318 and #319 were source-correct but visually negligible. Stop Bourse micro-loop; move to a large positive Midi/Fonsny recognition lot.
- **Visual Assets + Atmosphere** — `runtime_attempt_rejected_then_free`. #320 finally reached runtime but only 0.1327% normal-distance effect. Source work was not wasted, but isolated marker path is closed; pivot to higher-reuse identity/ambience.
- **Ixelles** — `productive_but_stabilization_overdue`. #314 is source-disciplined production truth, but expansion exceeded the prior freeze. No more infrastructure until human long-traversal QA is recorded.
- **Laeken** — `source_disciplined_but_low_player_return`. #316 completed the allowed runtime shot and proved zero direct-player effect. Idle rather than opening another ground/context evidence chain.
- **Director maintenance** — `healthy_stabilization`. No active maintenance feature lot; keep it that way unless a concrete regression appears.
- **Navigation** — `closed_truthfully_blocked`; missing Grand-Place -> Bourse graph connectivity remains unresolved without fabrication.

## Shared priorities

1. **One targeted street-level Midi/Fonsny recognition lot** from exact current main, preserving the readable authored station frontage and using existing official source geometry only where it clearly replaces visible placeholder massing/arrival context. Deterministic normal-player A/B + human verdict are mandatory.
2. **Direct sustained Web/phone traversal review of the shipped four-cell Ixelles cluster** before any fifth cell or streaming feature.
3. **One large exposed Bourse structural/roof/interior correction** only if its projected normal-player area and source contract are strong before coding.
4. **One recognisable same-coverage Ixelles identity cue** after traversal QA, judged qualitatively before pixel count.
5. **One reusable Brussels transit/signage/atmosphere cue** with naturally large visible or audible effect; no isolated micro-marker continuation.

## Production rules

1. Exact current `main` is the only production truth.
2. One active lot per exact problem/domain.
3. Small current-main PRs only; re-check `main` and active PRs before push/PR/merge.
4. Publication-only commits are not new gameplay/visual truth.
5. Never merge long-lived specialist branches wholesale.
6. Prefer Paradigm/UrbIS/UrbIS3D, Brussels Mobility, STIB and official orthophoto/DTM/DSM; OSM complements but does not prove unresolved geometry or traffic semantics.
7. Preserve lawful provenance/licensing.
8. Evidence-only work must unlock material player-facing improvement within one or two lots; otherwise close/defer.
9. Green CI can still be rejected for negligible impact, broad scope, weak source truth or negative human recognition.
10. Substantive lots require deterministic player-facing/runtime evidence when applicable, human inspection, affected tests, branch hygiene and performance.
11. Pixel delta is evidence, not the objective; judge recognition, silhouette, proportions, material response, atmosphere, legibility, motion, continuity and feel.
12. Streaming coverage may not expand beyond the shipped four-cell Ixelles cluster until direct sustained human traversal QA is recorded.
13. Never rescue a failed impact gate by changing camera/FOV, enlarging an object beyond source truth, increasing contrast/emission unnaturally or lowering the threshold.

## Director next-integration priority

**There is no current open substantive PR worth integrating. #318, #319 and #320 are correctly closed by their own player-facing gates. The single highest-impact next integration candidate is a fresh exact-current-main, source-bounded street-level Midi/Fonsny recognition correction that preserves the readable authored station frontage. If Centre cannot identify such a positive subset before implementation, it must pivot to one large exposed Bourse discrepancy rather than another micro-fix. In parallel, #314 streaming remains production truth but frozen until sustained human traversal QA.**
