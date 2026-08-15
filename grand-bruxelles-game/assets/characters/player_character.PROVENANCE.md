# Production authored player pilot provenance

Status: **interim real authored binary, not final Thandi likeness**.

This file records the source boundary for `res://assets/characters/player_character.glb`, used only when the preferred Thandi asset is absent. It must never be described as Thandi.

- Source pack: KayKit Character Pack — Adventurers 1.0
- Creator: Kay Lousberg / KayKit Game Assets
- Source repository: `KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0`
- Source commit: `672074b73ba276876a19e8816ecdc5241817ab47`
- Source asset: `addons/kaykit_character_pack_adventures/Characters/gltf/Mage.glb`
- Source Git blob SHA-1: `c89f19f6e707f6e07e4632a08876bd6d0172b082`
- Companion texture: `mage_texture.png`
- Texture Git blob SHA-1: `d0b91fba111e8b9c952aab6698807c0200061100`
- License: CC0 1.0 Universal (`LICENSE.txt` from the same pinned repository/commit)
- Declared pack contents: fully textured, rigged and animated characters; 75 animations; FBX/GLTF; Godot-compatible.

The acquisition workflow verifies the exact Git blob fingerprints, audits the GLB container for skins, weighted mesh primitives, materials and animation clips, imports it in Godot 4.7.1, then runs the real production `game/main.tscn` loader gate. The binary is allowed into this repository only after those checks pass.

This pilot exists to replace the procedural player with a genuine skinned/animated authored character while the intended Dale.Nolan `African Female Rigged with Mouth Morphs` / Thandi source binary remains physically unavailable in production. It does **not** close the final player-art task: the desired Brussels protagonist likeness, clothing, hair, accessories and facial morph quality remain a later authored pass once the intended source can be transferred legally and intact.
