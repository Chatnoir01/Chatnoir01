# Production Wall

## Main
- sha: `071a13f3a730618f5e57484b45044f6fb7dc5f42`
- last_verified: `2026-08-17T12:49Z`
- rule: re-read live `main` + open PRs before every branch, PR, merge, rejection or new claim. If this SHA is stale, refresh this wall before trusting it.

## Active ownership
- Grand-Place / architecture / Maison des Brasseurs source — PR #627 — source gate only — ACTIVE
- Continuity / maturity registry — PR #626 — shared production-state logic, no visual runtime — ACTIVE
- SIGNALER / active-zone truth — PR #617 — reporting runtime — ACTIVE
- Bourse / parvis proportions QA — PR #596 — Bourse surfaces/proportions evidence — ACTIVE
- Anneessens / west-side school landmark — PR #572 — Anneessens architecture — ACTIVE
- Midi / station envelope — PR #535 + #537 — Midi station plan/envelope — ACTIVE
- NPC / offline profile pack — PR #577 — NPC profile/dialogue system — ACTIVE

## Recently shipped
- #622 — LABO v2 truth contract; catalog/runtime semantics are production truth.
- #621 — explicit player production-vs-fallback identity contract.
- #620 — city-machine operator contract hardened and campaign closed.
- #595 — Grand-Place Town Hall window rhythm accepted into production.
- #474 — Fonsny crossing: 13 × 0.50 m white bands, 0.50 m gaps, 4.0 m length across 12.5 m carriageway.
- #469 — Bourse glazing is production truth.
- #465 — official UrbIS surface-level correction is production truth.

## Blocked / do not repeat
- Maison du Roi / Broodhuis — raw UrbIS LoD2 had large pixel impact but failed full-frame architectural fidelity. Do not retry raw LoD2 alone. Unlock: higher-detail facade/photogrammetry/reconstruction source.
- Ducs de Brabant — blind generic LoD2 mass failed human gate. Do not retry LoD2-only facade.
- Grand-Place `1786758` — micro window rhythm had insufficient 3-second impact. Do not enlarge windows just to pass thresholds.
- Roi d'Espagne — generic facade articulation + proxy dome failed human gate; dome read as floating sphere. Do not retry same proxy strategy.
- La Brouette — LoD2 + generic window grid failed architectural read and A/B UI masking was incomplete. Do not repeat window-grid strategy; fix masking before future visual witness.

## NOW / NEXT / LATER
- NOW: #627 Maison des Brasseurs — reproduce unique City record -> UrbIS `1639974` -> audited LoD2 on current live main. No runtime before source PASS.
- NEXT: if source PASS, red-first large-form Brasseurs articulation focused on curved pediment + colossal order + projected axial bay, then deterministic full-frame A/B with dynamics/UI truly masked.
- LATER: when ownership releases, prioritize Bourse proportions, Midi arrival/station envelope, then Anneessens west frontage by highest visible player impact.

## Known visible debt
- Grand-Place still lacks high-fidelity facade/silhouette treatment across several landmark houses.
- Bourse parvis/street/sidewalk proportions remain unresolved at human gate.
- Midi station envelope ownership conflict remains unresolved.
- Anneessens west-side monumental frontage is not yet production-shipped.
- Several Grand-Place LoD2 candidates remain too blind/generic for production-quality landmark recognition.

## Important invariants
- `main` is the only production truth; a green unmerged PR is not shipped progress.
- Never merge a stale visual PR for convenience; rebuild/revalidate from live `main`.
- Human full-frame visual verdict overrides green CI for landmark work.
- Never lower a predeclared gate to rescue a failing correction.
- Freeze/mask dynamic state and UI in deterministic A/B; a false masking claim is a FAIL.
- Two failures with the same solution family require a pivot, not another cosmetic variation.
- Claims are narrow: zone + system + objective. Release them immediately after merge/reject/abandon.

## Shift handoff
- What changed: Production Wall established as shared operational memory; #624 stale source PR was closed and #627 rebuilt from live main.
- What is proven: #624 source chain had passed on its old base; current #627 still must reproduce it on `071a13f...`.
- What is NOT proven: no Brasseurs runtime geometry, no current-main A/B, no human PASS.
- What must not be redone: raw LoD2-only landmarks, generic window grids, proxy sphere dome, threshold lowering.
- Exact next action: wait only for #627 source result; if PASS, create red-first large-form architecture lot after re-reading live main/ownership.
- Current blocker: Bourse/Midi/Anneessens remain actively owned by other PRs.
