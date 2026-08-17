# Production Wall

## Main
- observed_main_before_this_edit: `2198f1247933626cb268467196947459224812c1`
- last_verified: `2026-08-17T13:10Z`
- rule: this SHA is the last main observed before this wall edit, not a claim that it equals future HEAD. Always re-read live `main` + open PRs before every branch, PR, merge, rejection or claim.

## Active ownership
- Grand-Place / architecture / Maison des Brasseurs — separate visual ownership; do not overlap.
- Player / fallback identity badge — PR #631 — ACTIVE.
- LABO selector UI v2 — PR #643 — ACTIVE.
- Shared Environment / corridor OSM trees — THIS SHIFT — current exact-main rebuild in progress from `2198f124...`; prior #645/#650 are evidence only / stale and must not merge.
- City Machine / Jette OSM environment adapter — PR #649 — ACTIVE machine/data tooling only.
- Bourse / parvis proportions QA — PR #596 — ACTIVE LEGACY.
- Anneessens / west-side school landmark — PR #572 — ACTIVE LEGACY.
- Midi / station envelope — PR #535 + #537 — ACTIVE LEGACY.
- NPC / offline profile pack — PR #577 — ACTIVE LEGACY.

## Recently shipped
- #648 — Anneessens SIGNALER report sync ingestion.
- #639 — continuity maturity registry + deterministic next-lot selector; automation capped at M5.
- SIGNALER active-zone truth — production truth since `e87e317...`.
- #622 — LABO v2 truth contract.
- #621 — explicit player production-vs-fallback identity contract.
- #620 — city-machine operator contract hardened and campaign closed.
- #595 — Grand-Place Town Hall window rhythm accepted.
- #474 — Fonsny crossing production truth.
- #469/#465 — Bourse glazing + official UrbIS surface correction production truths.

## Closed evidence since previous wall
- #650 corridor OSM trees implementation — stale after #648 shipped; preserve diagnostics only. Tree contract itself passed: 273 source / 7 Anneessens / 266 shared / 3 batches; gate failed only because unrelated Midi autoload errors forced Godot exit 1 in the isolated runtime test.
- #645 corridor OSM trees — valid RED witness then stale; do not merge.
- #637/#628 corridor OSM trees — stale evidence only.
- #629 generic windows — closed for ownership collision + stale base.

## Blocked / do not repeat
- Maison du Roi — raw UrbIS LoD2 failed architectural fidelity.
- Ducs de Brabant — blind generic LoD2 mass failed human gate.
- Grand-Place `1786758` — micro window rhythm insufficient impact.
- Roi d'Espagne — proxy facade + sphere dome failed.
- La Brouette — LoD2 + generic window grid failed; UI masking claim was false.
- Never lower a predeclared visual gate to rescue a correction.

## NOW / NEXT / LATER
- NOW shared Environment: rebuild corridor OSM trees from exact live main `2198f124...`, preserving valid RED evidence and fixing only the isolated gate harness so unrelated Midi autoload exit noise cannot invalidate a tree-contract PASS.
- NEXT shared Environment: run deterministic 1280x720 player-eye A/B and human full-frame verdict; merge only if Corridor Trees + Performance + Web + Game CI + Photo Match + PC + Branch Hygiene all pass on one unchanged head.
- LATER shared Environment: only after tree ownership releases, reconsider generic facade/window/ground-floor repetition with source-backed claims.

## Known visible debt
- Corridor vegetation is incomplete outside Anneessens until the 266 shared OSM trees ship.
- Grand-Place landmark-house facade/silhouette fidelity remains weak.
- Bourse parvis/street/sidewalk proportions unresolved at human gate.
- Midi station envelope conflict unresolved.
- Anneessens west-side monumental frontage not production-shipped.

## Important invariants
- `main` is the only production truth; a green unmerged PR is not shipped progress.
- One defect may have only one active lot; close duplicate PRs.
- Never merge stale visual PRs; rebuild/revalidate from live `main`.
- Human full-frame verdict overrides green CI for visible lots.
- Preserve source X/Z; do not move or enlarge source-backed objects to satisfy impact thresholds.
- Validation workspaces/evidence PRs are not production unless rebuilt from exact live main and merged.

## Shift handoff
- What changed: #650 proved the tree runtime contract itself is green but exposed a harness bug: unrelated Midi autoload errors make the headless test process exit 1 after `BRUSSELS_CORRIDOR_TREES_OK`.
- What is proven: source=273 OSM trees; 7 Anneessens already owned; 266 shared runtime; exactly 3 batches; ODbL provenance; no source position move in the contract path.
- What is NOT proven: current-main A/B, human full-frame PASS, or performance/exports on the rebuilt exact-main head.
- What must not be redone: stale #645/#650 merge, threshold lowering, duplicate tree geometry at Anneessens.
- Exact next action: rebuild the same implementation from current main and make the corridor-tree workflow fail on targeted tree errors / parse errors, not on unrelated autoload exit code alone.
