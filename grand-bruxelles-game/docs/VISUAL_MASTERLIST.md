# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. Optimize player-perceived Brussels quality, not commit count.

Current production checkpoint: `4a4ae52b1230f99ae1b836afa6fe4bbe7a97f287` (publication-only Web commit). Latest substantive player-facing merge: `131449b2aee9fcb29b1445e9fc1e4f5d51fbead3` (#314 Ixelles 2×2 source-backed streaming cluster). Prior focused source/tooling unblocker: `5f0fbd20ef6e001c6ba034ee19ee78da4def1629` (#309 Midi/Fonsny hole-aware UrbIS3D extraction).

## North star

Judge three horizons: **3-second recognition**, **30-second immersion**, **10-minute playable continuity**. Use **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI and large pixel delta are evidence, never the objective.

## Director checkpoint — 2026-08-15 00:09 Brussels

### Fresh production truth

- **#314 Ixelles 2×2 source-backed streaming cluster** — `shipped_10min_coverage_gain_with_human_qa_debt`. Production now registers four contiguous UrbIS cells: `bxl-e149000-n169000-s500`, `bxl-e149000-n169500-s500`, `bxl-e149500-n169000-s500`, `bxl-e149500-n169500-s500`. The original Ixelles cell keeps full DTM + strong-height runtime; three neighbors are plan-only official StreetSurface geometry. Neighbor building extrusion remains blocked without a strong-height contract; no fake terrain/vertical collision is introduced. Exact-head Cell Streaming, Game CI, tests, Branch Hygiene, Web Export, Photo Match and Performance were green. However this was merged after Director had frozen further streaming expansion pending human long-traversal validation, so **no fifth cell or new streaming feature is allowed until direct Web/phone traversal proves pop, memory, collision transitions and unload/reload behavior are acceptable**.
- **#312 Midi/Fonsny whole-building LoD2 replacement** — `closed_without_merge_human_recognition_reject`. Numeric A/B was huge: 637,967 pixels >3 RGB = **69.2238%**, 620,060 >8 RGB = **67.2808%**. Exact 3,051 WALLSURFACE+ROOFSURFACE source triangles were used. Human full-frame review rejected it because exact coarse LoD2 replaced a readable authored station frontage with fragmented low grey masses and made 3-second Bruxelles-Midi recognition worse. Do not revive whole-building replacement or rescue by camera/FOV/scale/material manipulation. #309 remains useful only for source-bounded subsets.
- **#313 Ixelles Stassart 131 street-facing identity** — `closed_without_merge_human_recognition_reject`. Source/runtime selectors passed and A/B changed 261,023 pixels >=12/255 with bbox `[657,0,1279,719]`, but the after image read as a large flat light/grey slab rather than recognisable heritage. Do not rescue by contrast/brightness alone. This confirms pixel-area gates must remain subordinate to recognition.
- **#309 Midi/Fonsny hole-aware UrbIS3D extractor** — `shipped_source_tooling_foundation`. Exact official building 1633645 remains available: 889 faces, 3,428 triangles, 13.6076 m source height, 852 WALLSURFACE + 34 ROOFSURFACE, Paradigm/UrbIS3D EPSG:31370 CC0 with locked package SHA-256 `a760fdff222ae9431113f82fe1c8f942a9fe2bda40e32064c627ae8d3a21110f`. Whole-building runtime is rejected; use only defensible Fonsny-facing/roof/envelope subsets that improve the readable station presentation.
- **#299 STIB Suède / Zweden** — `closed_without_merge_evidence_quota_expired`. Official bilingual stop-point source gate was green, but the stale branch remained source-workflow/fetch-tool only after repeated runtime-now-or-close direction. Preserve source evidence historically; any future STIB lot must be a fresh exact-current-main runtime PR with no new discovery phase.
- **#310 Atomium RoadArea** — remains `closed_without_merge_player_frame_zero`: hero QA 2.6837%, actual `spawn=atomium` player frame 0.0000%.

### Active Director decisions

- **#316 Atomium official sidewalk projection/runtime** — `single_active_laeken_candidate`. Exact-current-main projection gate passed. Downloaded artifact `sha256:147119027e8c6ee04eb6f7b34292a4d59ca8c253ff7ef895f7f1bf66ec7ed4d0`: 486 samples in the accepted player wedge, 67 sidewalk hits, only 1 overlapping shipped #289 Green Block, therefore **66 exclusive hits = 13.5802% exclusive sidewalk coverage**, above the 6% pre-runtime threshold. This same PR may now perform exactly one exact-source actual-player A/B. No further evidence phase, camera rescue, material exaggeration or invented curb/marking/asphalt semantics.
- **Centre / Midi after #312** — whole-building LoD2 is finished/rejected. Next Centre lot must either isolate a **source-bounded Fonsny-facing envelope/roof/massing correction** that preserves the readable authored frontage, or pivot to a large Bourse structural/roof/interior discrepancy. No additional extractor research first.
- **Ixelles after #314** — infrastructure expansion is now frozen. No fifth cell, no second streamer, no terrain/collision feature until direct human traversal QA. Player-facing Ixelles identity is still weak; future visual cue must be recognisable, not merely high-delta.
- **Visual Assets + Atmosphere** — #299 is closed. Stream is free for one reusable Brussels cue with proven placement and strong normal-distance recognition; no evidence-only STIB continuation and no duplicate Midi geometry.
- **#11/#2** — long-lived specialist workspaces only; never merge wholesale.

## Active ownership map

- **Centre Vertical Slice** — owns Bourse/Centre/Midi visible slice. No active runtime PR. Exclusive next problem: source-bounded Fonsny-facing Midi correction from #309 evidence, or large Bourse correction if no useful subset is defensible.
- **Visual Assets + Atmosphere** — owns shared PBR/materials/furniture/signage/vegetation/lighting/weather/audio. Currently unowned/free after closing stale #299; next lot must be runtime-first and reusable.
- **Ixelles Runtime Slice** — owns Ixelles identity and existing four-cell production cluster. **Streaming expansion is frozen** until human long-traversal QA; no competing infrastructure lot.
- **Laeken Hero Impact** — owns Atomium/Heysel hero presentation. **#316 is the only active Laeken problem** and has one authorized runtime A/B after a 13.58% exclusive projection pass.
- **Director maintenance** — traffic/Living City/missions/saves/release only for blocking regression or unusually high perceived-impact opportunity. Current maintenance priority is human validation of #314/#305 streaming continuity, not new features.

## Top 5 perceived-quality bottlenecks

1. **Midi station frontage / transport identity** — `3sec_very_high`. Whole-building LoD2 is technically exact but visually worse; the challenge is now a targeted source-bounded correction that preserves immediate station readability while replacing obvious placeholder massing where defensible.
2. **Bourse roof/interior/frontage coherence** — `3sec_high`. Landmark still reads simplified; only large source-backed structural/occlusion/roof improvements qualify after repeated micro-rejects.
3. **10-minute streaming continuity proof after #314** — `10min_high`. Four-cell production coverage is larger, but direct Web/phone traversal still owes proof for pop, plan-only transitions, memory/performance, DTM collision tiering, unload/reload and vehicle-following behavior.
4. **Ixelles local identity density** — `30sec_medium_high`. Streaming coverage expanded but identity did not. #294 and #313 both failed qualitative recognition; next cue must read as Ixelles/Brussels architecture or street identity, not generic geometry/color mass.
5. **Reusable Brussels public-space / transit / signage / atmosphere vocabulary** — `3sec_30sec_medium_high`. STIB bilingual identity, wayfinding, ambient sound and source-placed public-space cues remain high-reuse opportunities, but must start from exact placement and runtime effect rather than research-only PRs.

## Stream health

- **Centre** — `healthy_rejection_then_idle`. #312 correctly rejected a huge but harmful delta; now needs a targeted exact-main runtime correction, not more source tooling.
- **Visual Assets + Atmosphere** — `idle_after_evidence_cleanup`. #299 correctly closed for evidence drift; next lot should be reusable and immediately player-facing.
- **Ixelles** — `productive_but_overexpanded`. #314 is source-disciplined and fully green, but violated the prior stabilization freeze. Stop infrastructure growth and pay the human traversal/recognition debt before more coverage.
- **Laeken** — `productive_single_gate`. #316 passed a meaningful actual-player projection pre-gate and may take one runtime shot. Close if A/B is weak.
- **Director maintenance** — `stabilization_and_human_QA_due`. No new traffic/mission/save/streaming subsystem unless a concrete regression is found.
- **Navigation** — `closed_truthfully_blocked`; missing Grand-Place -> Bourse graph connectivity remains unresolved without fabrication.

## Shared priorities

1. **#316 exact-source Atomium sidewalk actual-player A/B**, because it is the only current exact-main integration candidate that has already cleared a strong visibility pre-gate. Merge only on positive human recognition/context verdict and full applicable gates.
2. **One source-bounded Fonsny-facing Midi correction** using #309 geometry evidence without wholesale replacement; if no defensible subset improves recognition, pivot Centre to Bourse.
3. **Direct 10-minute Web/phone traversal review of #314/#305 streaming** across all four cells, including vehicle following, plan-only boundaries, collision tier transitions, unload/reload and memory/performance feel. No fifth cell before this review.
4. **One recognisable Ixelles identity cue** inside shipped coverage, with qualitative human gate stronger than raw pixel area.
5. **One reusable Brussels transit/signage/atmosphere runtime cue** from exact placement truth; STIB source evidence may be reused historically, but future implementation must be fresh current-main and runtime-first.

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
10. Substantive lots require player-facing/runtime evidence, human inspection when applicable, affected tests, branch hygiene and performance.
11. Pixel delta is evidence, not the objective; judge recognition, silhouette, proportions, material response, atmosphere, legibility, motion, continuity and feel.
12. Streaming coverage may not expand beyond the shipped four-cell Ixelles cluster until direct sustained human traversal QA is recorded.

## Director next-integration priority

**The single highest-impact current integration candidate is #316 Atomium official sidewalk only because its exact-current-main projection gate already demonstrates 13.5802% exclusive actual-player-wedge coverage. It gets one runtime A/B and no further research. In parallel, the highest-impact unowned bottleneck remains Midi: Centre must now use #309 only for a targeted Fonsny-facing correction or pivot Bourse. #314 streaming is production truth but frozen for human stabilization; #299 is closed; #312 and #313 are qualitative human rejects and must not be revived unchanged.**
