# Photo-match realism QA

## Purpose

Hero/reference locations are not considered visually complete because geometry merely exists or because a scene looks plausible in isolation. A hero area must be compared against a lawful real-Brussels reference from a reproducible viewpoint, with mismatches recorded as actionable work.

The machine-readable registry is `data/qa/photo_match/manifest.json`. `tools/validate_photo_match.py` is the merge gate.

## Reference policy

1. Register a stable HTTPS source page, capture date, author, license and camera notes.
2. Store reference imagery as provenance-only by default. Do not copy a third-party image into distributable game assets merely to run this process.
3. An image may only be vendored when its license permits redistribution and the license/source record remains alongside it.
4. Prefer official/public-domain/openly licensed imagery when it can provide the required viewpoint.

## Viewpoint capture

For each benchmark, reproduce the real reference viewpoint in Godot as closely as practical. Record the in-game camera position, rotation and FOV in the manifest. Camera height and effective focal length matter: changing them to make geometry look correct defeats the benchmark.

Commit the corresponding in-game screenshot under:

`data/qa/photo_match/game_screenshots/<reference-id>.png`

The screenshot is generated from our game and is separate from the external reference image.

## Scoring

Score each dimension from 0 to 5 after viewing the real reference and in-game capture side by side:

- silhouette;
- building placement;
- height and roofline;
- street width;
- curb and sidewalk proportions;
- landmark alignment;
- vegetation;
- street furniture;
- materials;
- lighting;
- major visual clutter.

Default completion threshold is an average of at least 4.0/5. The critical dimensions listed in the manifest must individually meet the same threshold. A high average may not hide a wrong street width, misplaced landmark or incorrect roofline.

## Mismatch tracking

Every incomplete reference must contain at least one actionable mismatch. Use severity `info`, `minor`, `major` or `blocker`, a concrete action, and optionally `resolved: true` after the fix is verified. Obvious geometry/viewpoint discrepancies should remain blockers rather than being downgraded to make a zone pass.

A reference may set `realism_complete: true` only when:

- its camera transform is recorded;
- the registered game screenshot exists in the repository;
- all eleven scores are numeric and valid;
- the average and every critical score meet the threshold;
- no unresolved blocker remains.

The validator enforces these conditions. An intentionally incomplete benchmark is valid CI state; an unsupported completion claim is not.

## First benchmark: Place de la Bourse

The initial Bourse benchmark records an openly licensed 2024 reference and camera metadata, but deliberately has no in-game screenshot or score yet. It therefore remains `realism_complete: false`. The next visual pass must reproduce that viewpoint, capture the game frame, fill the scorecard and convert each observed difference into a concrete scene/material/lighting task.
