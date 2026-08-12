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

The Bourse benchmark now has an automated capture gate. `game/tests/photo_match_capture_test.gd` reads the camera transform from the manifest, instantiates the real `main.tscn`, suppresses prototype UI/player noise, disables automatic traffic spawning for a geometry-focused comparison, and writes a deterministic 1280x960 PNG. CI publishes that PNG as the `bourse-photo-match-capture` artifact on every relevant PR.

The manifest transform may be marked `status: provisional` while viewpoint alignment is still being refined. A provisional transform is useful for repeatability but is not proof of a match. Once side-by-side alignment is accepted, commit the approved in-game screenshot under:

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

- its camera transform is recorded and no longer provisional;
- the registered game screenshot exists in the repository;
- all eleven scores are numeric and valid;
- the average and every critical score meet the threshold;
- no unresolved blocker remains.

The validator enforces the existing completion conditions. An intentionally incomplete benchmark is valid CI state; an unsupported completion claim is not.

## First benchmark: Place de la Bourse

The initial Bourse benchmark uses the CC0 2024 photograph `Place de la Bourse (6).jpg` by Bernard Lee. Wikimedia Commons records the original as 4032x3024, captured with an iPhone XR at 4.25 mm / 26 mm full-frame equivalent and released under CC0 1.0. The current game camera is intentionally marked provisional: it is a repeatable ground-level west-side starting pose facing the Bourse checkpoint with a 69.4 degree FOV approximation. CI must first produce a stable capture from that pose; the next realism pass then aligns the pose side-by-side with the reference, commits the accepted game screenshot, scores all dimensions and converts visible discrepancies into concrete scene/material/lighting tasks. Until that happens, `realism_complete` remains false.

### Current Bourse geometry status

The generic 6.3 m OSM fallback is replaced at runtime by the official UrbIS 3D geometry for building `https://databrussels.be/id/building/1751663`. The committed derived mesh contains 645 semantic LoD2 faces and 1,818 triangles, with an audited source Z range of 18.2459–58.4012 m. Its package URL, CC0-1.0 license, EPSG:31370 coordinates and package/component SHA-256 values are pinned in `data/urbis/heroes/bourse_lod2.game.json`.

The immediate Bourse forecourt context consumes the three exact official UrbIS `StreetSurfaces` locked by #117: `151495`, `152281` and `22358`. They comprise two `SW` and one `I` source-code polygons totalling 459 source m2 and 81 deterministic runtime triangles. Source TYPE codes remain uninterpreted evidence codes; runtime colors are presentation buckets only. The source response SHA-256, request bbox, CC0-1.0 provenance and exact EPSG:31370 coordinates are pinned in `data/urbis/bourse_street_surfaces.game.json`. This improves the bounded forecourt plan but does not approve the wider streetscape, curb elevations, materials, frontage density or provisional camera, so `runtime_approved=false` and `realism_complete=false` remain mandatory.

This closes only the missing-landmark massing blocker. `runtime_approved` and `realism_complete` remain false because the provisional camera, frontage, forecourt/street proportions, materials and neighboring streetscape have not passed side-by-side photo-match review.
