extends SceneTree

const TARGET_PATH := "res://assets/npc_gate_03.glb"
const REQUIRED_ROLES := [
    "pelvis", "spine_01", "spine_02", "neck_01", "head",
    "upperarm_l", "lowerarm_l", "hand_l",
    "upperarm_r", "lowerarm_r", "hand_r",
    "thigh_l", "calf_l", "foot_l",
    "thigh_r", "calf_r", "foot_r",
]

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

func _finish() -> void:
    if skeleton_count < 1:
        failures.append("no_skeleton")
    if bone_count < 53:
        failures.append("bone_count_too_low:%d" % bone_count)
    if skinned_meshes < 1:
        failures.append("no_skinned_mesh")
    if skinned_surfaces < 1:
        failures.append("no_skinned_surface")
    if material_surfaces != skinned_surfaces:
        failures.append("material_surface_mismatch")
    if vertex_count < 1000:
        failures.append("vertex_count_too_low:%d" % vertex_count)
    if invalid_skeleton_links != 0:
        failures.append("invalid_skeleton_links:%d" % invalid_skeleton_links)
    if missing_material_surfaces != 0:
        failures.append("missing_material_surfaces:%d" % missing_material_surfaces)

    var result := {
        "format": "grand-bruxelles-gate8-variant03-target-integrity-v1",
        "variant": 3,
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
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "retarget_applied": false,
        "visual_approval_claimed": false,
        "failures": failures,
        "state": "TARGET03_INTEGRITY_READY_FOR_PAIRING_PROBE" if failures.is_empty() else "TARGET03_INTEGRITY_BLOCKED",
    }
    var file := FileAccess.open("res://gate8_variant03_target_integrity.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(result, "  ") + "\n")
    file.close()
    print("GATE8_VARIANT03_TARGET_INTEGRITY state=%s bones=%d meshes=%d surfaces=%d materials=%d vertices=%d failures=%d" % [result.state, bone_count, skinned_meshes, skinned_surfaces, material_surfaces, vertex_count, failures.size()])
    quit(0 if failures.is_empty() else 1)
