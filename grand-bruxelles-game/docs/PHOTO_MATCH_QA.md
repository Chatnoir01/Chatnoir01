# Photo-match realism QA

## Purpose

Hero/reference locations are not considered visually complete because geometry merely exists or because a scene looks plausible in isolation. A hero area must be compared against a lawful real-Brussels reference from a reproducible viewpoint, with mismatches recorded as actionable work.

The machine-readable registry is `data/qa/photo_match/manifest.json`. `tools/validate_photo_match.py` is the merge gate.

## Reference policy

1. Register a stable HTTPS source page, capture date, author, license and camera provenance.
2. Store reference imagery as provenance-only by default. Do not copy a third-party image into distributable game assets merely to run this process.
3. An image may only be vendored when its license permits redistribution and the license/source record remains alongside it.
4. Prefer official/public-domain/openly licensed imagery when it can provide the required viewpoint.
5. Never invent a missing camera coordinate or bearing. Unknown facts stay explicitly `unknown`/`pending` until measured or recovered from a defensible source.

## Real-reference camera record

Schema v2 requires every benchmark to carry a structured camera record in addition to human-readable notes:

- WGS84 camera position status (`known` or `unknown`);
- numeric latitude/longitude when the source actually provides them;
- 35 mm-equivalent focal length;
- orientation status (`known`, `estimated` or `pending`) plus notes;
- a numeric compass heading only when orientation is genuinely known.

This makes the camera itself part of the benchmark instead of allowing a convenient in-game angle to hide geometric errors.

## Viewpoint capture

For each benchmark, reproduce the real reference viewpoint in Godot as closely as practical. Project known WGS84 positions through the same authoritative Lambert72/game-coordinate pipeline used by the world; do not hand-place the camera by eye when a source coordinate exists. Record the in-game camera position, rotation and FOV in the manifest. Camera height and effective focal length matter: changing them to make geometry look correct defeats the benchmark.

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

- its real-reference camera provenance is valid;
- its in-game camera transform is recorded;
- the registered game screenshot exists in the repository;
- all eleven scores are numeric and valid;
- the average and every critical score meet the threshold;
- no unresolved blocker remains.

The validator enforces these conditions. An intentionally incomplete benchmark is valid CI state; an unsupported completion claim is not.

## Registered benchmarks

### Place de la Bourse / Beursplein

The Bourse benchmark uses an openly licensed 2024 image. Its 26 mm-equivalent lens is known, but the registry does not currently have a defensible source camera position/bearing. Those facts are therefore explicit `unknown`/`pending`, and the benchmark remains incomplete.

### Bruxelles-Midi — Avenue Fonsny

The first Midi benchmark uses Wikimedia Commons `20160216 Gare du Midi Avenue Fonsny.JPG`, captured by Jacquesverlaeken on 16 February 2016 under CC BY-SA 4.0. The source provides WGS84 camera coordinates `50.835989, 4.340519` and EXIF 24 mm-equivalent focal length. No trustworthy compass bearing is present, so orientation remains `pending` rather than guessed.

The next exact Midi photo-match action is:

1. transform the verified WGS84 point through the project Lambert72/game-coordinate pipeline;
2. derive heading/pitch from authoritative station geometry and visible landmark alignment;
3. lock the deterministic game camera at the effective 24 mm-equivalent field of view;
4. capture the corresponding game screenshot;
5. score all eleven dimensions;
6. fix the largest screen-space geometry mismatch first, with station/adjacent-building silhouette and street/curb proportions ahead of decorative detail.
