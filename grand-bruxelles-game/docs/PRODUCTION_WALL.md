# Production Wall

## Main
- sha: `ed715f13653758014bf5e96bb5ce464c5e293124`
- last_verified: `2026-08-17T12:55Z`
- rule: re-read live `main` + open PRs before every branch, PR, merge, rejection or new claim. If this SHA is stale, refresh this wall before trusting it.

## Active ownership
- Grand-Place / architecture / Maison des Brasseurs source — PR #638 — source gate only — ACTIVE
- Player / fallback identity badge — PR #631 — player presentation truth — ACTIVE
- LABO selector UI workspace — PR #634 — validation workspace only, do not merge directly — ACTIVE QA
- Bourse / parvis proportions QA — PR #596 — Bourse surfaces/proportions evidence — ACTIVE
- Anneessens / west-side school landmark — PR #572 — Anneessens architecture — ACTIVE
- Midi / station envelope — PR #535 + #537 — Midi station plan/envelope — ACTIVE
- NPC / offline profile pack — PR #577 — NPC profile/dialogue system — ACTIVE

## Recently shipped
- Production Wall — now present in `main` from `1d6bf00...`; all engineers must refresh stale claims against live PR state.
- SIGNALER active-zone truth — production truth from `e87e317...`; stale duplicate PRs are not new work.
- #622 — LABO v2 truth contract; catalog/runtime semantics are production truth.
- #621 — explicit player production-vs-fallback identity contract.
- #620 — city-machine operator contract hardened and campaign closed.
- #595 — Grand-Place Town Hall window rhythm accepted into production.
- #474 — Fonsny crossing: 13 × 0.50 m white bands, 0.50 m gaps, 4.0 m length across 12.5 m carriageway.
- #469 / #465 — Bourse glazing and official UrbIS surface-level correction are production truth.

## Blocked / do not repeat
- Maison du Roi / Broodhuis — raw UrbIS LoD2 had large pixel impact but failed full-frame architectural fidelity. Do not retry raw LoD2 alone. Unlock: higher-detail facade/photogrammetry/reconstruction source.
- Ducs de Brabant — blind generic LoD2 mass failed human gate. Do not retry LoD2-only facade.
- Grand-Place `1786758` — micro window rhythm had insufficient 3-second impact. Do not enlarge windows just to pass thresholds.
- Roi d'Espagne — generic facade articulation + proxy dome failed human gate; dome read as a floating sphere. Do not retry same proxy strategy.
- La Brouette — LoD2 + generic window grid failed architectural read and A/B UI masking was incomplete. Do not repeat window-grid strategy; fix masking before future visual witness.

## NOW / NEXT / LATER
- NOW: #638 Maison des Brasseurs — re-run unique City record -> live UrbIS containment -> audited LoD2 on exact `ed715f...`; retries may recover transient source outages but never replace source truth.
- NEXT: if source PASS, red-first large-form Brasseurs articulation focused on curved pediment + colossal order + projected axial bay, then deterministic full-frame A/B with dynamics/UI truly masked.
- LATER: when ownership releases, prioritize Bourse proportions, Midi arrival/station envelope, then Anneessens west frontage by highest visible player impact.

## Known visible debt
- Grand-Place still lacks high-fidelity facade/silhouette treatment across several landmark houses.
- Bourse parvis/street/sidewalk proportions remain unresolved at human gate.
- Midi station envelope ownership conflict remains unresolved.
- Anneessens west-side monumental frontage is not yet production-shipped.
- Shared corridor environment changes require human validation before production acceptance.
- Player fallback identity visible badge proof remains pending in #631.

## Important invariants
- `main` is the only production truth; a green unmerged PR is not shipped progress.
- Never merge a stale visual PR for convenience; rebuild/revalidate from live `main`.
- Human full-frame visual verdict overrides green CI for landmark work.
- Never lower a predeclared gate to rescue a failing correction.
- Freeze/mask dynamic state and UI in deterministic A/B; a false masking claim is a FAIL.
- Two failures with the same solution family require a pivot, not another cosmetic variation.
- Claims are narrow: zone + system + objective. Release them immediately after merge/reject/abandon.
- Validation-workspace PRs such as #634 are evidence only unless rebuilt from exact live main as an integration lot.

## Shift handoff
- What changed: stale Brasseurs #627/#636 were closed; exact-main #638 now owns the source gate with bounded network retries; wall claim refreshed.
- What is proven: older #624 proved the Brasseurs source chain; no current-main proof is accepted until #638 reproduces it.
- What is NOT proven: no Brasseurs runtime geometry, no current-main Brasseurs A/B, no human PASS.
- What must not be redone: raw LoD2-only landmarks, generic window grids, proxy sphere dome, threshold lowering, cached source identity fallback.
- Exact next action: inspect #638 source workflow; if PASS and `main` is still exact, take a narrow red-first architecture claim; if FAIL, classify source/network failure before pivoting.
- Current blocker: Bourse/Midi/Anneessens remain actively owned; player/NPC scopes remain owned; do not overlap shared Environment work.
