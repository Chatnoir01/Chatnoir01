# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. Optimize player-perceived Brussels quality, not commit count.

Current production checkpoint: `2de6438c5038ba7f65397cd553fbaa2a03437d37` (Web publication-only). Latest substantive player-facing runtime is `9fa924d5048edf49c6b4a5f10368cb34c888251d` (#344 autonomous Living City showcase). Latest positive visual identity gain remains `1699dbbfa3eb4224f50f3879326c935f0eebe271` (#323 Midi concrete + glass-block). Latest blocking runtime correction remains #333 Ixelles DTM collision orientation parity.

## North star

Judge three horizons: **3-second recognition**, **30-second immersion**, **10-minute playable continuity**. Use **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI, source correctness and numeric deltas are evidence, never the objective.

## Director checkpoint — 2026-08-15

### Fresh production truth

- **#344 autonomous Living City showcase** — `shipped_30sec_and_10min_behavior_gain_needs_human_session_QA`. Reuses the already-shipped `NpcAgent` civilian/crowd/police systems at Midi and Bourse. After ~5.5 s in a populated zone, once per visited zone, an existing civilian flees, nearby civilians react, existing police respond, then the scene de-escalates and civilians return to their routines. The player is never the scripted target. No map/DTM/building/traffic geometry or new HUD chrome is added. Exact-head Visible Living City, general tests, Game CI, Web Export, Performance, Photo Match and Branch Hygiene are green. There is no dedicated human gameplay artifact, so long-session feel remains a human QA obligation rather than proven quality.
- **#323 Midi concrete + glass-block family** — `shipped_positive_human_visual_gain`. Existing readable Fonsny geometry preserved; deterministic 1280×720 witness changed **4.8870% >3 RGB / 2.0135% >8 RGB** with positive human full-frame verdict.
- **#314 Ixelles four-cell streaming cluster** — `shipped_10min_coverage_gain_with_unpaid_human_QA_debt`. One seed cell has real DTM/height runtime; three neighbors remain plan-only. This remains maximum authorized coverage.
- **#333 Ixelles DTM PhysicsServer orientation fix** — `shipped_blocking_runtime_regression_fix`. Render/source terrain and collision previously diverged by **11.177695 m**; reversing only collision rows reduced max measured error to **0.000065 m**.
- **#331/#332/#334** — `shipped_data_or_evidence_only`. Useful foundations only; no new terrain/building promotion authority.

### Closed / blocked low-return paths

- **#342 bilingual location HUD banner** — clean deterministic evidence but decorative UI chrome; existing bilingual location was already readable. Closed without merge.
- **#340 authored public-space ambience** — technically audition-ready, deterministic and CI-green, but no genuine human listening verdict. Not an aesthetic reject; do not build a competing ambience implementation.
- **#338 Bourse/Beurs entrance identity** — source-valid but **0 / 921,600** player-frame pixels changed because the cues were outside the legitimate camera. Closed.
- **#336 east-cell DTM runtime pilot** — closed: violated Ixelles freeze and failed dedicated seam/PhysicsServer gate.
- **#335/#329 generic atmosphere**, **#328/#325 Midi micro passes**, **#326/#322/#312 human-negative Midi geometry/material variants**, **#318/#319 Bourse hidden/shading paths**, **#320 isolated STIB marker**, **#316/#310 Atomium ground context**, **#313 generic Ixelles slab**, **#294 tree micro-cue** remain closed.

## Active ownership map

- **Centre Vertical Slice** — Bourse/Centre/Midi visible slice. No active runtime PR. Next lot: broad **Midi arrival/forecourt/transport-context** cue on existing readable geometry, or one large exposed Bourse discrepancy. Do not duplicate #344 Living City orchestration.
- **Visual Assets + Atmosphere** — shared PBR/materials/furniture/signage/vegetation/lighting/weather/audio. No active runtime PR. #340 remains audition-ready/human-unresolved; no competing ambience. Prefer naturally broad world/audio cues, not HUD chrome or invisible micro-signage.
- **Ixelles Runtime Slice** — same-coverage identity + shipped four-cell runtime. **Infrastructure hard-frozen.** No fifth cell, neighbor terrain promotion or neighbor building extrusion until sustained human traversal is recorded.
- **Laeken Hero Impact** — Atomium/Heysel presentation. Stay idle unless a fundamentally different source-backed cue plausibly affects the real direct-spawn frame.
- **Director maintenance** — traffic/Living City/missions/saves/release only for blocker/regression or unusually high perceived impact. #344 qualifies as a rare high-value orchestration gain; do not turn this into a chain of scripted encounters.
- **#11/#2** — long-lived specialist workspaces only; never merge wholesale.

## Top 5 perceived-quality bottlenecks

1. **10-minute human continuity proof of current production** — `very_high`. Traverse the shipped Ixelles four-cell cluster and also experience the new #344 Living City event in a normal session. Verify pop/prefetch, plan-only boundaries, collisions after #333, unload/reload, duplication, vehicle-following, sustained performance, and whether the autonomous incident feels believable rather than scripted/repetitive.
2. **Bruxelles-Midi station arrival / transport identity** — `3sec_high`. #323 remains the last positive visual identity gain. Next Centre lot must make the place read more clearly as Bruxelles-Midi without another small material/frame/HUD pass.
3. **Bourse exposed roof/interior/frontage coherence** — `3sec_high`. Only a visibly exposed structural/silhouette/frontage issue qualifies.
4. **Ixelles local identity density inside existing coverage** — `30sec_medium_high`. Improve the same cells before expanding them.
5. **Reusable Brussels atmosphere / transit / bilingual / audio vocabulary** — `30sec_medium_high_human_gate`. #340 can progress only after genuine audition; world cues must prove natural player exposure before coding.

## Stream health

- **Centre** — `healthy_but_needs_broader_visual_problem`. No active competing lot; remain on arrival/forecourt/transport-context or pivot Bourse.
- **Visual Assets + Atmosphere** — `technically_productive_but_human_gate_limited`. Avoid more decorative HUD and invisible markers; resolve #340 audition or choose another broad naturally exposed cue.
- **Ixelles** — `high_technical_progress_but_human_QA_overdue`. Infrastructure remains frozen.
- **Laeken** — `source_disciplined_idle`. Staying idle is better than another zero-impact chain.
- **Director maintenance / Living City** — `fresh_player_facing_progress_but_scope_now_frozen`. #344 is substantive and CI-clean; next action is human session QA, not another scripted incident feature.

## Shared priorities

1. **Run and record sustained human Web/phone session QA** covering #314 + #333 and the new #344 autonomous Living City event.
2. **One broad source-backed Midi arrival/forecourt/transport-context lot**, or pivot Centre to one large exposed Bourse discrepancy.
3. **Resolve #340 human audio gate without duplicating implementation**, or defer audio and choose another broad shared cue.
4. **One recognisable same-coverage Ixelles identity cue** only after traversal QA; no new infrastructure.
5. **No second autonomous scripted encounter lot** until #344 is judged in a real 10-minute session for repetition, disruption and believability.

## Production rules

1. Exact current `main` is the only production truth.
2. One active lot per exact problem/domain; small current-main PRs only.
3. Re-check `main` and active PRs before branch, push, PR and merge.
4. Publication-only and documentation-only commits are not substantive gameplay/visual truth.
5. Never merge long-lived specialist branches wholesale.
6. Preserve lawful provenance and fail closed on unresolved geometry/traffic semantics.
7. Evidence-only work must unlock meaningful player-facing improvement within one or two lots; otherwise stop.
8. Green generic CI cannot override a failing dedicated domain gate, zero/negative human result or missing required human sensory/gameplay verdict.
9. Substantive lots require deterministic player-facing/runtime evidence when practical, human inspection, affected tests, branch hygiene and performance.
10. Pixel/audio metrics are evidence, not the objective; judge recognition, silhouette, proportions, materials, atmosphere, sound character, motion, continuity and feel.
11. **Ixelles infrastructure freeze:** #314 is maximum authorized coverage until sustained human traversal QA is recorded.
12. Never rescue a failed gate by changing camera/FOV, enlarging beyond source truth, weakening tolerances, increasing contrast unnaturally or lowering thresholds.
13. Preserve readable authored geometry when exact source geometry produces a less recognisable result.
14. Dynamic-scene visual A/B must freeze identical vehicles/PNJs/physics or mask/isolate dynamic pixels.
15. Before signage/furniture/small context objects, prove natural player-frame exposure from a legitimate gameplay view.
16. Human sensory/gameplay inspection cannot be replaced by metrics alone.
17. Do not restyle already-clear HUD information unless legibility, hierarchy or gameplay understanding materially improves.
18. **Behavior orchestration gate:** autonomous showcase events must reuse existing behavioral systems, remain bounded, never script the player as target without design intent, recover to normal routines, and be judged for repetition/disruption in real session QA before any second event family is added.

## Director next-integration priority

**No open substantive PR is mergeable now. #344 is shipped and is a real 30-second/10-minute behavior gain, but it creates a fresh human-session QA obligation. Highest-value project action is now one sustained Web/phone play session that validates #314/#333 streaming/collision continuity and #344 Living City believability together. Highest-impact next engineering candidate remains a broad source-backed Centre arrival/forecourt/transport-context improvement at Bruxelles-Midi; if no naturally visible defensible candidate exists, pivot immediately to one large exposed Bourse discrepancy. Ixelles infrastructure and further scripted Living City expansion are frozen pending that session.**
