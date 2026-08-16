# Photo → Jeu — Brussels Swace wagon

## Subject and anchor
- Subject: one Suzuki Swace station-wagon silhouette reference.
- Real reference zone: Avenue Houzeau / Houzeaulaan, Uccle, Brussels-Capital Region.
- In-game target: `MidiUrbanLife/ParkedCar_07/ProductionVisual`.
- Witness: frozen normal gameplay camera from `midi_ambient_vehicle_visual_capture_test.gd`, 1280x720.

## BEFORE
- Source of truth: PR base SHA `dd3d00e98620f15f5b4b3e6522c57a4af09226c3` on `main`.
- Archived witness: `refs/witnesses/brussels_swace_wagon_before.png`.

## Diagnostic — max 3 gaps
1. **Proportion** — current glasshouse/roofline ends like a short sedan; the real Swace has a long station-wagon roof and rear glasshouse. **IN SCOPE.**
2. **Material** — current paint/glass remain generic production materials. **OUT OF SCOPE.**
3. **Detail** — grille, lamps and plates remain generic. **OUT OF SCOPE.**

## Unique correction
Extend only the glasshouse and roof cap of `ParkedCar_07` to a station-wagon roofline. Body shell, wheels, materials, traffic logic, physics and every other civilian car remain unchanged.

## AFTER
- Same gameplay camera as BEFORE: `(-655.0167, 1.520333, 624.8613)`.
- Archived witness: `refs/witnesses/brussels_swace_wagon_after.png`.

## Automated proof
- Godot import: PASS.
- Midi civilian-vehicle bridge test: PASS.
- BEFORE and AFTER capture: PASS, same camera.
- Reference source SHA-1 verification: PASS (`58a9d30263786459816b676d3e006d01e725846a`).
- Raw A/B metric: `gt4=2.9616%`, `gt12=2.6585%`, `bbox=309x443`.

## Gate — 3 seconds
**FAIL.** The raw CI A/B threshold is a false positive for this lot: visual inspection and pixel localization show the dominant changed region is the animated player in the center of frame, while the intended car does not gain a clearly visible player-camera improvement.

This fails the project rail: a photo lot must visibly improve the player capture. Therefore this branch must not merge.

## Archive
- Reference metadata: `refs/photos/brussels_swace_wagon/SOURCE.md`.
- Reference photo: `refs/photos/brussels_swace_wagon/reference.jpg` (repository display copy); the original licensed image is also preserved in the CI artifact after SHA-1 verification.
- BEFORE: `refs/witnesses/brussels_swace_wagon_before.png`.
- AFTER: `refs/witnesses/brussels_swace_wagon_after.png`.
- CI artifact: `midi-ambient-vehicle-visual-ab`, artifact ID `9268449434`.
- Verdict: **FAIL / close without merge**.

## Remaining risk
The current generic A/B witness can be fooled by player animation. Before retrying a car photo lot, the witness must exclude or deterministically freeze player-animation noise and frame a car that is actually visible to the player camera.
