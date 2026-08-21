# CIV-1 runtime packaging provenance

CIV-1 is the owner-approved authored civilian witness from PR #1006. This directory is the only canonical production packaging target for that candidate.

## Approved sources

- Character: `ibrews/VitruvianGodot@bdecdcd537b4031fdd0fb299b7e4f93f084fffa0`, CC0-1.0 character assets.
- Footwear: `furqonat/makehuman-assets@8cf9645b975a98eea056b140df11a1d278da0d10`, `base/clothes/shoes03/shoes03.obj`, CC0-1.0, git blob SHA-1 `2cd09f0af9c5bd13604d57d8af19e9205933ee85`.
- Mixamo-derived animation payload is excluded from this public production package.

## Production rail

`source_status.json` is fail-closed. `production_authorized` and `activation_ready` must remain false until all pinned source files are present locally, the canonical Godot runtime package exists under this directory, and every runtime file has a verified SHA-256 recorded in the manifest.

The player asset is never an admissible CIV-1 substitute. In particular, `assets/characters/player_character.glb` and anything under `assets/characters/player/` are forbidden runtime sources for this civilian.

PR #1006 supplies the human visual verdict **GARDER** and close-camera evidence. That verdict authorizes production integration of the approved candidate; it does not waive packaging, provenance, hash, locomotion, grounding, performance, or player-view gates.
