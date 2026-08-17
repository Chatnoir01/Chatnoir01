extends Node

const FAMILY := "urbis_official_paved_area_v1"
var applied := false
var paved_feature_count := 0
var _paved_mesh: MeshInstance3D = null
var _original_material: Material = null
var _enhanced_material: ShaderMaterial = null

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _apply_when_ready() -> void:
    for _frame: int in range(20):
        await get_tree().process_frame
        var main := get_tree().current_scene
        if main == null:
            continue
        var builder := main.get_node_or_null("UrbISMidiExact")
        if builder == null:
            continue
        var paved := builder.get_node_or_null("UrbISStreetSurfaces/ExactPavedAreas") as MeshInstance3D
        if paved == null or paved.mesh == null or paved.mesh.get_surface_count() == 0:
            continue
        var counts := builder.surface_family_counts() as Dictionary
        paved_feature_count = int(counts.get("paved", 0))
        if paved_feature_count <= 0:
            return
        _paved_mesh = paved
        _original_material = paved.mesh.surface_get_material(0)
        _enhanced_material = _material()
        paved.mesh.surface_set_material(0, _enhanced_material)
        paved.set_meta("source_semantics", "UrbIS StreetSurface TYPE=P")
        paved.set_meta("geometry_changed", false)
        applied = true
        print("MIDI_OFFICIAL_PAVED_FORECOURT_READY: paved_features=%d geometry_changed=false" % paved_feature_count)
        return

func set_enhanced_material_enabled(enabled: bool) -> void:
    if _paved_mesh == null or _paved_mesh.mesh == null or _paved_mesh.mesh.get_surface_count() == 0:
        return
    _paved_mesh.mesh.surface_set_material(0, _enhanced_material if enabled else _original_material)

func enhanced_material() -> ShaderMaterial:
    return _enhanced_material

func original_material() -> Material:
    return _original_material

func _material() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = "shader_type spatial; render_mode diffuse_burley,specular_schlick_ggx,cull_disabled; varying vec3 wp; float hash21(vec2 p){p=fract(p*vec2(123.34,345.45));p+=dot(p,p+34.345);return fract(p.x*p.y);} void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;} void fragment(){vec2 p=wp.xz; float broad=hash21(floor(p/2.8)); float fine=hash21(floor((p+vec2(broad*0.7))/0.72)); float v=(broad-0.5)*0.055+(fine-0.5)*0.025; vec3 base=vec3(0.365,0.350,0.320); ALBEDO=base+vec3(v); ROUGHNESS=clamp(0.91+(fine-0.5)*0.08,0.84,0.97); }"
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_meta("surface_family", FAMILY)
    material.set_meta("source_semantics", "official_urbis_type_P")
    material.set_meta("geometry_changed", false)
    material.set_meta("paving_composition_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("presentation_values", "authored_not_source_measurement")
    return material
