# Production Wall

## Main
- observed_main_before_this_edit: `ce8addae6b47e07d8fecbd93525adb4e32d903cf`
- last_verified: `2026-08-17T13:16Z`
- rule: this SHA is the last main observed before this wall edit, not a claim that it equals future HEAD. Always re-read live `main` + open PRs before every branch, PR, merge, rejection or claim.

## Active ownership
- Grand-Place / photo-constrained facade source audit / Maison des Brasseurs — THIS SHIFT — Wikimedia Commons 2024 high-resolution CC BY-SA 4.0 reference + official UrbIS placement; source gate only until license/hash/reference suitability pass — ACTIVE CLAIM.
- Player / fallback identity badge — PR #651 — ACTIVE.
- LABO selector UI v2 — PR #643 — ACTIVE.
- Shared Environment / corridor trees — PR #637 — ACTIVE.
- City Machine / Jette OSM environment — PR #649 — ACTIVE.
- Bourse / parvis proportions QA — PR #596 — ACTIVE LEGACY.
- Anneessens / west-side school landmark — PR #572 — ACTIVE LEGACY.
- Midi / station envelope — PR #535 + #537 — ACTIVE LEGACY.
- NPC / offline profile pack — PR #577 — ACTIVE LEGACY.
- Atomium/Laeken/Jette specialist branches retain their scopes; do not overlap.

## Recently shipped
- #648 — Anneessens SIGNALER report snapshots ingested into continuity evidence.
- #639 — continuity maturity registry + deterministic next-lot selector; automation capped at M5.
- SIGNALER active-zone truth — production truth since `e87e317...`.
- #622 — LABO v2 truth contract.
- #621 — explicit player production-vs-fallback identity contract.
- #620 — city-machine operator contract hardened.
- #595 — Grand-Place Town Hall window rhythm accepted.
- #474/#469/#465 — Fonsny crossing + Bourse glazing/UrbIS surface production truths.

## Closed evidence since previous wall
- #647 Brasseurs — source + RED + runtime + strict A/B all technically valid, but human full-frame FAIL and base became stale. Impact 1.3444% >3 RGB / 1.2817% >8 RGB; artifact `9289884796`, digest `99d61b63...c316`. UI/dynamics masking is proven and reusable.
- #642 Brasseurs — source PASS + legitimate red-first, closed stale before runtime.
- #638 Brasseurs duplicate — closed stale/duplicate.
- #627 Brasseurs source — closed stale.

## Blocked / do not repeat
- Maison du Roi — raw UrbIS LoD2 failed architectural fidelity. Unlock: higher-detail facade/photogrammetry/reconstruction source.
- Ducs de Brabant — blind generic LoD2 mass failed human gate. Do not retry LoD2-only facade.
- Grand-Place `1786758` — micro window rhythm insufficient impact. Do not enlarge to game thresholds.
- Roi d'Espagne — proxy facade + sphere dome failed. Do not retry primitive proxy strategy.
- La Brouette — LoD2 + generic window grid failed. Do not repeat window-grid strategy.
- Maison des Brasseurs — primitive large-form proxy (thin columns + slab + arc) failed human gate despite measurable impact. Do not retry primitive/procedural proxy family. Photo-constrained reconstruction is a distinct source/method family and is the only current Brasseurs retry allowed.

## NOW / NEXT / LATER
- NOW visual: validate the 2024 Wikimedia Commons Grand-Place 10 image through MediaWiki metadata, license, dimensions, immutable file identity and download hash; pair it with official UrbIS `1639974` / wall `10945501`. No runtime before this gate.
- NOW continuity: #648 has ingested Anneessens report snapshots; let continuity owner decide next M4→M5 proof from live registry/report state.
- NEXT visual: only if the photo gate is strong enough, create a photo-constrained reconstruction plan that extracts real facade proportions/features rather than hand-waving primitives. Otherwise release the claim and pivot.
- NEXT LABO regime: #643 ZONES truth UI remains independent.
- LATER: after ownership release, prioritize Bourse proportions, Midi station arrival/envelope, then Anneessens frontage.

## Known visible debt
- Grand-Place landmark-house facade/silhouette fidelity remains weak and now requires a higher-fidelity source family.
- Bourse parvis/street/sidewalk proportions unresolved at human gate.
- Midi station envelope conflict unresolved.
- Anneessens west-side monumental frontage not production-shipped.
- Corridor vegetation/material polish awaits current Environment work.
- Player fallback badge proof continues in #651.

## Important invariants
- `main` is the only production truth; a green unmerged PR is not shipped progress.
- Continuity never auto-promotes M6 JOUABLE.
- OPEN player report blocks JOUABLE readiness/promotion and wins oldest-first.
- One defect may have only one active lot; close duplicate PRs.
- Never merge stale visual PRs; rebuild/revalidate from live `main`.
- Human full-frame verdict overrides green CI for landmarks.
- Never lower a predeclared gate to rescue a correction.
- Strict Brasseurs A/B UI masking pattern is reusable: recursively mask CanvasLayer/CanvasItem and fail capture if any UI remains visible.
- Two failures with the same solution family require a pivot; Grand-Place primitive proxies are now blocked.
- A photo may constrain proportions/visible features only when its license/provenance is explicit; UrbIS remains owner of world placement/scale.
- Claims are narrow and released immediately after merge/reject/abandon.

## Shift handoff
- What changed: Grand-Place claim reopened only for a distinct photo-constrained source audit, not another proxy implementation.
- What is proven: Commons has a 2024 2737x5600 Grand-Place 10 photo under CC BY-SA 4.0; prior UrbIS building/wall identity and strict A/B harness are proven evidence.
- What is NOT proven: immutable photo hash/metadata in CI, suitability for proportion extraction, or any photo-constrained runtime reconstruction.
- What must not be redone: raw LoD2 landmarks, window grids, sphere domes, thin-column/slab/arc primitive facade proxies, lowered gates.
- Exact next action: merge this claim, re-read live main/open PRs, run source-only photo+UrbIS gate.
- Current blocker: Bourse/Midi/Anneessens/player/NPC/shared Environment/Jette machine scopes are owned elsewhere.
