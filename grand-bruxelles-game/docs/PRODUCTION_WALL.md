# Production Wall

## Main
- observed_main_before_this_edit: `ee99dac2f4cde0905300d2b8717554f63c3d03de`
- last_verified: `2026-08-17T13:00Z`
- rule: this SHA is the last main observed before this wall edit, not a claim that it equals future HEAD. Always re-read live `main` + open PRs before every branch, PR, merge, rejection or claim.

## Active ownership
- Grand-Place / architecture / Maison des Brasseurs source — PR #642 — ACTIVE
- Player / fallback identity badge — PR #631 — ACTIVE
- LABO selector UI v2 — PR #643 — ACTIVE; #641 is duplicate/stale and must close
- Shared Environment / corridor OSM trees — PR #637 — ACTIVE
- Bourse / parvis proportions QA — PR #596 — ACTIVE LEGACY
- Anneessens / west-side school landmark — PR #572 — ACTIVE LEGACY
- Midi / station envelope — PR #535 + #537 — ACTIVE LEGACY
- NPC / offline profile pack — PR #577 — ACTIVE LEGACY

## Recently shipped
- #639 — continuity maturity registry + deterministic next-lot selector; automation capped at M5.
- SIGNALER active-zone truth — production truth since `e87e317...`.
- #622 — LABO v2 truth contract.
- #621 — explicit player production-vs-fallback identity contract.
- #620 — city-machine operator contract hardened and campaign closed.
- #595 — Grand-Place Town Hall window rhythm accepted.
- #474 — Fonsny crossing production truth.
- #469/#465 — Bourse glazing + official UrbIS surface correction production truths.

## Closed evidence since previous wall
- #627 Brasseurs source — closed stale; rebuilt as #642.
- #628 corridor OSM trees — closed stale; rebuilt as #637.
- #629 generic windows — closed for ownership collision + stale base.
- #630 continuity registry — closed stale; replaced by shipped #639.
- #617/#632 duplicate SIGNALER fixes — closed; truth already shipped.

## Blocked / do not repeat
- Maison du Roi — raw UrbIS LoD2 failed architectural fidelity. Unlock: higher-detail facade/photogrammetry/reconstruction source.
- Ducs de Brabant — blind generic LoD2 mass failed human gate. Do not retry LoD2-only facade.
- Grand-Place `1786758` — micro window rhythm insufficient impact. Do not enlarge to game thresholds.
- Roi d'Espagne — proxy facade + sphere dome failed. Do not retry same proxy strategy.
- La Brouette — LoD2 + generic window grid failed; UI masking claim was false. Do not repeat window-grid strategy.

## NOW / NEXT / LATER
- NOW continuity: Phase 0/1 foundation is shipped as #639. Next continuity lot is Anneessens report ingestion/synchronisation only; if no blocking OPEN report is proven, then a separate M4→M5 JOUABLE_READY proof pack.
- NOW visual: #642 Brasseurs source gate remains independent.
- NEXT LABO regime: #643 ZONES truth UI remains independent from continuity.
- LATER continuity: only after Anneessens pilot is stable, advance the second zone from the registry.

## Known visible debt
- Grand-Place landmark-house facade/silhouette fidelity remains weak.
- Bourse parvis/street/sidewalk proportions unresolved at human gate.
- Midi station envelope conflict unresolved.
- Anneessens west-side monumental frontage not production-shipped.
- Corridor vegetation/material polish needs human validation.
- Player fallback badge proof remains pending in #631.

## Important invariants
- `main` is the only production truth; a green unmerged PR is not shipped progress.
- Continuity never auto-promotes M6 JOUABLE.
- OPEN player report blocks JOUABLE readiness/promotion and wins oldest-first.
- One defect may have only one active lot; close duplicate PRs.
- Never merge stale visual PRs; rebuild/revalidate from live `main`.
- Human full-frame verdict overrides green CI for landmarks.
- Never lower a predeclared gate to rescue a correction.
- Freeze/mask dynamic state and UI in deterministic A/B; false masking is FAIL.
- Two failures with the same solution family require a pivot.
- Claims are narrow and released immediately after merge/reject/abandon.
- Validation workspaces are evidence only unless rebuilt from exact live main.

## Shift handoff
- What changed: continuity foundation #639 is shipped; registry/selector are now production truth.
- What is proven: seven-zone maturity registry, Midi M6 baseline protection, M5 automation ceiling, oldest OPEN report priority.
- What is NOT proven: repo has not yet ingested runtime-local SIGNALER tickets; therefore `open_reports=[]` is not proof of zero blockers.
- What must not be redone: SIGNALER zone-truth fix, continuity Phase 0/1 registry, duplicate ZONES UI extraction.
- Exact next continuity action: build Anneessens report-ingestion/sync lot from live main without touching west-side school landmark ownership.
