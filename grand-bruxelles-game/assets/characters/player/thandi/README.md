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
- facial shape data present, including mouth/jaw/eye morph names such as `MouthOpen`, `Jaw_Down`, `Jaw_Left`, `Jaw_Right`, `EyesWide_Left`, `EyesWide_Right`, `Midmouth_Left` and `Midmouth_Right`

Godot player integration automatically looks for these authored assets in this order:
1. `Thandi.glb`
2. `Thandi.fbx`
3. `../player_character.glb`

The procedural pink character is only an emergency fallback when none of the authored assets is present.

## Production target

The source character is only a base. The intended authored derivative will be adjusted toward the approved Brussels player reference: dark/medium-brown skin, realistic young-adult face, dark updo/bun with a front strand, curvier silhouette, hot-pink tracksuit, white top and shoes, plus original non-branded accessories.

Keep this attribution notice with derivatives that use the CC BY source.
