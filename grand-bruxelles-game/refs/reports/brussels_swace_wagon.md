# Photo → Jeu — Brussels Swace wagon

## Subject and anchor
- Subject: one Suzuki Swace station-wagon silhouette reference.
- Real reference zone: Avenue Houzeau / Houzeaulaan, Uccle, Brussels-Capital Region.
- In-game target: `MidiUrbanLife/ParkedCar_07/ProductionVisual`.
- Witness: frozen normal gameplay camera from `midi_ambient_vehicle_visual_capture_test.gd`, 1280x720.

## BEFORE
- Source of truth: PR base SHA on `main`.
- CI output: `refs/witnesses/brussels_swace_wagon_before.png` after evidence archival.

## Diagnostic — max 3 gaps
1. **Proportion** — current glasshouse/roofline ends like a short sedan; the real Swace has a long station-wagon roof and rear glasshouse. **IN SCOPE.**
2. **Material** — current paint/glass remain generic production materials. **OUT OF SCOPE.**
3. **Detail** — grille, lamps and plates remain generic. **OUT OF SCOPE.**

## Unique correction
Extend only the glasshouse and roof cap of `ParkedCar_07` to a station-wagon roofline. Body shell, wheels, materials, traffic logic, physics and every other civilian car remain unchanged.

## AFTER
- Same frozen gameplay camera as BEFORE.
- CI output: `refs/witnesses/brussels_swace_wagon_after.png` after evidence archival.

## Automated proof
- Godot import must be clean.
- Existing Midi civilian-vehicle bridge test must pass.
- Existing A/B test must detect a visible normal-player-camera delta.
- CI verifies the reference photo SHA-1 before evidence upload.

## Human gate — 3 seconds
**PENDING.** Compare reference / BEFORE / AFTER for 3 seconds.
- PASS only if the AFTER reads more credibly as the referenced Brussels station wagon from the player camera.
- FAIL if it still reads as generic decoration, creates an obvious artifact, or does not visibly improve the player capture.
- No merge while this verdict is PENDING or FAIL.

## Archive
- Reference metadata: `refs/photos/brussels_swace_wagon/SOURCE.md`
- Reference photo: archived from the licensed original by CI, then copied to `refs/photos/brussels_swace_wagon/reference.jpg` when the witness artifact is finalized.
- BEFORE: `refs/witnesses/brussels_swace_wagon_before.png`
- AFTER: `refs/witnesses/brussels_swace_wagon_after.png`
- Verdict: this report.
