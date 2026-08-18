# Production Wall

## Main
- observed_main: `3be7b244cd9f6fe423870a0a7e012cb19f9292bb`
- last_verified: `2026-08-18T07:35Z`
- rule: `main` is the sole production truth. Re-read live main, open PRs, changed-file ownership and this wall before every branch, merge, rejection or production claim.
- six-point campaign status: **6/6 merged**.
- current production pipeline: #767 removed generated Web commits to `main`; Web build is repository-read-only and hands an immutable `grand-bruxelles-playable-web` artifact to Pages. Branch Hygiene now computes stale drift against live `origin/main`, not only the PR event base.
- post-#767 repository observation: the latest commit is still #767 itself; no `web: publish ...` automation commit has appeared after the merge. The connector available in this session does not enumerate push/workflow_run runs, so keep the first live Web→artifact→Pages workflow-run result as a production verification item rather than inventing a PASS.

## Six-point campaign — SHIPPED
1. **#749 — Midi official street collision**: official StreetSurface families are physically solid under the player. Dedicated ray + `CharacterBody3D` proof passed; building collision and visual/performance gates remained green.
2. **#750 — player melee feel**: readable recovery/anti-spam, no attack during dodge, collision-aware reaction, with existing KO/loot flow preserved.
3. **#752 — PhysicalCarB primary**: Mission 01 uses the physical B car; A remains fallback/comparison. Quicksave, autosave/cold resume, reward flow and Retour Express follow the mission primary vehicle and support rigid-body velocity state.
4. **#765 — Midi/Fonsny full entrance**: generic wall/glazing/slab articulation replaced in place with the Urban 9423 source-backed three-register porch, polygonal supports, glass-block bays and perforated canopy. Locked player-eye result: `4.9336%` >3 RGB, `4.2255%` >8 RGB, bbox `903x185`; human full-frame PASS. UrbIS remains plan authority; bounded presentation dimensions are not survey claims.
5. **#766 — LABO→JOUABLE promotion gate**: Midi remains the only JOUABLE. Six other catalog zones remain LABO. Promotion is fail-closed and requires source/runtime/collision/hero/full-frame/performance-export/human evidence; City Machine cannot promote.
6. **#767 — Web/integration discipline**: Web no longer commits generated `web-preview` back to `main`; Pages production path consumes the exact successful Web workflow artifact/head SHA. Any PR to main with `behind > 0` against live main is fail-closed until resync + gate rerun.

## Active ownership
- **#768** — exact-current-main generic `Building_*` OSM facade articulation, base `3be7b244...`. Owns only generic OSM facade presentation; do not overlap shared OSM facade material/articulation paths. Historical #764 is closed without merge and superseded by #768.
- **#652** — Anneessens SIGNALER sync export, old/stale draft. Do not treat green historical evidence as current-main integration authorization.
- **#643** — LABO selector UI, old/stale draft. Its promotion semantics must not bypass #766.
- **#596 / #592** — Bourse QA/architecture old drafts; source/evidence only until rebuilt from current main.
- **#2 / #11** — long-lived Laeken/Jette and rest-of-Brussels specialist branches. Never merge wholesale; extract one coherent lot from then-current main.
- Other old Atomium/NPC/evidence drafts are specialist/history workspaces, not current-main merge candidates.

## Known visible debt
- Grand-Place remains visually sparse/weak in the canonical #753 view; large generic/blank building masses still dominate.
- Midi/Fonsny is materially better at the targeted entrance after #765, but this does **not** mean the complete Midi station facade or district is realism-complete.
- Six LABO zones remain LABO by design. #766 prevents status inflation; future promotion still needs full player-visible evidence and human PASS.
- Generic OSM facade articulation is active in #768 and must not be duplicated by another workstream.

## Rejected / closed visual paths — do not repeat
- **#740 Fonsny canopy-only**: `1.2509% / 1.0272% / 649x149` versus locked `3.00% / 1.50% / 700x160`; insufficient. Superseded by the full in-place #765 solution.
- **#737 additive Fonsny porch**: exact-zero visible gain because production articulation occluded it. Do not return to additive layering at that entrance.
- **#738 generic street-level roofs**: `>3 RGB = 0.0`; no legitimate player-eye value.
- Maison des Brasseurs same-building path (`UrbIS 1639974`) is mathematically closed under the frozen canonical gate: #755 exact wall rendered only `96x287 px`; #758 optimistic union of all six official WALLSURFACE faces reached only `174.526x287.869 px`, below the frozen 300 px width requirement. Do not lower thresholds, move camera, widen/invent geometry or hide neighbours to rescue it.
- Maison du Roi raw UrbIS LoD2, Ducs de Brabant blind LoD2 mass, Roi d'Espagne primitive dome/proxy and La Brouette generic window grid remain previous human fidelity failures; do not repeat the same forms.
- Never use `Vector3(324.9581,3.3,-512.8388)` as “#711”; #753 shared Grand-Place camera contract is the canonical camera truth.

## Important invariants
- green unmerged PRs are not shipped progress.
- exact-current-main is mandatory at merge time; `behind > 0` is now a Branch Hygiene failure.
- one defect may have only one active implementation owner.
- human full-frame verdict overrides green CI for visual lots.
- UrbIS owns official geometry where available; photo measurements are image-space constraints, not survey geometry.
- LABO data readiness is not JOUABLE; only a human-approved proof satisfying #766 can change that status.
- Web publication must remain artifact-only and repository-read-only; reintroducing `git commit`, `git rebase` or `git push` in the Web build is a regression.

## NOW / NEXT / LATER
- **NOW**: production HEAD `3be7b244...`; six-point campaign is merged. Protect #768 ownership while its fresh current-main gates run. Do not reopen #764.
- **NEXT production verification**: record the first successful post-#767 `Grand Bruxelles Playable Web Build` artifact and the downstream `Grand Bruxelles Playable Link` workflow_run deployment. Confirm `main` remains unchanged by publication.
- **NEXT visual selection**: after ownership reread, use the canonical #753 Grand-Place player-eye witness to identify the largest source-backed production geometry owning the weak screen mass. Start with evidence-only screen-space ownership, not a landmark chosen by name.
- **LATER**: promote no LABO zone until its #766 evidence file can honestly PASS every required stage.

## Shift handoff
- What changed: collisions, melee, physical mission car, Fonsny entrance, promotion discipline and Web/integration discipline are all merged.
- What is proven: Point 1–5 player/runtime gates passed; Point 6 PR contract/Playable Link/Branch Hygiene/Game CI/tests passed and no post-merge generated publication commit has appeared on `main`.
- What remains to verify externally: the first post-#767 push-triggered Web artifact → Pages workflow-run chain, because the session connector exposes PR-triggered Action runs but not push/workflow_run listings.
- What must not be redone: old Fonsny additive/canopy-only attempts, same-building Brasseurs rescue, stale wholesale specialist merges, or Web publication by committing generated files to `main`.
- Exact next action: observe #768 ownership/gates and the first artifact-backed Pages production run; if `main` moves independently, every open merge candidate must resync and rerun before integration.
