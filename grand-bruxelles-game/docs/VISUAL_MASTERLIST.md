# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. Optimize player-perceived Brussels quality, not commit count.

Current production checkpoint: `97687095831f69f09517f5472ff73591eeceea25` (Director documentation merge). Latest substantive player-facing merge: `abbbf5379cd63000ae138cfbea3f7ee3534a7ec3` (#289 Atomium official green-block context). Latest publication-only playable Web commit before the Director docs: `cb22135552b31749923a77d211b23575b27834cb`.

## North star

At every zone ask: **what gives the game away beside a real Brussels photo or observation in the first three seconds?**

Optimize three horizons:
1. **3 seconds** — silhouette, proportions, materials, landmark/street identity, obvious placeholders.
2. **30 seconds** — signage, transit vocabulary, furniture, motion, clutter, lighting and atmosphere.
3. **10 minutes** — controls, navigation, driving, believable PNJ/police reactions, missions/saves and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient.

## Director checkpoint — 2026-08-14 20:13 Brussels

### Fresh production truth

- **#289 Atomium official green-block context** — `shipped`, `major_context_gain`. Paradigm INSPIRE LandCover `LandCover.1038`, `GB` / zone verte, 54,537.55 m², EPSG:31370, CC-BY-4.0. Exact source polygon is terrain-following on the accepted Atomium DTM; no trees/species, collision, landmark pose or pavilion dimensions are invented. Exact-head A/B changes 5.65% of hero pixels and 14.93% of direct-player pixels >3 RGB. Director downloaded the real artifact (`sha256:2ad3da507add3c77bfce1b27acece60aabd6d4735b87caebaa268219c84267ba`) and accepted the actual player view: foreground reads as a coherent green site while the Atomium silhouette and #254 framing remain intact.

- **#287 Bourse front-depth guard** — `shipped`, `medium_structure_gain`. Official UrbIS3D WALLSURFACE triangles behind the audited facade plane are no longer deleted merely for matching tangent/height/orientation. Intermediate head was correctly rejected at ~0.37% visual delta; final head `2f4c1a53a69a7670e1b536524059f6b933d67a15` materially improved to 54,724 / 1,228,800 = 4.4535% pixels >3 RGB and 46,131 = 3.7542% >8 RGB. Human inspection accepts the final correction, but broader Bourse structure remains simplified.

- **#285 Grand-Place granite QA repair** — `shipped_qa`. The #280 runtime stayed unchanged. Workflow now packages real 1280×720 before/after PNGs + logs; Director inspected the actual production A/B and found no obvious moiré, z-fighting, aggressive noise or architecture-readability regression. #280 evidence debt is closed.

- **#283 modern player locomotion** — `shipped_gameplay_gain`. Camera-relative normalized movement, stronger deceleration, reduced air control, coyote time and jump buffering are production while Brussels spawns, mobile compatibility and vehicle enter/exit remain intact.

### Production anchors

- #280 Grand-Place granite — 39.4694% >3 RGB / 37.7677% >8 RGB; human accepted.
- #272 Grand-Place 1786758 white stone — 5.4551% >3 RGB.
- #265 Town Hall white stone — 6.2901% >3 RGB.
- #260 Grand-Place LoD2 1786758 — 7.0665% >3 RGB.
- #257 Grand-Place LoD2 1655673 — ~11.07% >3 RGB.
- #258 Ixelles Stassart 124 — 111,611 direct-player pixels >=12/255; unresolved-height buildings remain absent.
- #254 Atomium 48° direct framing — ~43.08% >8 RGB.
- #243 bilingual plaque, #242 direct Ixelles entry, #241 Bourse roof winding, #239 Ixelles compact runtime, #230 Atomium direct entry, #226 reflections, #217 Bourse white-stone portico, #215 Midi/Fonsny brick and #214 Atomium stainless remain foundations.

### Closed / archived paths

- #273 daylight Grand-Place illumination — impact rejected; revisit only with real night/time-of-day presentation.
- #268 Atomium pavilion LoD2 — correct topology, 0-pixel locked hero effect.
- #267 Midi station label — impact zero; no oversized typography/camera/emission rescue.
- #269 Town Hall slate roof — measurable but human full-frame impact rejected.
- #231 STIB stop vocabulary — evidence accepted, actual visible stop furniture placement still unproven.
- #275 Midi forecourt reveal, #278 Ixelles Stéphanie 8, #261 Ixelles discovery — evidence/history only; no automatic revival.
- #223 Midi blue stone, #235 bins, #227 micro-material context and generic shopfront lots — rejected for weak/generic identity or low impact.
- #222 Bourse vault proxy — source-truth rejected.
- #165 Bourse pediment gate, #182 Atomium support gate and #204 Ixelles collision parity — stale old-main evidence archived and closed without merge.
- #276/#277/#279 — old prototypes closed as superseded by #288/#286/#283 respectively.
- Long-lived #2/#11 remain specialist workspaces only; never merge wholesale.

## Active ownership map

- **Centre Vertical Slice** — Bourse/Centre/Midi visible slice. #287 shipped. No current Centre production PR. Next lot: materially larger authoritative Bourse roof/interior/envelope correction or a real Midi station/entrance/public-space cue. No proxy pediment, floating labels or micro-frontages.
- **Visual Assets + Atmosphere** — no active production PR. #280 evidence debt closed. Next shared lot must have exact visible placement and high Brussels-specific reuse: transit/signage/furniture, large facade/material family, or weather/lighting/audio only when unmistakable.
- **Ixelles Runtime Slice** — no active production PR. Keep work same-cell and player-facing; old terrain/collision research stays archived unless a current blocking defect is reproduced.
- **Laeken Hero Impact** — #289 shipped and healthy. No current production PR. Do not immediately chase another ground polygon; next candidate must solve a different large pavilion/support/context discrepancy with strong view occupancy.
- **Impact Director maintenance** — Traffic/Living City/missions/saves/release are maintenance-only except blocking bugs or unusually high perceived-impact opportunities.
- **Vehicle lab #286** — still the isolated physical-car comparison lab. No production credit. A future vehicle integration must be rebuilt from exact current main and human drive-feel must clearly beat production.
- **AI lab #288** — technically green real LimboHSM pilot for one police + one civilian. No production-visible behavior win yet; keep quarantined.
- **Mobile/playability draft #290** — `scope_blocked_despite_green_ci`. Current head is exact-current-main and all major checks are green, but the PR mixes four independent domains: mobile analog/camera/fast-travel UX, vehicle A/B, PNJ/traffic collision completion, and Grand-Place LoD2 collision fixes. It must be split before any merge. Director review comment records this gate.

## Top 5 perceived-quality bottlenecks

1. **Mobile control/playability quality** — `10min_gap_high`. Keyboard-like touch input is a major usability limiter on phone. The mobile-only portion of #290 (analog thumbstick + touch camera + view cycling, with fast travel only if it stays compact) is now the strongest immediate 10-minute candidate, but must be extracted from the broad PR and human-playtested on the actual Web build.
2. **Bourse roof/interior/frontage coherence** — `3sec_visual_gap_high`. #287 fixes a real occlusion bug, but the landmark still reads simplified. Only large authoritative corrections qualify.
3. **Midi station + STIB/public-space identity** — `3sec_30sec_gap_high`. Fonsny brick is real, but station entrance, transport vocabulary and forecourt reading remain weak.
4. **Ixelles local identity density** — `30sec_identity_gap_medium_high`. Direct access and Stassart 124 are not enough to sustain a convincing neighborhood slice.
5. **Driving + NPC reaction quality** — `10min_gameplay_gap_high`. #286 and #288 are promising, but neither has exact-current-main production-visible human proof yet.

## Stream health

- **Centre** — `productive_but_needs_larger_next_gain`: #287 final head passed a real anti-micro gate; do not iterate the same portico plane.
- **Visual Assets + Atmosphere** — `healthy_idle`: ready for one high-reuse, placement-proven Brussels cue.
- **Ixelles** — `healthy_idle_but_under-dense`: prioritize visible same-cell identity, not infrastructure research.
- **Laeken** — `productive`: #289 is the strongest fresh visual gain this cycle; move to a different discrepancy next.
- **Mobile #290** — `high_value_scope_drift`: technically green but too broad; split immediately. Mobile UX can compete for integration after extraction + human phone/Web playtest.
- **Vehicle #286** — `promising_lab`: likely high 10-minute payoff, but old-base isolated prototype; do not merge as-is.
- **AI #288** — `technically_green_low_visible-proof`: dependency/complexity is not justified until visible NPC behavior improves in a small current-main pilot.

## Shared priorities

1. **Extract mobile UX from #290 into a tiny exact-current-main PR**; require direct phone/Web human playtest and normal CI/performance/Web gates. This is the single highest-impact next integration candidate.
2. **Large Bourse or Midi source-backed correction** for the strongest immediate visual recognition gap.
3. **Exact-current-main physical vehicle integration challenger** after #290 no longer overlaps the vehicle domain; require real in-game A/B and human drive-feel win.
4. **Ixelles second substantial same-cell identity cue**.
5. **Reusable Brussels transit/signage/furniture cue with proven placement**.
6. **NPC/HSM production pilot** only after it demonstrates a visibly better multi-step response.

## Production rules

1. Exact current `main` is the only production truth.
2. One active lot per exact problem/domain.
3. Small current-main PRs only; re-check `main` and active PRs before push/PR/merge.
4. Publication-only commits are not new gameplay/visual truth.
5. Never merge long-lived specialist branches wholesale.
6. Prefer Paradigm/UrbIS/UrbIS3D, Brussels Mobility, STIB and official orthophoto/DTM/DSM. OSM is complement, not proof for unresolved geometry/traffic semantics.
7. Preserve lawful provenance/licensing.
8. Evidence-only work is allowed only when it can unlock a material player-facing improvement within one or two lots.
9. Green CI can still be rejected for negligible player impact, weak source truth, broad scope or missing human-inspectable evidence.
10. Substantive lots require deterministic player-facing evidence, human inspection, relevant tests, branch hygiene and performance when applicable.
11. Pixel delta is evidence, not the objective; judge recognition, silhouette, street proportions, material response, atmosphere, legibility, motion and gameplay feel.

## Director next-integration priority

**Split #290. The highest-impact immediate candidate is the mobile-only UX slice from exact current main, because it can transform the 10-minute phone/Web experience. Do not merge #290 wholesale. In parallel, Centre should pursue one materially large Bourse/Midi correction. Vehicle A/B and NPC HSM remain separate challengers until direct human gameplay evidence proves they beat production.**
