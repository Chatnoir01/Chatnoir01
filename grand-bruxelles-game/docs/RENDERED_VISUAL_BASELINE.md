# Rendered main-scene visual baseline

## Purpose

The rendered baseline is a regression guard for the integrated `game/main.tscn` view. It catches large or accidental changes to composition, lighting, sky/fog, visible geometry, UI, traffic and other rendered content that can pass functional tests while making the playable scene visibly worse.

It is **not** a certificate that the scene matches a real Brussels photograph. Photo-match evidence remains a separate realism gate backed by lawful source images and source positions/cameras where available.

## Evidence kept in Git

Only `data/qa/rendered_main_baseline.json` is versioned. It contains a coarse 16 x 9 visual fingerprint:

- mean red, green, blue and luminance per tile;
- a normalized 16-bin luminance histogram;
- capture dimensions and sampling contract;
- provenance describing the scene and renderer contract used to establish it.

The 1280 x 720 PNG remains a GitHub Actions artifact so repeated captures do not add binary repository bloat.

## Comparison strategy

The contract deliberately avoids exact pixel hashes because Mesa/software-renderer rasterization can vary slightly across runners. The test instead compares coarse visual statistics and fails when any of these exceed the conservative tolerances encoded in `rendered_main_baseline_test.gd`:

- tile RGB mean absolute error;
- tile luminance mean absolute error;
- maximum single-tile luminance delta;
- global luminance-histogram mean absolute error.

The test also retains the existing non-degenerate-image and rendered-performance metrics.

## Establishing or intentionally updating the baseline

A baseline update is allowed only when the visual change is intentional and reviewed against the project realism goal.

1. Run the dedicated record workflow on the short visual-baseline branch with `GB_VISUAL_BASELINE_RECORD=1`.
2. Inspect the PNG artifact visually. Ask: **does this look more like real Brussels, not merely different?**
3. Copy only the emitted fingerprint JSON into `data/qa/rendered_main_baseline.json`.
4. Re-run the normal performance workflow with record mode disabled.
5. Merge only when the normal comparison passes together with Game CI, branch hygiene, tests and photo-match QA.

Never update the reference simply to make a red regression gate green. Fix the regression first unless the visual change is deliberate, source-backed and an improvement.

## Current scope

The baseline protects the current integrated Midi vertical-slice view from silent regression. As deterministic source-backed cameras are added for Midi -> Centre and other reference zones, this contract should expand to a small set of named camera baselines instead of one catch-all frame.
