extends SceneTree

const TARGET_PATH := "res://assets/npc_gate_07.glb"
const REQUIRED_ROLES := [
    "pelvis", "spine_01", "spine_02", "neck_01", "head",
    "upperarm_l", "lowerarm_l", "hand_l",
    "upperarm_r", "lowerarm_r", "hand_r",
    "thigh_l", "calf_l", "foot_l",
    "thigh_r", "calf_r", "foot_r",
]
const EXPECTED := {
    "skeleton_count": 1,
    "bone_count": 53,
    "skinned_meshes": 8,
    "skinned_surfaces": 8,
    "material_surfaces": 8,
    "vertex_count": 22642,
    "invalid_skeleton_links": 0,
    "missing_material_surfaces": 0,
}

var failures: Array[String] = []
var skeleton_count := 0
var bone_count := 0
var skinned_meshes := 0
var skinned_surfaces := 0
var material_surfaces := 0
var vertex_count := 0
var invalid_skeleton_links := 0
var missing_material_surfaces := 0
var role_indices := {}

func _initialize() -> void:
    var packed := load(TARGET_PATH) as PackedScene
    if packed == null:
        failures.append("target_scene_missing")
        _finish()
        return
    var root := packed.instantiate()
    get_root().add_child(root)
    _walk(root)
    _validate_roles(root)
    _finish()

func _walk(node: Node) -> void:
    if node is Skeleton3D:
        skeleton_count += 1
        bone_count = maxi(bone_count, (node as Skeleton3D).get_bone_count())
    if node is MeshInstance3D:
        _measure_mesh(node as MeshInstance3D)
    for child in node.get_children():
        _walk(child)

func _measure_mesh(mesh_instance: MeshInstance3D) -> void:
    if mesh_instance.mesh == null:
        return
    var skeleton := mesh_instance.get_node_or_null(mesh_instance.skeleton)
    var has_skin := mesh_instance.skin != null or not mesh_instance.skeleton.is_empty()
    if not has_skin:
        return
    skinned_meshes += 1
    if not (skeleton is Skeleton3D):
        invalid_skeleton_links += 1
    for surface in range(mesh_instance.mesh.get_surface_count()):
        skinned_surfaces += 1
        var arrays := mesh_instance.mesh.surface_get_arrays(surface)
        var vertices = arrays[Mesh.ARRAY_VERTEX]
        if vertices != null:
            vertex_count += vertices.size()
        var material := mesh_instance.get_surface_override_material(surface)
        if material == null:
            material = mesh_instance.mesh.surface_get_material(surface)
        if material == null:
            missing_material_surfaces += 1
        else:
            material_surfaces += 1

func _find_primary_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_primary_skeleton(child)
        if found != null:
            return found
    return null

func _validate_roles(root: Node) -> void:
    var skeleton := _find_primary_skeleton(root)
    if skeleton == null:
        failures.append("skeleton_missing")
        return
    for role in REQUIRED_ROLES:
        var index := skeleton.find_bone(role)
        role_indices[role] = index
        if index < 0:
            failures.append("missing_role:%s" % role)
    var seen := {}
    for role in REQUIRED_ROLES:
        var index := int(role_indices[role])
        if index < 0:
            continue
        if seen.has(index):
            failures.append("duplicate_role_assignment:%s:%s" % [seen[index], role])
        seen[index] = role

func _expect_exact(name: String, actual: int) -> void:
    var expected := int(EXPECTED[name])
    if actual != expected:
        failures.append("%s_expected_%d_actual_%d" % [name, expected, actual])

func _finish() -> void:
    _expect_exact("skeleton_count", skeleton_count)
    _expect_exact("bone_count", bone_count)
    _expect_exact("skinned_meshes", skinned_meshes)
    _expect_exact("skinned_surfaces", skinned_surfaces)
    _expect_exact("material_surfaces", material_surfaces)
    _expect_exact("vertex_count", vertex_count)
    _expect_exact("invalid_skeleton_links", invalid_skeleton_links)
    _expect_exact("missing_material_surfaces", missing_material_surfaces)
    if role_indices.size() != REQUIRED_ROLES.size():
        failures.append("reviewed_role_count_expected_%d_actual_%d" % [REQUIRED_ROLES.size(), role_indices.size()])
    var result := {
        "format": "grand-bruxelles-gate8-variant07-target-integrity-v1",
        "variant": 7,
        "skeleton_count": skeleton_count,
        "bone_count": bone_count,
        "skinned_meshes": skinned_meshes,
        "skinned_surfaces": skinned_surfaces,
        "material_surfaces": material_surfaces,
        "vertex_count": vertex_count,
        "invalid_skeleton_links": invalid_skeleton_links,
        "missing_material_surfaces": missing_material_surfaces,
        "required_roles": REQUIRED_ROLES,
        "role_indices": role_indices,
        "exact_inventory_required": true,
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "retarget_applied": false,
        "visual_approval_claimed": false,
        "failures": failures,
        "state": "TARGET07_EXACT_INTEGRITY_READY" if failures.is_empty() else "TARGET07_EXACT_INTEGRITY_BLOCKED",
    }
    var file := FileAccess.open("res://gate8_variant07_target_integrity.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(result, "  ") + "\n")
    file.close()
    print("GATE8_VARIANT07_TARGET_INTEGRITY state=%s bones=%d meshes=%d surfaces=%d materials=%d vertices=%d failures=%d" % [result.state, bone_count, skinned_meshes, skinned_surfaces, material_surfaces, vertex_count, failures.size()])
    quit(0 if failures.is_empty() else 1)
