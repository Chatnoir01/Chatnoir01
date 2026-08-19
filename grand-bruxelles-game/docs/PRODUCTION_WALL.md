# Production Wall

## Main
- observed_main_before_this_edit: `284d0869d57c09a4b5ded93f4caa477773748b49`
- last_verified: `2026-08-19T14:31Z`
- rule: `main` is the sole production truth. Re-read live main, open PR ownership and this wall before every branch, merge, rejection or production claim.
- current production HEAD: **#881** Atomium normal-arrival avatar-occluder fix.
- recent shipped visual chain includes **#848** Grand-Place Town Hall east cross windows, **#853** Ixelles source-safe facade depth, **#864** shared corridor tree material, and **#881** Atomium arrival occluder removal.

## Core invariants
- Exact-current-main is mandatory. If `main` advances before integration, do not merge a stale candidate; rebuild from live main.
- One coherent lot per PR. One active owner per defect.
- UrbIS owns official geometry. Heritage/archive evidence can constrain presentation only after explicit source registration/measurement.
- Source acquisition, source registration, metric conversion, visual implementation and promotion are separate decisions.
- Green CI alone does not authorize a visual merge.
- **Owner visual review rule:** a candidate may be technically rejected without owner review only for concrete blockers such as crash, false source/data claim, licensing problem or grave regression. A subjective visual FAIL (too small, not realistic enough, insufficient impact) must remain recoverable and must be shown in full-frame BEFORE/AFTER form to the game owner before final visual rejection/closure.
- The agent may recommend KEEP / IMPROVE / DROP, but the game owner owns the final aesthetic verdict after seeing the candidate.
- Never lower a frozen threshold, move the camera, broaden geometry or displace source geometry merely to rescue a visual gate.
- LABO data/readiness is not JOUABLE.

## Current open ownership — verified 2026-08-19T14:31Z
- **#889** owns Grand-Place Maison du Roi owner `1654360` source persistence only.
- **#888** owns shared street-lamp/bollard root-binding reliability only; no art-direction change.
- **#887** owns Combat V2 weapon-to-hand grip/socket work.
- **#886 / #884** own Atomium base-sphere glazing revalidation after #881.
- **#880** is the Bourse triangular-pediment owner-review candidate; do not auto-merge or auto-reject before owner verdict.
- **#878 / #876 / #874** are Grand-Place evidence/campaign workspaces.
- **#875** owns the current Midi civilian cuboid-fallback removal path. Do not touch its pedestrian visual defect from another PR until ownership is resolved.
- **#831 / #829 / #813** remain older overlapping Midi/NPC visual workspaces; treat them as historical/superseded unless a fresh current-main extraction explicitly uses their proven pieces.
- **#596** remains Bourse proportions QA, human review required.
- **#2 / #11** are long-lived specialist geography branches; never merge wholesale.
- At this verification there is **no active owner for civilian vehicle visual variety / body-style presentation at Midi**.

## Grand-Place — current truth
- Canonical player witness remains #711/#753: camera `[319.01,1.72,-535.20]` -> `[321.91,11.8,-485.66]`, FOV `62`, resolution `1280x720`.
- Correct Hôtel de Ville owner = UrbIS building `1655673`.
- **#783 SHIPPED**: source-constrained right-gallery correction on `10792525 + 10798452`; source span `15.944082 m`; full-frame human PASS.
- **#848 SHIPPED**: east-wing cross-window articulation on the existing window rhythm. Preserves 10 east + 9 west bays / 2 registers / 38 panels; adds 20 east crosses = 20 mullions + 20 transoms. Exact-head A/B: `3,361` pixels >8 RGB, `0.364691840277778%`, bbox `339x291`; full-frame human PASS. UrbIS mesh/openings unchanged; west special ordination remains deferred.
- **#854 CLOSED WITHOUT MERGE**: unchanged Town Hall dormer retry was judged too small at the natural player frame. Under the owner-review rule, any resurrection must be shown to the owner before a new final visual verdict.
- **#860 CLOSED evidence-only**: bright full-face unshaded drilldown nominated WALLSURFACE `10796610`, but that method overestimated useful low-relief visibility.
- **#862 CLOSED evidence-only**: source registration of the west-wing / rue de la Tête d'Or architectural semantics remains evidence only.
- **#865 CLOSED WITHOUT MERGE**: realistic Tête d'Or gable treatment on exact WALLSURFACE `10796609` measured `0.318359375%` >3 RGB, `0.3178168403%` >8, bbox `122x341`; it was human-failed because the visible change is a narrow strip at the extreme right edge. Do not call this aesthetically final unless the owner has reviewed the full-frame candidate.
- **#874/#876/#878/#889** now form the active full-square evidence/source campaign. #889 persists the official Maison du Roi owner `1654360` from UrbIS 3D; it authorizes no runtime by itself.

## Ixelles — current truth
- Ixelles remains **LABO** unless a separate promotion gate says otherwise.
- **#819 SHIPPED**: source-backed facade articulation on the 260 direct source-backed Ixelles buildings and whitelisted context cells; source geometry/collision preserved.
- **#853 SHIPPED**: source-safe authored facade depth rebuilt from current production after #848/#851. Scope remained renderer-only relief on existing source-backed walls; footprints, accepted heights, collisions and surveyed claims unchanged. Stassart 124 remains excluded from generic relief so its dedicated identity cue is preserved.
- Do not reopen stale #842; #853 superseded it.

## Atomium / Heysel — current truth
- **#881 SHIPPED / CURRENT HEAD**: removes the large centered normal-arrival player visual occluder after the legitimate Atomium hero is mounted. Player/world/collision/camera truth are preserved; dedicated true-player 1280x720 A/B and human full-frame gate passed.
- **#886 / #884 OPEN**: revalidate the base-sphere glazing candidate now that #881 removed the former occlusion blocker. These candidates must stay reviewable; no subjective auto-close before owner review.
- **#833 SHIPPED evidence-only**: the prior DTM reference resolves to the ticket-shop POI, while a separate monument-relation witness is ~`29 m` away. It rejects treating the ticket-shop point as the Atomium hero centre but authorizes no replacement anchor or runtime move.
- **#814** basin and **#820** neutral StreetSurface arrival were technical/source successes but player-visible failures. They may not be rescued by moving the camera or falsifying geometry; if visually reconsidered, show the original candidate to the owner rather than silently discarding it.

## Shared environment — current truth
- **#864 SHIPPED**: shared authored tree material revision 2 on the existing 266 corridor OSM trees / 3 existing MultiMesh batches. No source position, tree count, collision, silhouette geometry, dimensions, roads, sidewalks, Centre architecture or geography changes.
- Exact-head #864 player A/B passed: `12.7875%` >3 RGB, `7.9962%` >8 RGB, bbox `1207x678`; full-frame human PASS.
- **#888 OPEN**: runtime reliability only for the existing shared street-lamp/bollard bind path; it does not own visual styling.

## Player / NPC / vehicles — current truth
- Player authored locomotion support exists and production also keeps a CC0 KayKit Rogue fallback asset; this is technical fallback, not final Brussels art direction.
- Midi ambient pedestrians are still generated by `midi_urban_life.gd` and upgraded by the profiled pedestrian visual bridge/gait runtimes.
- **#875 owns the current Midi pedestrian fallback defect.** Do not create a parallel NPC branch that edits the same runtime/defect.
- `civilian_vehicle_visual.gd` already contains a brand-neutral European procedural vehicle renderer with Sedan/Hatchback/Wagon style profiles, while `midi_urban_life.gd` currently instantiates every ambient civilian vehicle without setting `body_style`, so the default Sedan path dominates. This is an unowned, player-visible opportunity for the next vehicle lot.

## Important previously rejected visual paths
These records are technical/history guidance, not permission to hide visual candidates from the owner:
- Maison des Brasseurs `1639974` same-building path is screen-space closed from the canonical camera.
- Unsupported Bézier/internal arch dimensions from #781 — never restore.
- Face `10792523` — off-camera; no camera rescue.
- Road markings #773 — prior zero player-visible impact verdict.
- Generic roofs #738 — prior zero player-visible impact verdict.
- Town Hall dormer #854 — prior insufficient player-frame impact verdict.
- Tête d'Or `10796609` #865 — source-valid but narrow-edge candidate.
- Maison du Roi raw LoD2, Ducs blind LoD2, Roi d'Espagne primitive proxy and La Brouette generic windows remain previous fidelity-failure records.

## NOW / NEXT / LATER
- **NOW:** production `284d0869d57c09a4b5ded93f4caa477773748b49` with #881 shipped.
- **NEXT visual-impact campaign:** keep Midi as the witness scene and prioritize high-screen-impact lots. Because #875 already owns civilian-pedestrian cleanup, the next non-overlapping implementation lot is civilian vehicle variety/presentation at Midi.
- **NEXT NPC:** wait for #875 ownership resolution, then integrate genuinely authored/rigged modern civilians on a fresh exact-main branch instead of parallel procedural work.
- **NEXT Grand-Place:** continue the active full-square owner/source campaign; #889 persists Maison du Roi source truth only.
- **LATER:** player art upgrade, police authored uniforms/animations, richer vehicle asset intake, ground/street material coherence, near-camera facades, lighting/ambience, then broader zone propagation.

## Shift handoff
- Live production truth: `284d0869d57c09a4b5ded93f4caa477773748b49` (#881).
- The previous wall was stale at `8b3f83d...`; ownership and governance have been recalculated from live GitHub.
- Visual governance is now explicit: technical/legal blockers may reject immediately; subjective aesthetic rejection requires owner-visible full-frame evidence first.
- Active conflict to respect: #875 owns Midi pedestrian fallback removal.
- Safe next implementation: civilian vehicle visual variety at Midi, using the existing renderer without changing traffic ownership or geography.
