# Production Wall

## Main
- observed_main_before_this_edit: `8f28b66d16f67f96fa56c10d3e2bbd561782d5c3`
- last_verified: `2026-08-18T03:10:00Z`
- latest_published_runtime_parent: `cf2433da792d3bd4616f2a27e6924de412c474aa` — shared presentation-only OSM rail surface shipped; player/release gates passed before publication `ce640963f6468cce2ccf786f26f53c3dfa0bb9c0`.
- rule: this SHA is the last `main` observed before this wall edit, not a claim about future HEAD. Re-read live `main` + open PRs before every branch, merge, rejection or production claim.

## Active ownership
- #11 — long-lived rest-of-Brussels mapping/data/tooling specialist workstream. Never merge wholesale; extract one coherent checkpoint from current main.
- #2 — long-lived Laeken + Jette / Heysel / Atomium specialist workstream. Never merge wholesale; extract current-main checkpoints only.
- No exact-current-main visual implementation PR is approved/open after #737, #738 and #740 were rejected. Old Bourse/Atomium/Anneessens/UI/NPC drafts are evidence/specialist workspaces, not current-main integration candidates.

## Recently shipped
- `cf2433da...` / publication `ce640963...` — reusable shared OSM rail presentation surface on existing geometry; no geometry claim.
- #733 — Bourse standardized OSM zone environment view: exact committed corridor anchor `[81.54,-664.58]`, source-declared 130 m radius, 26 supported OSM points (7 trees, 19 bollards, 0 street lamps), `coverage_complete=false`.
- #730 — Anneessens standardized OSM zone environment contract; seven existing OSM tree IDs/positions preserved and runtime moved to the deterministic zone path.
- #711 — reusable clean Grand-Place 1280x720 player-eye witness; no visible mission/minimap/money/HUD in accepted artifact.
- #680 — Brasseurs photo-plan contract; source/license/hash + exact UrbIS wall constraints, no runtime geometry.

## Closed evidence since previous wall
- #740 — source-backed in-place Fonsny canopy replacement rejected without merge. Urban 9423 supports a vast concrete canopy perforated with glass blocks; the candidate correctly replaced the existing solid slab in the exact authored envelope and produced a non-zero visible change. Locked normal-player A/B nevertheless failed: `ratio3=1.2509%`, `ratio8=1.0272%`, `bbox=649x149` versus frozen `3.00% / 1.50% / 700x160`. Artifact `9309393630`, digest `sha256:1c3cc73780cba722680b59774aa357856ef96b306181ba37c48c860c447a2af0`. Human full-frame verdict: the open grid is visible but remains a small dark band and does not read clearly enough as glass-block canopy in three seconds. In-place replacement is the right mechanism; canopy-only impact is insufficient.
- #738 — generic OSM roof material/runtime rejected without merge. 139 roofs register and technical/release gates are green, but legitimate Anneessens street-level A/B fails twice: locked `>3 RGB ratio = 0.0`. Artifact `9309080809`, digest `sha256:45ecb3cb352c7f5118742635bbf2d2ae51934fe288a85ae667541faa999202a3`. Full-frame review confirms roofs are not meaningfully visible from the normal player view. Do not revive with elevated/artificial camera or lower gate.
- #737 — Fonsny heritage porch overlay rejected without merge. All structural/Web/PC/general gates green, but strict player-eye A/B is exact zero: `ratio3=0`, `ratio8=0`, `bbox=0x0`. Artifact `9309055116`, digest `sha256:9503f23d0fb16567b01cb5000fe5baaef737cd5f26680aeb680a824dd3a407b9`. Candidate porch sits largely inside/behind existing entrance articulation, so it contributes no visible pixels.
- #726 — stale Brasseurs coherent-wall workspace closed. It was based on `b5f2f427...` and its own continuation rule required a fresh live-main read before implementation.
- #662 — stale shared sidewalk-edge workspace closed by its own rule after `main` advanced far beyond `2ab2a6c...`; current production already has later shared OSM sidewalk presentation.
- #681 — obsolete Web first-load audit closed. Its ~66 MB PCK baseline was superseded by later production reductions to the ~38 MB class.
- #728 — stale production-capability roadmap closed after Anneessens/Bourse OSM zone contracts shipped.
- #696 — Brasseurs photo-constrained runtime technical PASS but mandatory human FAIL; primitive/free-standing overlays read as scaffold, not a coherent facade.

## Blocked / do not repeat
- Generic OSM roof treatment from a normal street-level context where roofs are not visible: no player value. Do not game the camera/gate.
- Fonsny additive porch behind the existing `MidiMainEntranceFonsny`: exact-zero visible gain. Do not stack duplicate geometry.
- Fonsny canopy-only replacement: source-correct mechanism but insufficient player impact at the locked normal-player camera. Do not retry by brightening/opaquing glass blocks for pixel count, changing the camera, lowering thresholds, or splitting into even smaller column/register micro-lots.
- Maison du Roi raw UrbIS LoD2; Ducs de Brabant blind LoD2 mass; Roi d'Espagne primitive proxy/sphere dome; La Brouette generic window grid: previous human fidelity failures.
- Maison des Brasseurs free-standing bars/columns/slabs/arches/window-grid overlays and raw photo quad: rejected. Photo remains a constraint/reference source unless a compliant licensed derivative strategy is explicitly approved.
- Never lower a predeclared visual threshold after failure.

## NOW / NEXT / LATER
- NOW: no visual candidate is approved for integration. `main` is `8f28b66d...`; latest player/runtime publication remains `ce640963...` from substantive `cf2433da...`. Do not merge an old draft merely to create activity.
- NEXT visual priority: move away from Fonsny micro-fixes and select another unowned high-impact normal-player defect. Grand-Place / Maison des Brasseurs is the strongest current Centre candidate if ownership remains free.
- Brasseurs restart rule: fresh branch from live main only; exact UrbIS building `1639974` / wall `10945501`; one coherent official-wall skin before relief; reuse #711 clean player-eye witness; no free-standing primitive scaffold; Commons photo measurements are constraints only, not shipped pixels or survey geometry; mandatory human 3-second PASS.
- LATER: continue OSM zone-environment standardization only on zones not actively owned by #2/#11 or another live specialist.

## Known visible debt
- Grand-Place landmark-house facade/silhouette fidelity remains weak; no production-quality Brasseurs facade has passed the human three-second gate.
- Midi/Fonsny station entrance remains generic, but two successive source-backed approaches now prove that additive detail and canopy-only correction are not enough at normal player distance. Revisit only as a larger evidence-backed entrance replacement lot, not as another micro-patch.
- Bourse/Atomium/Anneessens old drafts must be rebuilt from current main before any integration decision.

## Important invariants
- `main` is the only production truth; green unmerged PRs are not shipped progress.
- Standardized OSM zone-environment production coverage remains Jette + Anneessens + Bourse (3/7 catalogue zones). This is contract coverage, not JOUABLE promotion and not a global OSM completeness claim.
- Never merge stale visual PRs; rebuild/revalidate from live main.
- One defect may have only one active implementation; close duplicates rather than race them.
- Human full-frame verdict overrides green CI for visual lots; technical PASS cannot rescue invisible or too-small work.
- #711 remains the canonical clean Grand-Place player-eye witness pattern.
- UrbIS owns official placement/span/wall shape where available; photo measurements are image-space constraints, not survey geometry.
- Commons pixels are not shipped by current contracts; any future derivative must satisfy the applicable license obligations.

## Shift handoff
- What changed: #740 tested the correct Fonsny replacement mechanism and still failed the locked player-eye bar; #737 additive porch and #738 generic roofs remain rejected; no failed runtime was merged.
- What is proven: source-backed Fonsny in-place replacement can create visible change, but canopy-only reaches only `1.2509% / 1.0272% / 649x149` and is not a 3-second production improvement. Fonsny should not consume another micro-lot now.
- What is NOT proven: a production-quality Brasseurs facade; a larger full Fonsny entrance replacement; standardized OSM environment contracts for Midi, Grand-Place, Ixelles or Atomium/Heysel.
- What must not be redone: invisible roof autoload, hidden duplicate Fonsny porch, canopy-only Fonsny retune, stale Brasseurs branch, stale sidewalk-edge branch, obsolete ~66 MB Web audit, lowered visual gates.
- Exact next action: re-read live main and open PR ownership. If Grand-Place/Brasseurs is free, audit current production wall `10945501` and the #680/#711 source/witness chain, then create one fresh RED-first coherent-wall-skin lot from live main. If occupied, choose another unowned normal-player-visible Centre defect.
