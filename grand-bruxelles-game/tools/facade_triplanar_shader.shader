# Facade triplanar shader — Godot 4 (GLSL-like) — Proof of Concept

shader_type spatial;

uniform sampler2D albedo_texture : hint_albedo;
uniform sampler2D normal_texture : hint_normal;
uniform float tile_scale = 1.0;

vec3 triplanar_albedo(vec3 pos, vec3 n) {
    vec2 xproj = pos.yz * tile_scale;
    vec2 yproj = pos.xz * tile_scale;
    vec2 zproj = pos.xy * tile_scale;
    vec4 sx = texture(albedo_texture, xproj);
    vec4 sy = texture(albedo_texture, yproj);
    vec4 sz = texture(albedo_texture, zproj);
    vec3 w = abs(n);
    w /= (w.x + w.y + w.z + 1e-6);
    return sx.rgb * w.x + sy.rgb * w.y + sz.rgb * w.z;
}

void fragment() {
    vec3 n = NORMAL;
    vec3 albedo = triplanar_albedo(WORLD_POSITION, n);
    ALBEDO = albedo;
    ROUGHNESS = 0.8;
}

# Usage
# - Import a tiling facade texture atlas
# - Apply shader to OSM extruded building meshes
# - Combine with decals and normal maps for variety
