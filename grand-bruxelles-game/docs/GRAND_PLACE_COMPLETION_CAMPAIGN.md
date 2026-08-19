# Grand-Place Completion Campaign

## Production anchor
- Exact launch main: `c1ff559c5ab6faf8f56780f9e65fa432ee1856a4`.
- `main` is the sole production truth.
- Any visual/runtime PR must be rebuilt from live `main` if production advances before integration.
- This document is campaign governance, not runtime authorization.

## Player problem
The Grand-Place currently reads as partially finished: some authored pieces are credible, while large parts of the player-visible square remain generic or incomplete. The campaign objective is therefore not another isolated detail. The objective is to finish every major player-visible mass around the square until no large prototype-like gap remains in normal traversal.

## North star
Grand-Place is complete when 100% of the major visible masses in the reference player views are coherently treated and source-backed. This does not mean reproducing every historical micro-detail. It means no major generic facade, roof mass, ground gap, street transition or collision defect remains obvious at player eye level.

## Canonical player witness
Single production camera contract: `data/qa/grand_place_clean_player_witness.json`.

- source PR: #711
- resolution: 1280×720
- position: `[319.01, 1.72, -535.20]`
- target: `[321.91, 11.8, -485.66]`
- FOV: 62°
- UI/Canvas must be masked
- vehicles/NPC/ambient must be frozen

The canonical camera is the primary view. Phase 0 may add 3–5 secondary traversal views, but these must be registered once and then frozen. A failed candidate may never be rescued by moving a camera.

## Existing production truth to preserve
- #783 SHIPPED: Hôtel de Ville right gallery on official UrbIS `10792525 + 10798452`.
- #848 SHIPPED: Hôtel de Ville east-wing cross-window articulation.
- `grand_place_brasseurs_photo_plan.json` already records evidence for building `1639974`, wall `10945501`; it remains evidence-only until a separately approved runtime lot.

## Explicitly rejected / blocked paths
Do not retry unchanged or rescue the following:
- `10792523`: Town Hall left gallery; outside the natural player frame.
- `10792937` alone: high exposure but unresolved fine architectural identity; do not force-fit B1499/B1501.
- `10796610`: Tête d'Or implementation #863 visually rejected.
- `10796609`: Tête d'Or implementation #865 failed the 3-second gate.
- unchanged Town Hall dormer candidate: too small at the canonical player frame.
- rejected Bourse triangular pediment: outside this campaign and below its frozen full-frame gate.

## Phase 0 — Full-square coverage map
Status: ACTIVE FIRST LOT.

Build a DONE / PARTIAL / MISSING / REJECTED map for all major screen owners in the canonical view plus registered secondary traversal views.

For every owner/group record:
- landmark/front name;
- UrbIS building id when available;
- official face ids or bounded group when available;
- screen bbox;
- full-frame changed-pixel percentage using a realistic shaded/low-relief probe;
- horizontal edge margin / centrality;
- production status;
- source identity status;
- player priority;
- next allowed action.

The probe must approximate the intensity of a realistic stone/material/low-relief architectural correction. Bright emissive or saturated debug masks cannot authorize implementation because they overestimate useful player-visible impact.

Phase 0 must cover at minimum:
1. Hôtel de Ville — central portal/tower/base, principal visible wing groups, roof/tower mass.
2. Maison du Roi — complete player-visible mass.
3. Each contiguous guild-house front visible in the canonical frame.
4. Immediate street-corner/exit masses visible from the square.
5. Ground/paving/routing surfaces visible from player eye.

## Phase 1 — Hôtel de Ville complete visible mass
Order of attack:
1. portal + base of tower as a grouped official-face owner;
2. principal central facade groups;
3. joins around already-shipped right gallery and east cross-window work;
4. roof/tower silhouette only when a large realistic candidate passes exposure.

No window, arcade, statue, portal depth, turret or decorative dimension may be invented before source registration to the exact official face/group.

## Phase 2 — Maison du Roi
Audit and finish major masses before micro-detail:
1. silhouette / vertical massing;
2. roof and gables;
3. major facade rhythm;
4. ground floor / entrances;
5. dominant material treatment.

If the current representation is still generic at player eye, it remains PARTIAL even if geometry exists.

## Phase 3 — Guild-house fronts
Treat contiguous fronts as coherent visual lots rather than one tiny building/detail at a time.

Priority layers:
1. silhouette and gables;
2. major bay rhythm;
3. existing opening articulation;
4. ground-floor readability;
5. material hierarchy.

A front is not DONE while a large neighboring facade in the same player view is still a generic box.

## Phase 4 — Ground / paving / street joins
Complete the square as a place, not only a ring of facades:
- paving/surface readability;
- lawful joins to streets;
- source-backed level transitions;
- foot collision continuity;
- no invented curb/step elevation.

## Phase 5 — Player-height ground floors
Only after major masses are closed:
- arcades;
- doors;
- shopfronts/windows where directly sourced;
- plinths;
- porches;
- threshold articulation.

## Phase 6 — Roofline / final silhouette
Only after large gaps are closed:
- gables;
- chimneys;
- spires;
- dormers that materially affect player-eye reading;
- roof joins.

## Phase 7 — Zero-large-gap pass
Replay all frozen views. Any major facade, roof, corner, street exit or ground section that still reads as prototype/generic keeps the campaign PARTIAL.

## Per-PR rails
- one coherent visual lot = one owner;
- exact-current-main base required;
- UrbIS remains geometry authority;
- source registration precedes architectural detail;
- deterministic BEFORE/AFTER full-frame evidence;
- UI/Canvas hidden recursively;
- dynamic world frozen;
- thresholds frozen before first candidate render;
- no threshold lowering, camera movement, geometry broadening or color rescue after FAIL;
- human full-frame review overrides numeric PASS;
- Character/NPC, combat, shared global Environment and CityGen remain separate ownership unless a dedicated dependency is explicitly approved.

## Required gates for visual lots
- provenance/source gate;
- RED→GREEN dedicated test when runtime changes;
- Game CI;
- Photo Match;
- Performance;
- Web export;
- PC export;
- Runtime Bootstrap when applicable;
- Branch Hygiene;
- deterministic player-eye A/B;
- human full-frame PASS.

## Final completion gate
Do not close the campaign until all are true:
- Hôtel de Ville reads immediately as a coherent finished landmark in every registered player view;
- Maison du Roi reads immediately as a coherent finished landmark;
- no major guild-house front remains generic;
- no large architectural gap remains visible in the registered views;
- square ground and street joins are coherent;
- player collisions are correct across the covered square;
- Game CI, Photo Match, Performance, Web and PC are green on the final integration head;
- multi-view human review passes.

## Immediate next action
Complete Phase 0 and rank the entire square by realistic player impact. The highest-value non-blocked owner becomes the next visual PR. Do not return to isolated micro-detail selection until the full-square coverage matrix exists.