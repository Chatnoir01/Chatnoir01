# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. Optimize player-perceived Brussels quality, not commit count.

Current production checkpoint: `ae7d06e37b439ee6e5bd21883d9ad7169b7bb001` (#339 documentation-only). Latest positive player-facing visual gain remains `1699dbbfa3eb4224f50f3879326c935f0eebe271` (#323 Midi concrete + glass-block identity). Latest substantive runtime correction is #333: Ixelles DTM collision north/south orientation parity. #331/#332/#334 are source/data foundations only and do not authorize additional runtime coverage.

## North star

Judge three horizons: **3-second recognition**, **30-second immersion**, **10-minute playable continuity**. Use **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI, source correctness and pixel delta are evidence, never the objective.

## Director checkpoint — 2026-08-15

### Fresh production truth

- **#333 Ixelles DTM PhysicsServer orientation fix** — `shipped_blocking_runtime_regression_fix`. A real production defect was reproduced: rendered/source DTM and Godot collision diverged by **11.177695 m** at an asymmetric sample because HeightMapShape3D rows were mirrored north/south. The fix reverses only collision rows, preserving source heights, render geometry, Lambert transform and vertical datum. Post-fix six asymmetric PhysicsServer probes reached **0.000065 m max delta (0.065 mm)**, inside the 2 mm hard gate.
- **#334 neighbor DTM shared-datum candidates** — `shipped_data_only_not_runtime_approval`. Three neighboring 2 m DTM contracts use the same absolute seed reference **62.393423 m**. Official source seam checks report zero source/shared-relative seam drift across 1,004 paired samples. Neighbor terrain remains `runtime_approved=false` / `promote_runtime=false`.
- **#331 neighbor strong-height cross-check** and **#332 source-space DTM collision parity** — `shipped_evidence_only`. Useful source foundations only; no new building or terrain runtime authority.
- **#323 Midi concrete + glass-block family** — `shipped_positive_human_visual_gain`. Existing readable Fonsny geometry preserved; deterministic 1280×720 witness changed **4.8870% >3 RGB / 2.0135% >8 RGB** with positive human full-frame verdict.
- **#314 Ixelles four-cell streaming cluster** — `shipped_10min_coverage_gain_with_unpaid_human_QA_debt`. One seed cell has real DTM/height runtime; three neighbors remain plan-only. This remains the maximum authorized coverage.

### Fresh rejects / blocked paths

- **#340 authored public-space ambience** — `closed_without_merge_human_audio_gate_unavailable_not_aesthetic_reject`. Runtime-first procedural PCM was mounted by autoload with no third-party recording and no claimed official STIB/MIVB signal, announcement, timetable, service frequency or vehicle schedule. A real initial import red was reproduced and fixed by removing a `class_name`/autoload collision without tuning audio parameters or evidence thresholds. Exact head `ce5cf7581423daf5f524e05f4b4f3ae9e900abc0` is green on general tests, Game CI, Branch Hygiene, Performance Baseline, Web Export, Photo Match QA, Visible Living City and dedicated Public Space Audio. Deterministic artifact `brussels-public-space-audio-evidence` id `9241843698`, Actions digest `sha256:58ebc0a6b54f4491daa95691704e6e635afee3600ed817416b9e052ed1f60362`, contains the exact runtime PCM as a 30 s stereo PCM16 22,050 Hz WAV (`sha256:03db7fd7d815ddb5ec58cc8882123433092c0f8032847d2042cda8a20334a4d7`; PCM digest `7f97aa9f45ebeb5adba7b23541c293e192ae9a7926a2e1c4b539d9818036fada`; RMS 0.045091, peak 0.173309, active ratio 0.843707). Evidence integrity is strong, but **no human listening verdict is available in the current execution environment**. Numeric loudness/activity cannot establish Brussels specificity, naturalness, fatigue or aesthetic quality. Preserve #340 as a technically audition-ready witness; do not call it a PASS and do not open a competing ambience implementation. Promotion requires genuine human audition from a fresh exact-current-main lot or direct review of this exact witness.
- **#338 Bourse / Beurs seven-entrance bilingual identity** — `closed_without_merge_zero_player_frame_effect`. Source/runtime contract was valid: seven official City of Brussels / STIB-MIVB published entrance anchors, bilingual identity, no invented service/shelter semantics. Exact-head CI was broadly green, including dedicated visual, Game CI, Web Export, Performance, Photo Match and Branch Hygiene. Evidence integrity was strong: one source-locked production scene, **65 dynamic nodes frozen**, then only identity visibility toggled. Downloaded artifact `bourse-metro-identity-visual-evidence` (`sha256:a35aba9c32a281e0fd49af89d6d20a728a63ee75ce9994dab71e6a2794c0532c`) measured **0 / 921,600 pixels >3 RGB and >8 RGB**; direct inspection found before/after identical because none of the seven blades was naturally visible from the legitimate player-facing camera. Preserve the seven-entry source evidence historically. Do not rescue by moving camera, enlarging markers, changing anchors, increasing emission/contrast or lowering thresholds.
- **#336 east-cell shared-datum DTM runtime pilot** — `closed_without_merge_director_freeze_and_domain_gate_failure`. It attempted terrain promotion before sustained four-cell traversal QA was recorded and failed the dedicated seam/PhysicsServer gate; rendered seam evidence was skipped. Do not weaken thresholds or reopen this branch.
- **#335 overcast** and **#329 post-rain atmosphere** — closed. Generic atmosphere did not produce a strong enough human-readable benefit; #329 also demonstrated why dynamic-scene A/B must freeze or mask moving actors.
- **#328/#325 Midi micro-detail/material passes** — too small. **#326/#322/#312** — human-negative despite large deltas. The Fonsny material/frame/LoD2 replacement loop is exhausted.
- **#318/#319 Bourse hidden/shading paths**, **#320 isolated STIB marker**, **#316/#310 Atomium ground context**, **#313 generic Ixelles slab**, **#294 tree micro-cue** remain closed low-return paths.

## Active ownership map

- **Centre Vertical Slice** — Bourse/Centre/Midi visible slice. No active runtime PR. Next lot must be a fundamentally broader **Midi arrival/forecourt/transport-context** cue on readable geometry, or one large exposed Bourse discrepancy. No more Fonsny material/frame micro-iterations.
- **Visual Assets + Atmosphere** — shared PBR/materials/furniture/signage/vegetation/lighting/weather/audio. No active runtime PR. #340 is technically audition-ready but human-unresolved, so **do not create a second competing public-space ambience implementation**. Either obtain a genuine human verdict on the exact #340 witness from a fresh current-main lot, or pivot to a different naturally broad shared cue.
- **Ixelles Runtime Slice** — Ixelles identity and shipped four-cell coverage. **Infrastructure hard-frozen.** No fifth cell, no neighbor terrain promotion, no neighbor building extrusion until sustained human Web/phone traversal of #314 is recorded.
- **Laeken Hero Impact** — Atomium/Heysel presentation. No active runtime PR. Stay idle unless a fundamentally different source-backed cue plausibly affects the real direct-spawn frame.
- **Director maintenance** — traffic/Living City/missions/saves/release only for concrete blockers/regressions. #333 qualifies; normal feature expansion does not.
- **#11/#2** — long-lived specialist workspaces only; never merge wholesale.

## Top 5 perceived-quality bottlenecks

1. **10-minute continuity proof for #314** — `very_high`. Perform sustained Web/phone traversal on foot and in a driven vehicle. Verify prefetch/pop, plan-only boundaries, collision-tier transitions after #333, unload/reload hysteresis, duplication, direct-spawn return and sustained performance/memory.
2. **Bruxelles-Midi station arrival / transport identity** — `3sec_high`. #323 is still the last positive visual gain. Next Centre change must make the place read more clearly as Bruxelles-Midi without another small material/frame pass.
3. **Bourse exposed roof/interior/frontage coherence** — `3sec_high`. Only a visibly exposed structural/silhouette/frontage issue qualifies. #338 proves that correct transit anchors are worthless if they are outside the legitimate player frame.
4. **Ixelles local identity density inside existing coverage** — `30sec_medium_high`. Coverage has outpaced recognisable place identity; improve the same cells before expanding them.
5. **Reusable Brussels atmosphere / transit / bilingual / audio vocabulary** — `30sec_medium_high_human_gate`. #340 proves deterministic authored audio can reach runtime and Web cleanly, but human audition is mandatory before promotion. Prefer an exact witness that can actually be listened to, or a different cue with broad natural exposure.

## Stream health

- **Centre** — `healthy_but_needs_new_problem_class`. Fonsny micro-iteration loop is exhausted; move to station-arrival context or Bourse.
- **Visual Assets + Atmosphere** — `technically_productive_human_gate_blocked`. #340 produced a deterministic runtime-identical audio witness with broad CI green, but the current execution environment cannot perform the required human listening gate. This is not evidence of bad audio. Do not fork another ambience branch; seek real audition or pivot.
- **Ixelles** — `high_technical_progress_but_scope_frozen`. #333 was a valuable production regression fix; #331/#332/#334 are foundations only; #336 proved promotion is premature.
- **Laeken** — `source_disciplined_idle`. Staying idle is preferable to another zero-impact evidence chain.
- **Director maintenance** — `healthy`. Continue only blocker/regression work and release/10-minute validation.

## Shared priorities

1. **Run and record sustained human Web/phone traversal of the shipped four-cell Ixelles cluster, including #333 collision parity.**
2. **One fundamentally broader source-backed Midi arrival/forecourt/transport-context lot**, or pivot Centre to Bourse if no strong candidate exists.
3. **Resolve #340's human audio gate without duplicating implementation**: audition the exact deterministic 30-second witness in a suitable human-listening path, or defer audio and choose another broad shared cue.
4. **One large exposed Bourse correction** only with a pre-implementation player-frame visibility estimate and source contract.
5. **One recognisable same-coverage Ixelles identity cue** only after traversal QA; no new infrastructure.

## Production rules

1. Exact current `main` is the only production truth.
2. One active lot per exact problem/domain; small current-main PRs only.
3. Re-check `main` and active PRs before branch, push, PR and merge.
4. Publication-only and documentation-only commits are not new gameplay/visual truth.
5. Never merge long-lived specialist branches wholesale.
6. Preserve lawful provenance and fail closed on unresolved geometry/traffic semantics.
7. Evidence-only work must unlock meaningful player-facing runtime improvement within one or two lots; otherwise stop.
8. Green generic CI cannot override a failing dedicated domain gate, a zero/negative human player-facing result, or a missing required human sensory verdict.
9. Substantive lots require deterministic player-facing/runtime evidence, human inspection, affected tests, branch hygiene and performance when applicable.
10. Pixel delta and numeric audio metrics are evidence, not the objective; judge recognition, silhouette, proportions, materials, atmosphere, sound character, motion, continuity and feel.
11. **Ixelles coverage/infrastructure freeze:** #314 is the maximum authorized runtime coverage until sustained human traversal QA is recorded. #331/#332/#334 do not grant promotion authority.
12. Neighbor terrain promotion requires a fresh then-current-main PR after traversal QA, world-space seam parity, PhysicsServer parity, rendered seam evidence and direct human inspection.
13. Never rescue a failed gate by changing camera/FOV, enlarging beyond source truth, weakening physics/seam tolerances, increasing contrast unnaturally or lowering thresholds.
14. Preserve readable authored geometry when exact source geometry produces a less recognisable result.
15. Dynamic-scene A/B must freeze identical vehicle/PNJ/physics state or mask/isolate dynamic pixels.
16. **Player-frame exposure gate:** before implementing signage, furniture, entrance identity or small context objects, estimate whether the legitimate normal-player camera can naturally see them. Source correctness alone does not justify a lot that is projected outside the playable frame.
17. **Human sensory gate:** deterministic audio/image/runtime metrics can prove integrity and detect regressions, but cannot substitute for required human listening/visual/gameplay inspection. When the environment cannot perform the sensory gate, preserve the witness and close/defer rather than claim PASS or start a competing implementation.

## Director next-integration priority

**No open substantive PR is mergeable now. #340 is technically audition-ready but not human-approved; #338 is a correct zero-impact reject. The highest-value project action remains sustained Web/phone traversal of #314 with the shipped #333 collision fix. The single highest-impact next engineering candidate is a fresh exact-current-main Centre lot attacking a broad Bruxelles-Midi arrival/transport-context problem; if no defensible normal-distance candidate exists, pivot immediately to one large exposed Bourse discrepancy. Visual Assets should not fork another ambience implementation while #340's exact witness remains unauditioned. Ixelles infrastructure remains frozen.**
