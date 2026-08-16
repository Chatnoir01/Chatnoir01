# Grand Bruxelles — Visual Masterlist

Production truth: exact GitHub `main` only. Phase: **VISUAL-FIRST VERTICAL SLICE**, with **VISIBLE LAB ACCESS** for any already-main zone that passes its load contract. Quality expansion still prioritizes **Bruxelles-Midi → Anneessens → Bourse → Grand-Place**, but existing loadable zones must not remain hidden merely because they are unfinished.

## North star

Judge **3-second first impression**, **30-second immersion**, then **10-minute playability**. Optimize visible player-facing improvement per unit of work. Green CI and source correctness are gates, never the objective.

## Human zone-status contract

- **JOUABLE**: the zone is on `main`, loads, is directly visitable, and has passed human play/feel validation.
- **LABO**: the zone is on `main`, loads and is directly visitable, but is explicitly experimental until a human visit promotes it.
- **Not listed**: missing, empty or failing load contracts. Do not replace this with an invisible quarantine.
- The zone selector is the player-facing truth for what can actually be visited. CI may prove loadability; only human play can promote LABO → JOUABLE.

## Current production checkpoint — 2026-08-16

- **#355 NPC visual upgrade — SHIPPED / positive visible gain.** Production civilians no longer use BoxMesh/SphereMesh primitive bodies; they use deterministic profile-driven custom ArrayMesh silhouettes with varied stature, shoulders, skin, hair, clothes and footwear. Human witness is clearly better, though still stylized/low-poly.
- **#351 + #354 authored-player loader — SHIPPED infrastructure only.** The live player can select an authored model, but `assets/characters/player/thandi/` still contains only README/source/textures scaffolding: no real `Thandi.glb` or `Thandi.fbx`. The playable player therefore still falls back to the procedural humanoid. **Real player character remains bottleneck #1.**
- **#360 PC Desktop export gate — SHIPPED release-quality gain.** A deterministic Godot 4.7.1 Linux Desktop export + smoke gate now exists and passes. Web remains preview/QA; PC/Desktop is the quality target.
- **#344 autonomous Living City showcase — SHIPPED 30-second behavior gain.** Reuses existing civilian/police systems at Midi/Bourse. Freeze further scripted-incident expansion pending real 10-minute human QA.
- **#323 Midi concrete + glass-block identity — SHIPPED positive visual gain.** Last clearly positive Brussels-specific facade/material improvement.

## Active ownership map

### 1. Character + NPC Production
Owns player model, rig/skin/materials/animation and NPC visual quality.

**Now:** get one genuine rigged, textured, animated player binary into the shipped authored path and prove the Player actually loads it. No more loader-only cycles unless a concrete import/rig blocker exists. NPC follow-on comes after the real player.

### 2. Centre Vertical Slice
Owns visible architecture/context on **Midi → Anneessens → Bourse → Grand-Place** only.

**Now:** large source-backed facade/arrival/forecourt/hero corrections with legitimate player exposure. #359 Midi multimodal furniture is closed for missing exact placement truth + missing deterministic BEFORE/AFTER. #358/#529 Bourse decorative articulation paths are closed without merge; fix existing mass/detail coherence before adding more decoration.

### 3. Brussels Environment + Lighting
Owns reusable materials, sidewalks/curbs, paving/asphalt/brick/glass/concrete, lamp posts, bollards, road markings, vegetation, sky/lighting/wetness.

**Now:** prefer broad visible reusable assets. Lighting/sky/wetness comes after characters/NPCs/facades and must preserve visual baselines. #353 broad neutral daylight is closed because the rendered-main luma baseline exceeded the allowed contract; do not loosen the baseline to rescue it.

### 4. Runtime Quality + Release
Owns PC/Desktop target, Web preview/QA, mobile readability/controls, LOD/material budgets, zone access and measured performance blockers.

**Now:** keep working systems stable, preserve Web/PC builds, and make existing main zones inspectable through the LABO/JOUABLE selector. No invisible optimization unless it removes a measured blocker or enables a visible lot.

## Top 5 visible bottlenecks

1. **Real player character** — authored loader exists, actual rigged/textured/animated production binary does not.
2. **NPC credibility** — #355 is a clear improvement, but the crowd still reads stylized/low-poly and needs stronger human silhouettes/animation/material quality after the player is solved.
3. **Brussels facades / station arrival identity** — especially Midi arrival/forecourt and large generic Bourse/Centre context masses.
4. **Street-level Brussels vocabulary** — sidewalks, paving, road markings, furniture, vegetation and source-backed signage with natural gameplay exposure.
5. **Presentation + platform polish** — lighting/sky/wetness, vehicle visuals, UI polish and sustained PC/Web/mobile performance after the higher visual priorities above.

## Recent closed / blocked paths

- **#529 Bourse context facade articulation — CLOSED WITHOUT MERGE.** A valid A/B pipeline and green CI still produced an exposed scaffold-like context in the human 3-second verdict. Do not revive decorative overlays until existing vertical composition is coherent.
- **#359 Midi multimodal arrival furniture — CLOSED WITHOUT MERGE.** Project-authored wayfinding/bike/taxi objects lacked authoritative exact placement semantics and the witness was not a deterministic BEFORE/AFTER pair.
- **#353 shared neutral daylight — CLOSED WITHOUT MERGE.** Broad environment gate passed but rendered-main performance/visual baseline failed; do not weaken the baseline.
- **#349 unlocated photogrammetry lab — CLOSED WITHOUT MERGE.** Excellent source/LOD quality but exact geographic identity unproven; no production path until identity is independently proven before opening a future lot.
- **#348 invisible PBR foundation, #346 rear police vest, #342 HUD banner, #338 entrance markers, #329/#335 generic atmosphere** remain closed. Do not revive invisible/decorative loops.

## Production rules

1. Exact current `main` is the only production truth.
2. **Do not hide loadable work already on `main`.** Expose it through the zone selector as **LABO** until human play/feel validation promotes it to **JOUABLE**. Missing/empty/crashing zones are not listed.
3. One active lot per exact problem/domain; avoid duplicate PRs.
4. Fresh-main, small, source/licence-safe lots only.
5. Every visual lot needs deterministic player-facing capture or direct playable evidence plus human full-frame verdict.
6. Dynamic vehicles/PNJs/physics must be frozen/replayed identically or masked in visual A/B evidence.
7. Localized signs/furniture/character details require natural gameplay exposure proof before implementation.
8. No speculative photogrammetry chain; exact geographic identity first.
9. No major traffic/AI/streaming/save rewrite without measured blocker.
10. No invisible optimization/PBR/lighting work unless it removes a measured blocker or enables an obvious visible gain.
11. Preserve working Living City, missions, saves, police, streaming and UrbIS/OSM/DTM pipelines.
12. PC/Desktop is the quality target; Web is lightweight preview/QA.

## Highest-impact next lot

**Character + NPC: integrate one genuine rigged, textured, animated player model into `assets/characters/player/thandi/` and prove the production Player loads it instead of the procedural fallback.** This remains the highest-value 3-second quality improvement; LABO zone access is allowed in parallel because it exposes existing `main` work rather than claiming new geography as finished.

Parallel only if non-overlapping: Centre may prepare one large, source-backed, legitimate-player-view facade/arrival correction; Environment may prepare one broad reusable street/material asset; Runtime may validate/protect those lots, zone access and the PC/Web builds.
