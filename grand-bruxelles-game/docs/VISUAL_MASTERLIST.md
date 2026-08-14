# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. Optimize player-perceived Brussels quality, not commit count.

Current production checkpoint: `557210f059b8dbc00b4060a4cd30c72154b55fa7` (#305 playable Brussels cell streaming runtime). Prior infrastructure foundation: `abb9149f109dd41bba864d42cbfc9a3821a85e1e` (#303 near-player collision tier + warm asset cache), followed by publication-only `8dc6c23379bcf2c55c0553dc668f14476571bcae` before #305.

## North star

Judge three horizons: **3-second recognition**, **30-second immersion**, **10-minute playable continuity**. Use **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient.

## Director checkpoint — 2026-08-14 22:07 Brussels

### Fresh production truth

- **#305 playable Brussels cell streaming runtime** — `shipped_10min_continuity_gain`. The validated streamer is now attached to the real playable world. It follows the on-foot player or actually driven vehicle, keeps Ixelles dormant from Midi, predictively prefetches the shipped Ixelles micro-slice, activates official DTM collision only near the player, unloads beyond hysteresis, and preserves direct `spawn=ixelles` without duplicate geometry. Exact-head Cell Streaming Probe, Mobile Playability, Game CI, Web, Photo Match, Performance, tests and Branch Hygiene are green. Human long-traversal/Web-phone sanity remains a follow-up QA debt; do not add a second streaming feature before that review.
- **#303 near-player collision tier + warm asset cache** — `shipped_performance_foundation`. Heavy collision is separated from visual prefetch and streamed resources remain warm across unload/reload cycles.
- **#302 predictive cell streaming scheduler** — `shipped_infrastructure_foundation`. Hysteresis, lookahead and bounded operations were validated against the real Ixelles manifest.
- **#304** — `closed_superseded_without_merge`; stale parallel runtime attachment replaced cleanly by #305.
- **#301** — `closed_superseded_without_merge`; roadmap became historical after #302/#303/#305 implementation.
- **#298 Mission GPS** — `closed_without_merge_core_gate_failed`. General gates were green, but the dedicated real-road contract could not truthfully resolve Grand-Place -> Bourse. No fabricated road edges or weakened tests.

### Active Director decisions

- **#299 STIB Suède / Zweden** — `highest_value_active_runtime_candidate`. The official stop point + bilingual identity source gate is green. Evidence work is finished. Rebuild from exact current main and land only the smallest visible runtime lot: real stop identity plus queue/boarding behavior using existing `NpcTransitStop`/`NpcAgent`; no invented shelter, timetable or service semantics. Runtime now or close.
- **#295 Atomium RoadArea** — `runtime_now_or_close`. 24.28% official RoadArea wedge coverage already answered the evidence question. One exact-current-main deterministic runtime A/B is allowed, must coexist with shipped #289 context, then accept/reject immediately.
- **#11/#2** — long-lived specialist workspaces only; never merge wholesale.

## Active ownership map

- **Centre Vertical Slice** — owns Bourse/Centre/Midi visible slice. No active Centre visual PR. Highest unowned visible target remains Midi station/STIB/public-space identity; Bourse large structure second.
- **Visual Assets + Atmosphere** — no active production PR. Next shared lot must be unmistakably Brussels-specific, reusable and visibly placed; no generic filler or micro-materials.
- **Ixelles Runtime Slice** — #305 now owns the shipped streaming/continuity foundation. No competing streaming lot. After human traversal sanity, next Ixelles work must be one large same-cell identity cue rather than distant micro vegetation.
- **Laeken Hero Impact** — #295 owns exactly one RoadArea runtime A/B; no further source research.
- **STIB gameplay** — #299 owns Suède / Zweden stop + visible boarding flow only.
- **Director maintenance** — streaming now stabilizes; navigation #298 is closed. Traffic/Living City/missions/saves advance only for regressions or unusually high perceived-impact opportunities.

## Top 5 perceived-quality bottlenecks

1. **Midi station + STIB/public-space identity** — `3sec_30sec_high`. Fonsny mass/brick and Living City help, but the station still lacks unmistakable Brussels transport identity.
2. **Bourse roof/interior/frontage coherence** — `3sec_high`. Structural/collision fixes shipped, yet landmark reading remains simplified.
3. **Human proof of seamless 10-minute continuity** — `10min_high`. #305 is technically green, but real Web/phone traversal from core city toward streamed Ixelles still needs sustained sanity for pop, duplicate geometry, collision transitions and frame feel.
4. **Ixelles local identity density** — `30sec_medium_high`. Direct access + Stassart remain sparse; #294 proved distant trees were too weak.
5. **Secondary Brussels detail/reuse** — `3sec_30sec_medium_high`. Grand-Place secondary façades/edges/furniture, reusable STIB/signage vocabulary, atmosphere and sound remain comparatively simplified.

## Stream health

- **Centre** — `healthy_idle_but_priority_starved`; next free substantive slot should return here.
- **Visual Assets + Atmosphere** — `healthy_idle`; avoid low-impact filler.
- **Ixelles** — `productive_foundation_shipped`; freeze streaming expansion and validate real traversal before more systems work.
- **Laeken** — `drifting_if_more_evidence`; #295 runtime A/B now or close.
- **STIB #299** — `source_gate_productive_runtime_due`; runtime now or close.
- **Director maintenance** — `stabilization_mode` after #305.
- **Navigation** — `closed_truthfully_blocked`; revisit only as fresh source-supported work.

## Shared priorities

1. **#299 runtime Suède / Zweden stop + boarding flow**, because it directly attacks the highest Midi/STIB identity gap and reuses existing NPC transit behavior; close if it cannot become visibly useful immediately.
2. **One large source-backed Centre recognition lot** — Midi station/entrance/public-space first, Bourse structure second.
3. **#295 exact-main Atomium RoadArea runtime A/B**, then immediate accept/reject.
4. **Direct 10-minute Web/phone play review** across movement, mobile UI, Living City/police, vehicle A/B, save/load and #305 streaming transitions.
5. **One larger Ixelles identity cue** after streaming sanity is confirmed.
6. **Reusable Brussels-specific transit/signage/furniture/atmosphere cue** with proven visible placement.

## Production rules

1. Exact current `main` is the only production truth.
2. One active lot per exact problem/domain.
3. Small current-main PRs only; re-check `main` and active PRs before push/PR/merge.
4. Publication-only commits are not new gameplay/visual truth.
5. Never merge long-lived specialist branches wholesale.
6. Prefer Paradigm/UrbIS/UrbIS3D, Brussels Mobility, STIB and official orthophoto/DTM/DSM; OSM complements but does not prove unresolved geometry or traffic semantics.
7. Preserve lawful provenance/licensing.
8. Evidence-only work must unlock material player-facing improvement within one or two lots.
9. Green CI can still be rejected for negligible impact, broad scope, weak source truth or missing human evidence.
10. Substantive lots require player-facing/runtime evidence, human inspection when applicable, affected tests, branch hygiene and performance.
11. Pixel delta is evidence, not the objective; judge recognition, silhouette, proportions, material response, atmosphere, legibility, motion, continuity and feel.

## Director next-integration priority

**#299 is now the single highest-impact active next integration candidate, but only if it immediately becomes a small exact-current-main player-facing STIB lot. Its source gate is already done; another evidence-only commit is grounds to close it. If #299 stalls, the slot returns directly to a compact high-impact Midi/Bourse recognition PR. #295 is runtime-now-or-close, and #305 streaming must stabilize rather than expand.**
