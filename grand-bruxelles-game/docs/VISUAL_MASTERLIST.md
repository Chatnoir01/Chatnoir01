# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. Optimize player-perceived Brussels quality, not commit count.

Current production checkpoint: `428fef342f426ba63067c6453e3319b3bbd347cb` (publication-only Web commit). Latest substantive player-facing merge below it: `ddff90d8f4552c62b8929fdd8c73b2b1cfbd0f5d` (#297 mobile mission/save/campaign access). Other fresh substantive production: `e7f8241db36bcd503e936af62ba388a53b8454b6` (#296 visible Living City/police) and `063bc99f8d45043b5eecb9ab1a8ab4856c991df7` (#293 Bourse collision sync).

## North star

At every zone ask: **what gives the game away beside a real Brussels photo or observation in the first three seconds?**

Optimize three horizons:
1. **3 seconds** — silhouette, proportions, materials, landmark/street identity, obvious placeholders.
2. **30 seconds** — signage, transit vocabulary, furniture, vegetation, motion, clutter, lighting and atmosphere.
3. **10 minutes** — controls, navigation, driving, believable PNJ/police reactions, missions/saves and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient.

## Director checkpoint — 2026-08-14 21:09 Brussels

### Fresh production truth

- **#297 mobile mission/save/campaign access** — `shipped_10min_access_gain`. Existing mission, wallet, quick-save, quick-load and new-game systems are now reachable through the mobile UI instead of remaining keyboard-hidden. This materially improves Web/phone continuity without changing mission economics or save format.
- **#296 visible Living City + police** — `shipped_30sec_10min_gain`. Existing NPC systems are finally exposed in the real world: bounded civilians and police at Midi/Bourse, real movement/collision, crowd reaction and visible police investigation/pursuit/de-escalation. This is a stronger use of existing systems than adding another hidden AI layer.
- **#293 Bourse collision sync** — `shipped_blocking_bug_fix`. Collision is rebuilt after the source-bounded wall reveal so invisible stale walls no longer survive where the final visible Bourse mesh is open.
- **#290 mobile playability + vehicle A/B + collision completion** — `shipped_broad_gameplay_gain`, still under human phone/Web and drive-feel debt. Do not resume broad feature expansion without a concrete regression or unusually high-value opportunity.
- **#289 Atomium green-block context** — `shipped_major_context_gain`, human accepted. Official Paradigm LandCover improved the direct-player foreground by 14.93% >3 RGB.
- **#287 Bourse front-depth guard** — `shipped_medium_structure_gain`, final direct witness 4.45% >3 RGB.

### Active Director decisions

- **#298 Mission GPS** — `high_value_blocked`. Scope is compact (workflow + minimap + test) and Game CI/Web/Photo Match/Performance/Branch Hygiene are green, but the dedicated runtime gate fails because the committed OSM graph cannot resolve Grand-Place -> Bourse. Do not fabricate road edges or weaken the test. Repair truthfully or degrade unsupported routes explicitly. Rebuild/rebase on exact current main before integration.
- **#295 Atomium RoadArea context** — `source_gate_passed_one_runtime_lot_allowed`. Official RoadArea covers **24.28%** of the accepted Atomium player wedge versus the 8% unlock threshold. Evidence question is answered: no more research expansion. Next step must be exact-current-main deterministic runtime A/B and human inspection; reject if it conflicts with #289 or requires invented road/material semantics.
- **#294 Ixelles Louise trees** — `closed_without_merge_impact_rejected`. Source contract was good, but exact 1280×720 A/B produced only **3,811 meaningful pixels >=12/255**, bbox **113×67**, below required 15,000 pixels and 120×80. Do not rescue by enlarging trees, moving camera or relaxing thresholds.
- **#288 LimboHSM** — `closed_without_merge_low_visible_value`. Technical compatibility was proven, but #296 now exposes useful police/civilian behavior with the existing authoritative systems. No new dependency until a tiny current-main experiment demonstrates an obvious player-visible behavior advantage.

### Production anchors

#280 Grand-Place granite, #272/#265 white-stone identity, #260/#257 Grand-Place LoD2 masses, #258 Ixelles Stassart frontage, #254 Atomium framing, #243 bilingual plaque, #242 Ixelles direct entry, #241 Bourse roof winding, #239 Ixelles runtime, #230 Atomium direct entry, #226 reflections, #217 Bourse portico, #215 Midi/Fonsny brick and #214 Atomium stainless remain foundations.

Long-lived #2/#11 remain specialist workspaces only; never merge wholesale.

## Active ownership map

- **Centre Vertical Slice** — owns Bourse/Centre/Midi visible slice. No active Centre visual production PR. Priority remains one materially large authoritative Bourse roof/interior/envelope correction or real Midi station/entrance/STIB/public-space cue.
- **Visual Assets + Atmosphere** — no active production PR. Next shared lot needs exact visible placement, Brussels-specific recognition and reuse; no generic props or micro-materials.
- **Ixelles Runtime Slice** — #294 closed for weak impact. Redirect to a larger same-cell identity cue: major frontage/material family, substantial streetscape proportion cue, or unmistakable transport/public-space identity. No more distant micro vegetation.
- **Laeken Hero Impact** — #295 owns the RoadArea context question. One runtime A/B lot allowed because the source gate passed strongly; then accept/reject and move on.
- **Impact Director maintenance** — #298 navigation is temporarily Director-owned because it is a high-value 10-minute opportunity with a real blocker. Traffic/Living City/missions/saves otherwise remain maintenance-only after #296/#297.
- **AI lab** — no active production candidate after #288 closure.

## Top 5 perceived-quality bottlenecks

1. **Midi station + STIB/public-space identity** — `3sec_30sec_gap_high`. Fonsny mass/brick and Living City help, but the station entrance/transport identity still reads weakly as Brussels.
2. **Bourse roof/interior/frontage coherence** — `3sec_visual_gap_high`. #287/#293 fixed real structure/collision defects, but landmark reading remains simplified.
3. **Truthful mission navigation and spatial continuity** — `10min_gap_high`. #298 is potentially high-value, but current OSM graph cannot truthfully route Grand-Place -> Bourse.
4. **Ixelles local identity density** — `30sec_identity_gap_medium_high`. Direct access + Stassart remain too sparse; #294 proved distant trees are not enough.
5. **Grand-Place architectural/detail coherence + human gameplay QA** — `3sec_30sec_10min_gap_medium_high`. Core mass/material/ground are stronger, while secondary façades/edges/furniture remain simplified and #290/#296/#297 still need sustained human Web/phone play review.

## Stream health

- **Centre** — `healthy_idle_high_value_target_available`.
- **Visual Assets + Atmosphere** — `healthy_idle`.
- **Ixelles** — `redirected_after_micro_rejection`; source discipline good, impact selection needs improvement.
- **Laeken** — `productive_but_evidence_clock_running`; #295 must become runtime A/B now or close.
- **Director maintenance / GPS #298** — `high_value_but_blocked_real_route_gap`.
- **Living City / missions / saves** — `fresh_player_facing_progress`; #296/#297 are substantive gains, now stabilize rather than broaden.
- **AI** — `closed_low_visible_value` after #288.

## Shared priorities

1. **Truthful compact GPS repair for #298** if the existing committed road graph can support it without invented connectivity; otherwise narrow/degrade unsupported routing and do not merge false guidance.
2. **One large source-backed Centre correction** — Midi identity first if a strong station/STIB cue is available; Bourse structure second.
3. **#295 exact-current-main Atomium RoadArea runtime A/B**, then immediate accept/reject.
4. **Ixelles larger same-cell identity cue** after #294 rejection.
5. **Reusable Brussels transit/signage/furniture/atmosphere cue** with proven visible placement.
6. **Direct human Web/phone 10-minute play review** across #290/#296/#297 production before adding more gameplay complexity.

## Production rules

1. Exact current `main` is the only production truth.
2. One active lot per exact problem/domain.
3. Small current-main PRs only; re-check `main` and active PRs before push/PR/merge.
4. Publication-only commits are not new gameplay/visual truth.
5. Never merge long-lived specialist branches wholesale.
6. Prefer Paradigm/UrbIS/UrbIS3D, Brussels Mobility, STIB and official orthophoto/DTM/DSM. OSM is complement, not proof for unresolved geometry or traffic semantics.
7. Preserve lawful provenance/licensing.
8. Evidence-only work is allowed only when it can unlock material player-facing improvement within one or two lots.
9. Green CI can still be rejected for negligible impact, weak source truth, broad scope or missing human evidence.
10. Substantive lots require deterministic player-facing evidence, human inspection, relevant tests, branch hygiene and performance when applicable.
11. Pixel delta is evidence, not the objective; judge recognition, silhouette, street proportions, material response, atmosphere, legibility, motion and gameplay feel.

## Director next-integration priority

**#298 is currently the single highest-impact next integration candidate because truthful mission navigation compounds the 10-minute value of the newly exposed missions/saves and Living City, but it is NOT mergeable while Grand-Place -> Bourse fails. If that route cannot be supported truthfully from committed source geometry, Centre regains top integration priority with one compact Midi/Bourse recognition gain. #295 gets one runtime A/B lot only; Ixelles must abandon micro-context work.**
