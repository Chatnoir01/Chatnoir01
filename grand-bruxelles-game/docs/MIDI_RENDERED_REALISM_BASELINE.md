# Midi rendered realism baseline — Day 1

Baseline source: PR #47, GitHub Actions run `31574051084`, artifact `grand-bruxelles-rendered-main-baseline`.

The capture is a deterministic 1280×720 render of the real `game/main.tscn` under Xvfb + Mesa llvmpipe using Godot 4.7.1 OpenGL compatibility. It is a reproducible regression/photo-match input, not a target hardware benchmark.

## Measured rendered baseline

- draw calls max: **3298**
- objects in frame max: **14541**
- primitives in frame max: **591545**
- static memory max: **72.40 MiB**
- wall frame average under llvmpipe: **262.98 ms**
- wall frame p95 under llvmpipe: **266.40 ms**
- sampled luma range: **0.9975** (capture is non-degenerate)

Do not convert llvmpipe frame time into a player-facing FPS target. Use these numbers only as the first reproducible rendered regression reference until a GPU benchmark lane is available.

## Ranked visible mismatch queue

1. **Building silhouette and facade specificity** — major masses still read as generic blocks rather than the actual Midi/Fonsny streetscape.
2. **Street, sidewalk and curb geometry** — ground planes are too flat and uniform; curb/pavement transitions lack real Brussels dimensions and edge detail.
3. **Rail, lane and crossing treatment** — high-contrast slab-like surface geometry reads as placeholder rather than real road/tram infrastructure.
4. **Human proportions and appearance** — procedural humanoids remain visibly prototype at gameplay distance; future changes must use source-backed anthropometrics/assets rather than arbitrary scaling.
5. **Vegetation scale/form** — current trees are simple low-poly masses and do not yet reproduce real species, canopy scale or placement character.
6. **Vehicle diversity/fidelity** — traffic systems are functional, but silhouettes/materials are still visibly generic.
7. **Facade materials/weathering** — surfaces are too uniform; glazing, joints, grime, repairs, aging and commercial variation are missing.
8. **Street furniture/signage/clutter** — not enough Midi-specific poles, bollards, signs, shelters, barriers, bins and frontage detail.
9. **Lighting/atmospheric match** — technically usable but not yet matched against a registered lawful reference viewpoint for exposure, shadow softness, sky and pavement response.
10. **UI composition** — functional prototype; secondary until world-scale mismatches above are reduced.

## Photo-match quality gate

Register 2–3 lawful real Brussels-Midi / Avenue Fonsny hero viewpoints with source URL/metadata, camera position or best available constrained estimate, capture date if known, licensing/reference-only status, and visible target landmarks. Reproduce each camera deterministically in-game.

For every comparison, rank discrepancies by screen-space impact and close them in this order:

**silhouette / building height → street width → curb/sidewalk/rail geometry → major vegetation/furniture → facade proportions → materials/weathering → clutter/signage → lighting.**

Do not mark the Midi hero corridor realism-complete until obvious differences at the fixed viewpoints have been substantially reduced.

## Integration rule

Visual fixes must not replace authoritative UrbIS geometry, alter Lambert 72 truth, bypass provenance, or regress canonical traffic/PNJ/performance gates. Shared `main.tscn` changes belong on small current-main integration branches only.

## Exact next action

Select the first Fonsny/Midi real reference viewpoint, register its lawful provenance and camera constraints, generate the matching deterministic in-game view, then fix only the top one or two largest screen-space mismatches before re-rendering. Do not add new geographic breadth in the same lot.
