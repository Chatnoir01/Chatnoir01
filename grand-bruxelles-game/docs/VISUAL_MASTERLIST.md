# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. Optimize player-perceived Brussels quality, not commit count.

Current production checkpoint: `a753e87649021614ac2a78a6016bb3e7f82eaa79` (publication-only Web commit). Latest substantive player-facing merge: `fc9d2c71f4c9ddda15ec011e023d1750bba37568` (#290 mobile playability + in-world vehicle A/B + collision fixes).

## North star

At every zone ask: **what gives the game away beside a real Brussels photo or observation in the first three seconds?**

Optimize three horizons:
1. **3 seconds** — silhouette, proportions, materials, landmark/street identity, obvious placeholders.
2. **30 seconds** — signage, transit vocabulary, furniture, motion, clutter, lighting and atmosphere.
3. **10 minutes** — controls, navigation, driving, believable PNJ/police reactions, missions/saves and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient.

## Director checkpoint — 2026-08-14 20:14 Brussels

### Fresh production truth

- **#290 mobile playability + in-world vehicle A/B + collision completion** — `shipped_broad_gameplay_gain`, `scope_rule_breached`, `human_playability_debt`. A real analog thumbstick, independent right-side touch camera, player/vehicle camera cycling and fast travel are now production. Both A current vehicle and B 60 Hz physical vehicle are present in the real main world. Runtime also completes missing PNJ/ambient Midi physical bodies and restores collision on two Grand-Place official LoD2 replacements. Exact-head checks were green: Mobile Playability, Game CI, Web Export, Performance, deterministic render, Photo Match, Grand-Place/Atomium/Ixelles/Bourse visual checks, traffic, mission/save and Branch Hygiene. However the PR mixed four independent domains in one 976-addition lot despite the Director scope gate. Do not repeat this pattern. No further mobile/vehicle/collision expansion until direct human phone/Web playability and vehicle A/B drive-feel are reviewed; revert/fix only if a concrete regression is found.

- **#289 Atomium official green-block context** — `shipped`, `major_context_gain`. Paradigm INSPIRE LandCover `LandCover.1038`, `GB` / zone verte, 54,537.55 m², EPSG:31370, CC-BY-4.0. Exact source polygon is terrain-following on the accepted DTM; no trees/species, collision, landmark pose or pavilion dimensions invented. Exact-head A/B changes 5.65% hero pixels and 14.93% direct-player pixels >3 RGB. Director downloaded and inspected the artifact (`sha256:2ad3da507add3c77bfce1b27acece60aabd6d4735b87caebaa268219c84267ba`); human accepted.

- **#287 Bourse front-depth guard** — `shipped`, `medium_structure_gain`. Final exact-head A/B measures 54,724 / 1,228,800 = 4.4535% pixels >3 RGB and 46,131 = 3.7542% >8 RGB. Official UrbIS3D WALLSURFACE behind the audited facade plane is preserved without invented geometry. Human accepted, but broader Bourse structure remains simplified.

- **#285 Grand-Place granite QA repair** — `shipped_qa`; #280 evidence debt closed after Director inspection of the real 1280×720 production A/B.
- **#283 modern player locomotion** — `shipped_gameplay_gain`; smoother camera-relative movement, stronger deceleration, reduced air control, coyote time and jump buffering are production.

### Production anchors

#280 Grand-Place granite, #272/#265 white-stone identity, #260/#257 Grand-Place LoD2 masses, #258 Ixelles Stassart frontage, #254 Atomium framing, #243 bilingual plaque, #242 Ixelles direct entry, #241 Bourse roof winding, #239 Ixelles runtime, #230 Atomium direct entry, #226 reflections, #217 Bourse portico, #215 Midi/Fonsny brick and #214 Atomium stainless remain foundations.

### Closed / archived paths

- #273 daylight Grand-Place illumination, #268 Atomium pavilion LoD2, #267 Midi station label and #269 Town Hall slate roof remain impact-rejected.
- #231 STIB stop vocabulary remains evidence-only until a real visible stop/furniture placement is proven.
- #275 Midi forecourt, #278 Ixelles Stéphanie 8, #261 Ixelles discovery remain history/evidence only.
- #223 Midi blue stone, #235 bins, #227 micro-material context, generic shopfront lots and #222 Bourse vault proxy remain rejected.
- #165 Bourse pediment, #182 Atomium support and #204 Ixelles collision parity were archived and closed as stale old-main evidence.
- #276/#277/#279 were closed as superseded. #286 is now also closed: its vehicle A/B is superseded by shipped in-world #290.
- Long-lived #2/#11 remain specialist workspaces only; never merge wholesale.

## Active ownership map

- **Centre Vertical Slice** — owns Bourse/Centre/Midi visible slice. #287 shipped; no active Centre production PR. Next lot must be a materially larger authoritative Bourse roof/interior/envelope correction or real Midi station/entrance/public-space cue.
- **Visual Assets + Atmosphere** — no active production PR. Next shared lot needs exact visible placement and strong Brussels-specific reuse.
- **Ixelles Runtime Slice** — no active production PR. Same-cell player-facing identity only; no stale terrain/collision research unless a current blocking bug is reproduced.
- **Laeken Hero Impact** — #289 shipped and healthy. No current production PR. Next lot must solve a different large pavilion/support/context discrepancy; do not immediately add more generic ground.
- **Impact Director maintenance** — #290 is now production and frozen for stabilization/human QA. Traffic/Living City/missions/saves remain maintenance-only unless a blocking regression appears.
- **AI lab #288** — only active gameplay lab. Technically green real LimboHSM pilot for one police + one civilian, but no production-visible behavior advantage yet; keep quarantined.

## Top 5 perceived-quality bottlenecks

1. **Bourse roof/interior/frontage coherence** — `3sec_visual_gap_high`. #287 helps, but the landmark still reads simplified. Highest clean current visual opportunity.
2. **Midi station + STIB/public-space identity** — `3sec_30sec_gap_high`. Fonsny brick is real, but entrance/transport/forecourt reading remains weak.
3. **Ixelles local identity density** — `30sec_identity_gap_medium_high`. Direct access + Stassart are not enough to sustain the neighborhood slice.
4. **Grand-Place architectural/detail coherence** — `3sec_30sec_gap_medium_high`. Massing/material/ground are stronger; openings, secondary façades, roof detail, edge context and furniture still reveal the game.
5. **Human-verified 10-minute feel** — `gameplay_qa_gap_high`. #290 substantially changed mobile controls, driving options and collision behavior, but direct human phone/Web playability and A-vs-B drive-feel are not yet Director-verified. Do not add more gameplay complexity until this is assessed.

## Stream health

- **Centre** — `productive_but_needs_larger_next_gain`.
- **Visual Assets + Atmosphere** — `healthy_idle`.
- **Ixelles** — `healthy_idle_but_under-dense`.
- **Laeken** — `productive`; #289 is the strongest fresh visual gain this cycle.
- **Mobile/vehicle/collision #290** — `shipped_high-impact_but_scope-drifted`; technically green, now stabilization-only pending human playability review.
- **AI #288** — `technically_green_low_visible-proof`; dependency/risk is not justified until visible NPC behavior improves in a small exact-current-main pilot.

## Shared priorities

1. **Large Bourse or Midi source-backed correction** — single highest-impact next integration candidate now that #290 is frozen for stabilization.
2. **Direct human phone/Web + vehicle A/B playability review of current #290 production** — QA/decision gate, not a new feature lot.
3. **Ixelles second substantial same-cell identity cue**.
4. **Reusable Brussels transit/signage/furniture cue with proven placement**.
5. **Grand-Place architectural edge/detail correction** only if large and source-backed.
6. **NPC/HSM pilot** only after visible multi-step behavior improvement is proven.

## Production rules

1. Exact current `main` is the only production truth.
2. One active lot per exact problem/domain.
3. Small current-main PRs only; re-check `main` and active PRs before push/PR/merge.
4. Publication-only commits are not new gameplay/visual truth.
5. Never merge long-lived specialist branches wholesale.
6. Prefer Paradigm/UrbIS/UrbIS3D, Brussels Mobility, STIB and official orthophoto/DTM/DSM. OSM is complement, not proof for unresolved geometry/traffic semantics.
7. Preserve lawful provenance/licensing.
8. Evidence-only work is allowed only when it can unlock material player-facing improvement within one or two lots.
9. Green CI can still be rejected for negligible impact, weak source truth, broad scope or missing human evidence.
10. Substantive lots require deterministic player-facing evidence, human inspection, relevant tests, branch hygiene and performance when applicable.
11. Pixel delta is evidence, not the objective; judge recognition, silhouette, street proportions, material response, atmosphere, legibility, motion and gameplay feel.

## Director next-integration priority

**Do not extend #290 further. Treat it as a shipped stabilization target. The next new integration should be one compact, materially large, source-backed Centre correction — Bourse first, Midi second — while current mobile/vehicle production receives human playability review. #288 remains quarantined until it proves an obvious visible NPC-behavior win.**
