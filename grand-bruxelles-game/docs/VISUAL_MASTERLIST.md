# Grand Bruxelles — Visual Masterlist

Production truth: GitHub `main` only. This backlog optimizes player-perceived Brussels quality, not commit count.

Current production checkpoint: `cb22135552b31749923a77d211b23575b27834cb` (publication-only Web commit). Latest substantive player-facing merge: `abbbf5379cd63000ae138cfbea3f7ee3534a7ec3` (#289 official Atomium green-block context).

## North star

Ask at every zone: **if a real Brussels photo or observation is beside the game, what gives the game away in the first three seconds?**

Optimize three horizons:
1. **3 seconds** — silhouette, proportions, materials, landmark/street identity, obvious placeholders.
2. **30 seconds** — signage, transport vocabulary, furniture, motion, clutter, lighting and atmosphere.
3. **10 minutes** — playable continuity, navigation, believable traffic/PNJ behavior, missions/saves and performance.

Decision model: **Impact × Confidence × Reuse / (Cost × Risk)**. Green CI is necessary but never sufficient. Source truth and direct player-facing inspection are hard gates.

## Director gates — 2026-08-14 20:10 Brussels

### Fresh production changes

- **#289 Atomium official green-block context** — `shipped`, `major_context_gain`. Paradigm INSPIRE LandCover `LandCover.1038`, classification `GB` / zone verte, official area 54,537.55 m², EPSG:31370, CC-BY-4.0 with attribution. Exact source polygon is mounted terrain-following on the accepted Atomium DTM; no vegetation species, tree geometry, collision, landmark pose or pavilion dimensions are inferred. Presentation green/roughness remain authored rather than measured.
  - Exact-head deterministic A/B: 69,430 / 1,228,800 hero pixels = 5.65% >3 RGB; 137,609 / 921,600 direct-player pixels = 14.93% >3 RGB.
  - Director downloaded artifact `atomium-landcover-1038-evidence` (`sha256:2ad3da507add3c77bfce1b27acece60aabd6d4735b87caebaa268219c84267ba`) and inspected the real direct-player before/after. The foreground changes from generic/exposed terrain to a coherent source-bounded green site while preserving the Atomium silhouette and #254 framing. Human accepted.
  - Source/candidate gates, Atomium hero-ground and pavilion-envelope gates, Game CI, general tests, Branch Hygiene, Web Export, Photo Match and Performance were green on exact head `95c94fb301771d71ed72ecbe92191a6931af8732` before merge. A later Branch Hygiene failure occurred only after `main` advanced and does not invalidate the exact-head pass.

- **#287 Bourse front-depth guard** — `shipped`, `medium_structure_gain`. Exact official UrbIS3D WALLSURFACE triangles behind the audited front facade plane are no longer deleted merely because they match tangent/height/orientation. No source vertices are moved or invented; 0.05 m is floating-point/coordinate tolerance only.
  - Initial intermediate head was correctly rejected by Director at ~0.37% visual delta. Final head `2f4c1a53a69a7670e1b536524059f6b933d67a15` materially changed the result: downloaded exact base/head artifact measures 54,724 / 1,228,800 = 4.4535% pixels >3 RGB and 46,131 = 3.7542% >8 RGB, bbox x37..932 / y82..514.
  - Human inspection accepts the final correction as a real envelope/occlusion cleanup, but it does not solve the broader simplified Bourse roof/interior/frontage problem.

- **#285 Grand-Place granite evidence repair** — `shipped_qa`. The #280 runtime/material stayed unchanged; the dedicated workflow now packages the actual 1280×720 before/after PNGs and logs deterministically. Director inspected the real production A/B: no obvious moiré, z-fighting, aggressive noise or architecture-readability regression. Evidence debt closed.

- **#283 modern player locomotion** — `shipped_gameplay_gain`. Camera-relative normalized movement, stronger deceleration, reduced air control, grounded walk/sprint profile, coyote time and jump buffering are now production behavior while Brussels direct spawns, mobile controls and vehicle enter/exit remain intact.

### Shipped anchors

- **#280 Grand-Place source-backed granite paving** — 39.4694% >3 RGB / 37.7677% >8 RGB; human accepted after evidence repair #285.
- **#272 Grand-Place building 1786758 white-stone identity** — 5.4551% >3 RGB; human accepted.
- **#265 Grand-Place Town Hall white-stone walls** — 6.2901% >3 RGB; human accepted.
- **#260 Grand-Place official LoD2 mass 1786758** — 7.0665% >3 RGB.
- **#257 Grand-Place official LoD2 landmark mass 1655673** — ~11.07% >3 RGB.
- **#258 Ixelles Stassart 124 blue-stone frontage** — 111,611 direct-player pixels >=12/255; 460 unresolved-height buildings remain absent.
- **#254 Atomium direct 48° framing** — ~43.08% >8 RGB.
- **#243 bilingual Brussels street-name plaque**, **#242 direct Ixelles entry**, **#241 Bourse roof winding**, **#239 Ixelles compact runtime**, **#230 Atomium direct entry**, **#226 Atomium reflections**, **#217 Bourse white-stone portico**, **#215 Midi/Fonsny brick**, **#214 Atomium stainless** remain production foundations.

### Closed / rejected / archived paths

- **#273 Grand-Place daylight illumination** — closed without merge; daylight impact 0.1360% >3 RGB / 0.0920% >8 RGB. Reconsider only with real night/time-of-day presentation.
- **#268 Atomium pavilion LoD2** — closed without merge; exact topology repaired but locked hero A/B remained 0 pixels.
- **#267 Midi bilingual station identity** — closed without merge; impact zero. No oversized typography/camera/emission rescue.
- **#269 Town Hall slate roof** — closed without merge; 3.4419% >3 RGB but human full-frame impact rejected.
- **#231 STIB surface-stop vocabulary** — evidence accepted, placement/furniture truth unproven; rebuild only when a real visible stop anchor is proven.
- **#275 Midi forecourt reveal**, **#278 Ixelles Stéphanie 8 frontage**, **#261 Ixelles discovery** — evidence/history only; no automatic revival.
- **#223 Midi blue-stone**, **#235 bins**, **#227 micro-material context**, generic shopfront lots — rejected for weak/generic identity or low impact.
- **#222 Bourse vault proxy** — source-truth rejected.
- **#165 Bourse pediment**, **#182 Atomium support semantics**, **#204 Ixelles collision parity** — archived stale evidence gates on old `main`; closed without merge. Any future use must be rebuilt compactly from exact current main and directly unlock player-facing improvement.
- Long-lived **#2/#11** remain specialist evidence/workspace branches only and are never merge units.

## Active ownership map

- **Centre Vertical Slice** — owns Bourse/Centre/Midi visible slice. #287 is shipped; no active Centre production PR now. Next lot must be a materially larger source-backed Bourse roof/interior/envelope correction or real Midi station/entrance/public-space correction. No proxy pediment, floating labels or micro-frontages.
- **Visual Assets + Atmosphere** — no active PR. #280 evidence debt is closed. Next shared lot must have a defensible exact visible anchor and strong reuse: Brussels transport/signage/furniture, large facade/material family, weather/lighting/audio only when the player-facing effect is unmistakable.
- **Ixelles Runtime Slice** — no active production PR. #239/#242/#258 are healthy; next work must add a substantial same-cell identity cue or compact playable density, not reopen old terrain/collision research unless a current blocking runtime defect is proven.
- **Laeken Hero Impact** — #289 is shipped and healthy. No active production PR. Next Atomium lot should avoid further generic ground work and target a different large source-backed context/pavilion/support discrepancy only if it occupies meaningful player view.
- **Impact Director maintenance** — Traffic/Living City/missions/saves/release remain maintenance-only. Old prototype PRs #276/#277/#279 were closed as superseded. Active labs are #286 vehicle A/B and #288 LimboHSM pilot; neither receives production credit yet.

## Current top 5 perceived-quality bottlenecks

1. **Bourse roof/interior/frontage coherence** — `visual_gap_high`. #287 fixes a real occlusion defect, but the building still reads as simplified compared with the real Bourse. Highest 3-second Centre gap. Only authoritative large-area geometry/material corrections qualify.
2. **Midi station + STIB/public-space identity** — `visual_gap_high`. Fonsny brick is shipped, but station entrance, transit vocabulary and forecourt/public-space reading remain weak. A correct large station/public-space cue has high recognition and reuse.
3. **Ixelles local identity density** — `identity_gap_medium_high`. Direct access and Stassart 124 are real gains, but the playable cell still lacks enough strong Brussels-specific facades/street cues to sustain 30 seconds of immersion.
4. **Grand-Place architectural/detail coherence** — `visual_gap_medium_high`. Massing, white-stone identity and granite ground are much stronger; openings, secondary façades, roof detail, edge context and furniture still reveal the game. Do not return to generic ground/material tweaks.
5. **10-minute world feel: vehicle handling + NPC reactions** — `gameplay_gap_high`. Locomotion is improved, but driving and believable civilian/police reactions are the largest remaining repeat-exposure systems. #286 and #288 are promising labs, not integration units until exact-current-main in-game A/B proves a player-perceived win.

## Stream health

- **Centre** — `productive_but_needs_larger_next_gain`: #287 final head passed the anti-micro gate and shipped; next work must solve a larger Bourse/Midi giveaway rather than iterate the same portico plane.
- **Visual Assets + Atmosphere** — `healthy_idle`: #280 evidence debt is closed; no active duplicate lot. Needs one fresh reusable Brussels cue with exact placement truth.
- **Ixelles** — `healthy_idle_but_under-dense`: stale #204 closed. Avoid returning to infrastructure research; prioritize visible same-cell identity.
- **Laeken** — `productive`: #289 is the strongest fresh visual gain this cycle and directly improves normal-player framing. Do not immediately chase another ground polygon.
- **Vehicle lab #286** — `promising_but_not_current-main-integration`: automated physics and player enter/exit are green, but PR base is old and the physical car is still isolated from the production playable route. Rebuild only after exposing an opt-in exact-current-main A/B in the actual game/preview and human drive-feel review.
- **AI lab #288** — `technically_green_but_low_visible-proof`: real LimboHSM transitions work for one police + one civilian, but there is no demonstrated production-visible behavior advantage yet. Keep quarantined until a tiny current-main opt-in scene produces a clear multi-step behavior improvement worth the dependency/risk.

## Shared priorities

1. **Large Bourse or Midi source-backed correction** — best immediate 3-second recognition opportunity.
2. **Exact-current-main opt-in physical vehicle A/B** — strongest plausible 10-minute feel opportunity; only proceed if human driving clearly beats production without Web/performance regressions.
3. **Ixelles second substantial same-cell identity cue** — compact player-facing lot, not research.
4. **Reusable Brussels transport/signage/furniture cue with proven placement** — strong 30-second immersion and reuse.
5. **Grand-Place architectural edge/detail correction** — only if large and source-backed.
6. **NPC/HSM production pilot** — behind vehicle/visual work until visible behavior improvement is demonstrated.

## Production rules

1. Exact current `main` is the only production truth.
2. One active lot per exact problem/domain.
3. Small current-main PRs only; re-check `main` and active PRs before push/PR/merge.
4. Publication-only commits are not new gameplay/visual truth.
5. Never merge long-lived specialist branches wholesale.
6. Prefer Paradigm/UrbIS/UrbIS3D, Brussels Mobility, STIB and official orthophoto/DTM/DSM. OSM is complement, not proof for unresolved geometry/traffic semantics.
7. Preserve lawful provenance/licensing; never distribute reference imagery as textures without permission.
8. Evidence-only work is allowed only when it can unlock material player-facing improvement within one or two lots.
9. Green CI can still be rejected for negligible player impact, weak source truth or missing human-inspectable evidence.
10. Substantive lots require deterministic player-facing evidence, human inspection, relevant tests, branch hygiene and performance when applicable.
11. Pixel delta is evidence, not the objective. Judge recognition, silhouette, street proportions, material response, atmosphere, legibility, motion and gameplay feel.

## Director next-integration priority

**Highest-impact immediate visual target: a materially large authoritative Bourse roof/interior/envelope or real Midi station/public-space correction from exact current main. Highest-impact 10-minute challenger: reconstruct #286 as a tiny exact-current-main opt-in in-game physical-car A/B and only promote it if direct human driving clearly wins. #288 remains behind both until it proves a visible NPC-behavior advantage.**
