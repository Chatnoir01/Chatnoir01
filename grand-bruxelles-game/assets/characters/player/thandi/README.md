# Thandi player-character source

This directory is reserved for the imported player-character source selected for the Grand Bruxelles player visual.

Source asset: **African Female Rigged with Mouth Morphs**  
Creator: **Dale.Nolan**  
Source page: https://sketchfab.com/3d-models/african-female-rigged-with-mouth-morphs-ffd218c1ae864283b8d72394acdb4c45  
License: **Creative Commons Attribution (CC BY)**

Verified source package received for production work:
- `source/Thandi.fbx` — original FBX, about 19.7 MB
- 12 texture maps for body, hair and top (diffuse, normal, specular and opacity)
- rig/skeleton data present in the FBX
- facial shape data present, including mouth, jaw, eye, brow, cheek and nose morphs

Godot player integration automatically looks for these authored assets in this order:
1. `Thandi.glb`
2. `Thandi.fbx`
3. `../player_character.glb`

The procedural pink character is only an emergency fallback when none of the authored assets is present.

## Automated production build

Once the original source files are committed in `source/` and `textures/`, the workflow `.github/workflows/grand-bruxelles-thandi-build.yml` runs the Blender production script `tools/prepare_thandi_character.py` and generates `Thandi.glb` automatically.

The first production pass reconnects supplied textures, preserves the rig and facial morphs, normalizes the character to about 1.70 m, removes the zebra colour from the top in favour of the approved hot-pink material, darkens the hair and exports a Godot-friendly GLB with skins, animations and morph targets. The generated GLB is then imported and tested headlessly in Godot before being committed.

This automation is **not** a claim that the face already matches the approved reference. Face likeness, hairstyle reshaping, curvier silhouette, white crop-top/shoes and accessories remain authored visual passes after the source asset is active in-engine.

## Production target

The source character is only a base. The intended authored derivative will be adjusted toward the approved Brussels player reference: dark/medium-brown skin, realistic young-adult face, dark updo/bun with a front strand, curvier silhouette, hot-pink tracksuit, white top and shoes, plus original non-branded accessories.

Keep this attribution notice with derivatives that use the CC BY source.
