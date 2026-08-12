extends Node

## High-value visual refinement for the existing Atomium hero.
## Structural dimensions/centres/tube connectivity remain owned by the zone
## builder. This pass only increases mesh tessellation and replaces the overly
## mirror-like prototype material with a restrained brushed-metal shader.

var refinement_ready: bool = false
var refined_spheres: int = 0
var refined_tubes: int = 0
var refined_base_parts: int = 0

var _metal: ShaderMaterial
var _dark_metal: StandardMaterial3D


func _ready() -> void:
    call_deferred("_refine")


func _make_materials() -> void:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_back;
varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
    local_pos = VERTEX;
    local_normal = NORMAL;
}

void fragment() {
    vec3 n = normalize(local_normal);
    float brushed = sin((local_pos.x + local_pos.z) * 1.55 + local_pos.y * 0.42) * 0.018;
    float vertical = sin(local_pos.y * 0.23) * 0.010;
    float facing = 0.5 + 0.5 * abs(dot(n, normalize(vec3(0.32, 0.74, 0.59))));
    vec3 steel = vec3(0.66, 0.685, 0.70) + vec3(brushed + vertical);
    steel *= mix(0.94, 1.055, facing);
    ALBEDO = steel;
    METALLIC = 0.94;
    ROUGHNESS = 0.18;
    SPECULAR = 0.62;
}
"""
    _metal = ShaderMaterial.new()
    _metal.shader = shader

    _dark_metal = StandardMaterial3D.new()
    _dark_metal.albedo_color = Color(0.12, 0.135, 0.145, 1.0)
    _dark_metal.metallic = 0.78
    _dark_metal.roughness = 0.30


func _refine() -> void:
    _make_materials()
    var hero := get_parent().get_node_or_null("AtomiumHero")
    if hero == null:
        push_warning("LaekenAtomiumVisualRefinement: AtomiumHero missing")
        return

    for child in hero.get_children():
        if not child is MeshInstance3D:
            continue
        var instance := child as MeshInstance3D
        var node_name := str(instance.name)
        if node_name.begins_with("Sphere") and instance.mesh is SphereMesh:
            var sphere := instance.mesh as SphereMesh
            sphere.radial_segments = 48
            sphere.rings = 24
            instance.material_override = _metal
            refined_spheres += 1
        elif node_name.begins_with("Tube") and instance.mesh is CylinderMesh:
            # Godot auto-renames duplicate Tube nodes (Tube2, Tube3, ...), so the
            # prefix is the stable semantic identity for all structural links and
            # support cylinders created by the authoritative zone builder.
            var tube := instance.mesh as CylinderMesh
            tube.radial_segments = 24
            instance.material_override = _metal if tube.bottom_radius >= 1.55 else _dark_metal
            refined_tubes += 1
        elif node_name == "BasePavilion26m" and instance.mesh is CylinderMesh:
            var base := instance.mesh as CylinderMesh
            base.radial_segments = 72
            instance.material_override = _dark_metal
            refined_base_parts += 1

    var base_detail := get_parent().get_node_or_null("AtomiumBaseRealism")
    if base_detail != null:
        for child in base_detail.get_children():
            if child is MeshInstance3D:
                var mesh_instance := child as MeshInstance3D
                if mesh_instance.mesh is CylinderMesh:
                    var cylinder := mesh_instance.mesh as CylinderMesh
                    cylinder.radial_segments = 72
                    refined_base_parts += 1

    refinement_ready = refined_spheres == 9 and refined_tubes >= 20
    print("LAEKEN_ATOMIUM_VISUAL_REFINED: ready=%s spheres=%d tubes=%d base_parts=%d" % [
        refinement_ready,
        refined_spheres,
        refined_tubes,
        refined_base_parts,
    ])
