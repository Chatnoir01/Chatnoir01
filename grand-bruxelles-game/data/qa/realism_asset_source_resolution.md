# Realism asset source resolution

Captured: 2026-08-21

## Problem
The first realism shortlist treated Renderpeople/Sketchfab characters as primary CIV-1 candidates. This is not appropriate for the public production path without an asset-by-asset redistribution review. Renderpeople's own terms allow real-time use in games but prohibit exposing the raw 3D data so third parties can download/extract it. In addition, Renderpeople's free download page blocks mobile-device downloads.

## Resolution
For the public Grand Bruxelles Game repository, close-camera character sources must be redistributable from the outset.

### Primary CIV-1 source class: CC0/redistributable digital-human sources
Preferred lead: `ibrews/VitruvianGodot`, pinned at upstream commit `bdecdcd537b4031fdd0fb299b7e4f93f084fffa0` for evaluation only.

Verified upstream facts:
- upstream README describes a stock-Godot real-time digital human with rigged body, expressive face, eyes, hair and realistic skin workflow;
- upstream NOTICE identifies `vitruvian_head.glb` and `vit_*.png` textures derived from CharMorph Vitruvian as CC0;
- upstream LICENSE states tool code/shaders are MIT and the CC0 character-asset split explicitly;
- upstream Blender prep documentation points to the CC0 `character.zip` release from CharMorph-Vitruvian, so a clean rebuild from original CC0 data is possible;
- do **not** blindly copy Mixamo animation payloads or treat every file in VitruvianGodot as CC0. Animation licensing remains separate.

### Locomotion source class
Prefer a CC0 animation library for the public repository. Quaternius Universal Animation Library / Universal Animation Library 2 is the first choice because it is declared CC0 and has Godot-tested humanoid retargeting. Mixamo may remain a runtime-use option only after a separate redistribution review; never assume the raw Mixamo library can be redistributed.

### Renderpeople status
Renderpeople models remain useful visual/quality references and may be usable in a private licensed asset pipeline, but they are **not** the default public-repository CIV-1 source. Do not commit Renderpeople raw model/texture files to the public repo without explicit rights that allow redistribution.

## CIV-1 implementation gate
1. Fetch/rebuild exactly one CC0 Vitruvian-based witness from a pinned upstream source.
2. Record upstream commit/release, files, license evidence and SHA-256.
3. Strip/replace any animation payload whose redistribution terms are not CC0-compatible.
4. Retarget a CC0 idle/walk/run set.
5. Integrate renderer-only on `NpcAgent`; no AI/navigation/density ownership changes.
6. Preserve current procedural NPC renderer as failure/far-distance fallback.
7. Capture the actual Midi scene at fixed 2 m / 5 m / 8 m views.
8. Measure Web/PC performance and validate grounding/no-slide/material correctness.
9. Production remains false until owner verdict `GARDER`.

## Public-repo rule
If an asset license permits use in a game but forbids redistribution of the source asset, keep the raw asset outside the public repository or reject it for this production path. Never solve an access problem by bypassing login, download controls, or license restrictions.
