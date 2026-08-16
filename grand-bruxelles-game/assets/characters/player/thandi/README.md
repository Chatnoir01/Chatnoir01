# Thandi player-character source

This directory is reserved for the imported player-character source selected for the Grand Bruxelles player visual.

Source asset: **African Female Rigged with Mouth Morphs**  
Creator: **Dale.Nolan**  
Source page: https://sketchfab.com/3d-models/african-female-rigged-with-mouth-morphs-ffd218c1ae864283b8d72394acdb4c45  
License: **Creative Commons Attribution (CC BY)**

## Current production status

The source has been selected and its expected production contract is documented, but the actual source package is **not committed on current `main` yet**. At present, `source/` and `textures/` contain placeholders only, so the authored player cannot be built and runtime correctly falls back to the procedural pink character.

Machine-readable truth lives in `source_status.json`. It must stay synchronized with the repository contents and is validated fail-closed by `tools/validate_thandi_source_status.py`.

Required source files before the package may be marked present:
- `source/Thandi.fbx`
- `textures/Thandi_Body_Diffuse.png`
- `textures/Thandi_Hair_Diffuse.png`
- `textures/Thandi_Top_Diffuse.png`

The intended source package is expected to preserve:
- rig/skeleton data in the FBX;
- supplied body, hair and top textures;
- facial shape/morph data where present in the licensed source.

Godot player integration looks for authored assets in this order:
1. `Thandi.glb`
2. `Thandi.fbx`
3. `../player_character.glb`

The procedural pink character is only an emergency fallback when none of the authored assets is present.

## Automated production build

Once the required original source files are genuinely committed and `source_status.json` is updated to match, `.github/workflows/grand-bruxelles-thandi-build.yml` runs the Blender production script `tools/prepare_thandi_character.py` and generates `Thandi.glb` automatically.

The first production pass reconnects supplied textures, preserves the rig and facial morphs, normalizes the character to about 1.70 m, removes the zebra colour from the top in favour of the approved hot-pink material, darkens the hair and exports a Godot-friendly GLB with skins, animations and morph targets. The generated GLB is then imported and tested headlessly in Godot before being committed.

This automation is **not** a claim that the face already matches the approved reference. Face likeness, hairstyle reshaping, curvier silhouette, white crop-top/shoes and accessories remain authored visual passes after the source asset is active in-engine.

## Production target

The source character is only a base. The intended authored derivative will be adjusted toward the approved Brussels player reference: dark/medium-brown skin, realistic young-adult face, dark updo/bun with a front strand, curvier silhouette, hot-pink tracksuit, white top and shoes, plus original non-branded accessories.

Keep this attribution notice with derivatives that use the CC BY source.
