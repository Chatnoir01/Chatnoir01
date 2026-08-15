# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. Optimize player-perceived Brussels quality, not commit count.

Current production checkpoint: `725656583ce3afcbe35092416b9de14ff69c6512`. Latest player-facing visual gain remains `1699dbbfa3eb4224f50f3879326c935f0eebe271` (#323 Midi concrete + glass-block identity). Latest substantive runtime correction is #333: Ixelles DTM collision north/south orientation parity. #331/#332/#334 are source/data foundations only and do not authorize additional runtime coverage.

## North star

Judge three horizons: **3-second recognition**, **30-second immersion**, **10-minute playable continuity**. Use **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI, source correctness and pixel delta are evidence, never the objective.

## Director checkpoint — 2026-08-15

### Fresh production truth

- **#333 Ixelles DTM PhysicsServer orientation fix** — `shipped_blocking_runtime_regression_fix`. A real production defect was reproduced: rendered/source DTM and Godot collision diverged by **11.177695 m** at an asymmetric sample because HeightMapShape3D rows were mirrored north/south. The fix reverses only collision rows, preserving source heights, render geometry, Lambert transform and vertical datum. Post-fix six asymmetric PhysicsServer probes reached **0.000065 m max delta (0.065 mm)**, inside the 2 mm hard gate. This is the only recent Ixelles infrastructure lot that directly improves player continuity and safety.
- **#334 neighbor DTM shared-datum candidates** — `shipped_data_only_not_runtime_approval`. Three neighboring 2 m DTM contracts now use the same absolute seed reference **62.393423 m**. Official source seam checks report zero source/shared-relative seam drift across 1,004 paired samples. All neighbor terrain remains `runtime_approved=false` / `promote_runtime=false`.
- **#331 neighbor strong-height cross-check** — `shipped_evidence_only`. Cross-source UrbIS3D/DSM height evidence exists for neighboring Ixelles footprints but remains unmounted and does not authorize building volumes.
- **#332 source-space DTM collision parity** — `shipped_evidence_only`. Source topology parity is proven; it does not authorize Godot runtime promotion by itself.
- **#323 Midi concrete + glass-block family** — `shipped_positive_human_visual_gain`. Existing readable Fonsny geometry preserved; deterministic 1280×720 witness changed **4.8870% >3 RGB / 2.0135% >8 RGB** with positive human full-frame verdict.
- **#314 Ixelles four-cell streaming cluster** — `shipped_10min_coverage_gain_with_unpaid_human_QA_debt`. One seed cell has real DTM/height runtime; three neighbors remain plan-only. This remains the maximum authorized coverage.

### Fresh rejects / blocked paths

- **#336 east-cell shared-datum DTM runtime pilot** — `closed_without_merge_director_freeze_and_domain_gate_failure`. The stream attempted terrain promotion before sustained four-cell traversal QA was recorded. More importantly, exact head `b099d980c00af1343c6196260699ce2b9d877e93` failed the dedicated **Grand Bruxelles Ixelles East DTM Runtime** gate in the production seam/PhysicsServer step; the rendered seam capture was skipped. General tests, Game CI, Web Export, Performance, Photo Match, Branch Hygiene and generic streaming probe were green but cannot override the failing domain gate. Do not weaken seam/physics thresholds, bypass visible evidence or continue this branch.
- **#335 shared Brussels overcast atmosphere** — closed without merge. Do not reopen as another grading/weather iteration without a clearly stronger human-readable atmosphere result and deterministic frozen dynamic state.
- **#329 post-rain atmosphere** — closed: Bourse too subtle; Midi full-frame delta contaminated by moving-world differences. Dynamic-scene A/B must freeze or mask vehicles/PNJs.
- **#328/#325 Midi micro-detail/material passes** — closed as too small. **#326/#322/#312** — closed despite large deltas because human recognition worsened. The Fonsny material/frame/LoD2 replacement loop is exhausted.
- **#318/#319 Bourse hidden/shading paths**, **#320 isolated STIB marker**, **#316/#310 Atomium ground context**, **#313 generic Ixelles slab**, **#294 tree micro-cue** remain closed low-return paths.

## Active ownership map

- **Centre Vertical Slice** — Bourse/Centre/Midi visible slice. No active runtime PR. Next lot must be a fundamentally broader **Midi arrival/forecourt/transport-context** cue on readable geometry, or one large exposed Bourse discrepancy. No more Fonsny material/frame micro-iterations.
- **Visual Assets + Atmosphere** — shared PBR/materials/furniture/signage/vegetation/lighting/weather/audio. No active runtime PR. Prefer reusable multi-zone Brussels identity or lawful ambient/audio work. Dynamic actors must be frozen or masked for image evidence.
- **Ixelles Runtime Slice** — Ixelles identity and shipped four-cell coverage. **Infrastructure hard-frozen.** #336 is closed. No fifth cell, no neighbor terrain promotion, no neighbor building extrusion until sustained human Web/phone traversal of #314 is recorded.
- **Laeken Hero Impact** — Atomium/Heysel presentation. No active runtime PR. Stay idle unless a fundamentally different source-backed cue plausibly affects the real direct-spawn frame.
- **Director maintenance** — traffic/Living City/missions/saves/release only for concrete blockers/regressions. #333 qualifies as such a blocker fix; normal feature expansion does not.
- **#11/#2** — long-lived specialist workspaces only; never merge wholesale.

## Top 5 perceived-quality bottlenecks

1. **10-minute continuity proof for #314** — `very_high`. Perform sustained Web/phone traversal on foot and in a driven vehicle. Verify prefetch/pop, plan-only boundaries, collision-tier transitions after #333, unload/reload hysteresis, duplication, direct-spawn return and sustained performance/memory.
2. **Bruxelles-Midi station arrival / transport identity** — `3sec_high`. #323 is the last positive player-facing visual gain. Next Centre change must make the place read more clearly as Bruxelles-Midi without another small material/frame pass.
3. **Bourse exposed roof/interior/frontage coherence** — `3sec_high`. Only a visibly exposed structural/silhouette/frontage issue qualifies.
4. **Ixelles local identity density inside existing coverage** — `30sec_medium_high`. Coverage has outpaced recognisable place identity; improve the same cells before expanding them.
5. **Reusable Brussels atmosphere / transit / bilingual / audio vocabulary** — `3sec_30sec_medium_high`. Prefer cues with naturally broad visible or audible value across multiple zones.

## Stream health

- **Centre** — `healthy_but_needs_new_problem_class`. Recent Fonsny iteration family is exhausted; move to station-arrival context or Bourse.
- **Visual Assets + Atmosphere** — `healthy_reject_discipline`. Weather/material evidence needs deterministic frozen world state; pursue broader reusable cues.
- **Ixelles** — `high_technical_progress_but_scope_drift`. #333 was a valuable production regression fix. #331/#332/#334 are valid foundations, but they exceeded the Director freeze without paying the human traversal debt. #336 is therefore closed. Stop infrastructure now.
- **Laeken** — `source_disciplined_idle`. Staying idle is preferable to another zero-impact evidence chain.
- **Director maintenance** — `healthy`. Continue only blocker/regression work and release/10-minute validation.

## Shared priorities

1. **Run and record sustained human Web/phone traversal of the shipped four-cell Ixelles cluster, including the #333 collision fix.**
2. **One fundamentally broader source-backed Midi arrival/forecourt/transport-context lot**, or pivot Centre to Bourse if no strong candidate exists.
3. **One large exposed Bourse correction** only with strong projected player-frame value and source contract before coding.
4. **One recognisable same-coverage Ixelles identity cue** only after traversal QA; no new infrastructure.
5. **One reusable Brussels atmosphere/transit/audio cue** with deterministic uncontaminated evidence and multi-zone reuse.

## Production rules

1. Exact current `main` is the only production truth.
2. One active lot per exact problem/domain; small current-main PRs only.
3. Re-check `main` and active PRs before branch, push, PR and merge.
4. Publication-only commits are not new gameplay/visual truth.
5. Never merge long-lived specialist branches wholesale.
6. Preserve lawful provenance and fail closed on unresolved geometry/traffic semantics.
7. Evidence-only work must unlock meaningful player-facing runtime improvement within one or two lots; otherwise stop.
8. Green generic CI cannot override a failing dedicated domain gate.
9. Substantive lots require deterministic player-facing/runtime evidence, human inspection, affected tests, branch hygiene and performance when applicable.
10. Pixel delta is evidence, not the objective; judge recognition, silhouette, proportions, materials, atmosphere, motion, continuity and feel.
11. **Ixelles coverage/infrastructure freeze:** #314 is the maximum authorized runtime coverage until sustained human traversal QA is recorded. #331/#332/#334 do not grant promotion authority.
12. Neighbor terrain promotion requires a fresh then-current-main PR after traversal QA, world-space seam parity, PhysicsServer parity, rendered seam evidence and direct human inspection.
13. Never rescue a failed gate by changing camera/FOV, enlarging beyond source truth, weakening physics/seam tolerances, increasing contrast unnaturally or lowering thresholds.
14. Preserve readable authored geometry when exact source geometry produces a less recognisable result.
15. Dynamic-scene A/B must freeze identical vehicle/PNJ/physics state or mask/isolate dynamic pixels.

## Director next-integration priority

**No open substantive PR is mergeable now. #336 is closed because the dedicated east-terrain runtime gate failed and the Ixelles human traversal prerequisite remains unpaid. The highest-value project action is sustained Web/phone traversal of #314 with the shipped #333 collision fix. The single highest-impact next engineering candidate is a fresh exact-current-main Centre lot attacking a broad Bruxelles-Midi arrival/transport-context problem; if no defensible normal-distance candidate exists, pivot immediately to one large exposed Bourse discrepancy. Ixelles infrastructure remains frozen.**
