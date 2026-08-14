# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. Optimize player-perceived Brussels quality, not commit count.

Current production checkpoint: `8dc6c23379bcf2c55c0553dc668f14476571bcae` (publication-only Web commit). Latest substantive production below it: `abb9149f109dd41bba864d42cbfc9a3821a85e1e` (#303 near-player collision tier + warm asset cache). Earlier substantive anchors remain #297 mobile mission/save access, #296 visible Living City/police, #293 Bourse collision sync, #290 mobile/vehicle playability, #289 Atomium context, #287 Bourse structure, #280 Grand-Place granite and prior landmark/material lots.

## North star

Ask every run: **what gives the game away beside a real Brussels photo or observation in the first three seconds, thirty seconds, and ten minutes?**

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient.

## Director checkpoint — 2026-08-14 22:06 Brussels

### Fresh production truth

- **#302 predictive Brussels cell streaming** — `shipped_infrastructure_foundation`. Clean-room scheduler, hysteresis, bounded operations and real Ixelles manifest lifecycle were validated. Useful only insofar as it unlocks seamless playable geography.
- **#303 near-player collision tier + warm asset cache** — `shipped_10min_performance_foundation`. Exact-head test, Cell Streaming Probe, Web, Game CI, Ixelles direct-player, Photo Match, Performance and Branch Hygiene were green. Visual prefetch can remain light while heavy DTM collision activates near the player; warm resources reduce reload churn.
- **#304** — `closed_superseded_without_merge`; parallel runtime attachment was rebuilt cleanly as #305 after #303 changed the same backend.
- **#301** — `closed_superseded_without_merge`; roadmap became obsolete after #302/#303 implementation. Keep only as historical context.
- **#298 Mission GPS** — `closed_without_merge_core_gate_failed`. General gates were green but the dedicated real-road contract repeatedly failed because committed OSM data could not truthfully resolve Grand-Place -> Bourse. Do not fabricate edges or weaken the test.

### Active Director decisions

- **#305 production cell streaming runtime** — `single_high_value_10min_candidate_pending_final_gate`. Exact-current-main small integration attaches the already-validated streamer to the real playable world, follows on-foot/driven-vehicle observer state and streams the shipped Ixelles cell. Dedicated production lifecycle, Mobile Playability, Game CI, Web, Photo Match, tests and Branch Hygiene are green on head `3012b396...`; Performance is still pending at this checkpoint. Do not merge until Performance is green and the final human/runtime sanity check confirms no visible pop/duplicate Ixelles geometry or broken direct spawn.
- **#299 STIB Suède / Zweden** — `source_gate_finished_runtime_now_or_close`. Official stop identity/point gate is green. No more evidence commits. Next commit must expose the real stop plus visible queue/boarding behavior from existing systems, rebuilt on exact current main; otherwise close.
- **#295 Atomium RoadArea** — `evidence_clock_expired_runtime_now_or_close`. 24.28% wedge coverage already unlocked one runtime A/B. No more research. Rebuild on exact main, test against shipped #289, human-inspect, then accept/reject immediately.
- **#11/#2** — long-lived specialist workspaces only; never merge wholesale.

## Active ownership map

- **Centre Vertical Slice** — Bourse/Centre/Midi visible slice. No active Centre PR. Healthy but under-producing while infrastructure work dominates. Next Centre lot should target major Midi station/STIB/public-space identity first, large Bourse structure second.
- **Visual Assets + Atmosphere** — no active production PR. Needs a reusable Brussels-specific cue with exact visible placement; avoid generic props and micro-materials.
- **Ixelles Runtime Slice** — #305 temporarily owns Ixelles runtime continuity/streaming. No competing Ixelles visual lot until #305 resolves. Afterward choose one large same-cell identity cue, not distant micro vegetation.
- **Laeken Hero Impact** — #295 owns exactly one remaining RoadArea runtime A/B. No further evidence expansion.
- **Director maintenance** — streaming integration #305 temporarily owns the 10-minute continuity slot. Navigation #298 is closed; missions/saves/Living City otherwise stabilize rather than broaden.
- **STIB gameplay** — #299 owns Suède / Zweden stop + boarding flow only.

## Top 5 perceived-quality bottlenecks

1. **Midi station + STIB/public-space identity** — `3sec_30sec_high`. The living city and Fonsny mass help, but the station still lacks unmistakable Brussels transport identity.
2. **Bourse roof/interior/frontage coherence** — `3sec_high`. Structural/collision fixes shipped, but landmark reading remains simplified.
3. **Seamless playable geography + streaming proof** — `10min_high`. #302/#303 are only valuable if #305 makes real travel toward Ixelles stable without pop, duplication or performance regression.
4. **Ixelles local identity density** — `30sec_medium_high`. Direct access and Stassart remain sparse; #294 proved distant trees were too weak.
5. **Human gameplay QA + secondary Brussels detail** — `10min_30sec_medium_high`. #290/#296/#297 plus new streaming need sustained Web/phone play review; Grand-Place secondary façades/furniture and reusable transit cues remain simplified.

## Stream health

- **Centre** — `healthy_idle_but_priority_starved`; redirect next free substantive slot here after #305.
- **Visual Assets + Atmosphere** — `healthy_idle`; no low-impact filler.
- **Ixelles** — `temporarily_productive_via_streaming`; #305 is useful only if it reaches playable runtime safely.
- **Laeken** — `drifting_if_more_evidence`; runtime A/B now or close #295.
- **STIB #299** — `source_gate_productive_but_runtime_due`; runtime now or close.
- **Director streaming #305** — `high_value_pending_final_acceptance`; do not broaden beyond one real shipped Ixelles cell.
- **Navigation** — `closed_blocked_truthfully`; #298 may return only as a fresh source-supported lot.

## Shared priorities

1. **Finish or reject #305** after Performance + final runtime/human sanity. No second streaming feature until this production bridge is proven.
2. **One large Centre recognition lot** — Midi station/STIB/public-space first; Bourse structure second.
3. **#299 runtime Suède / Zweden stop + boarding flow**, or close if the player-facing effect cannot land immediately.
4. **#295 exact-main Atomium RoadArea runtime A/B**, then immediate accept/reject.
5. **One larger Ixelles identity cue** after #305 resolves.
6. **Direct 10-minute Web/phone play review** covering movement, mobile UI, Living City/police, vehicle A/B, save/load and streaming transitions.

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

**#305 is the single highest-impact next integration candidate because it converts the already-shipped streaming infrastructure into actual playable continuity toward Ixelles. It is not mergeable until Performance is green and final runtime sanity is positive. If #305 fails or becomes broad, close it and immediately return the substantive slot to a compact high-impact Midi/Bourse recognition lot. #299 and #295 are runtime-now-or-close; no more source-only expansion.**
