# CIV-1 runtime packaging provenance

CIV-1 is the owner-approved authored civilian witness from PR #1006. This directory is the only canonical production packaging target for that candidate.

## Approved sources

- Character: `ibrews/VitruvianGodot@bdecdcd537b4031fdd0fb299b7e4f93f084fffa0`, CC0-1.0 character assets.
- Footwear: `furqonat/makehuman-assets@8cf9645b975a98eea056b140df11a1d278da0d10`, `base/clothes/shoes03/shoes03.obj`, CC0-1.0, git blob SHA-1 `2cd09f0af9c5bd13604d57d8af19e9205933ee85`.
- Mixamo-derived animation payload is excluded from this public production package.

The character commit is not sufficient by itself as a packaging identity. The exact CC0 source bytes accepted by the production preflight are pinned individually:

| Canonical source file | Upstream path | Git blob SHA-1 | Size |
| --- | --- | --- | ---: |
| `source/vitruvian_body.glb` | `godot_project/vitruvian_body.glb` | `09bcade1092e5a89b474e91e6013209d4c68c127` | 6,879,364 B |
| `source/vitruvian_head.glb` | `godot_project/vitruvian_head.glb` | `0c810e209f09fc079086746f0813de9531d0f7fb` | 10,189,832 B |
| `source/hairtool_cards.glb` | `godot_project/hairtool_cards.glb` | `04799adc868ba72e0fa1c1ab60c0442e12d5987e` | 14,839,096 B |
| `source/vitruvian_hair.glb` | `godot_project/vitruvian_hair.glb` | `b6f63553ce9d5f2f83920b445f21831caf9017f1` | 21,189,248 B |
| `source/shoes03.obj` | `base/clothes/shoes03/shoes03.obj` | `2cd09f0af9c5bd13604d57d8af19e9205933ee85` | validated by Git blob identity |

`validate_civ1_runtime_packaging.py` recomputes the Git blob identity from local bytes whenever `source_package_present=true`. A renamed, regenerated or substituted file therefore cannot satisfy the source gate merely because the repository/commit metadata still matches.

## Production rail

`source_status.json` is fail-closed. `production_authorized` and `activation_ready` must remain false until all pinned source files are present locally, the canonical Godot runtime package exists under this directory, and every runtime file has a verified SHA-256 recorded in the manifest.

The player asset is never an admissible CIV-1 substitute. In particular, `assets/characters/player_character.glb` and anything under `assets/characters/player/` are forbidden runtime sources for this civilian.

PR #1006 supplies the human visual verdict **GARDER** and close-camera evidence. That verdict authorizes production integration of the approved candidate; it does not waive packaging, provenance, hash, locomotion, grounding, performance, or player-view gates.
