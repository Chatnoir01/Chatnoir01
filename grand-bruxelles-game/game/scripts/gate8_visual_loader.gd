extends RefCounted
class_name Gate8VisualLoader

const ENABLE_SETTING := "grand_bruxelles/npc/gate8_visuals_enabled"
const ASSET_DIR := "res://game/assets/characters/civilians/gate8"
const VARIANT_COUNT := 8
const PROXY_Y_OFFSET := 0.67
# Source generation was rebuilt on #1099 with helpers/masks/shapekeys baked.
# Those bytes have not yet passed a fresh front-facing Godot player-view review,
# so runtime activation must fail closed without prejudging the visual verdict.
const VISUAL_REVIEW_APPROVED_INDICES := []
const VISUAL_REVIEW_VERDICTS := {
    1: "AMELIORER",
    2: "AMELIORER",
    3: "AMELIORER",
    4: "AMELIORER",
    5: "AMELIORER",
    6: "AMELIORER",
    7: "AMELIORER",
    8: "AMELIORER",
}
const SOURCE_GENERATION_RUN := 32552758284
const SOURCE_GENERATION_ARTIFACT := 9470539830

static func enabled() -> bool:
    return bool(ProjectSettings.get_setting(ENABLE_SETTING, false))

static func variant_index_for_seed(seed_value: int) -> int:
    return 1 + posmod(seed_value, VARIANT_COUNT)

static func path_for_seed(seed_value: int) -> String:
    return "%s/npc_gate_%02d.glb" % [ASSET_DIR, variant_index_for_seed(seed_value)]

static func path_for_index(index: int) -> String:
    if index < 1 or index > VARIANT_COUNT:
        return ""
    return "%s/npc_gate_%02d.glb" % [ASSET_DIR, index]

static func variant_verdict(index: int) -> String:
    return str(VISUAL_REVIEW_VERDICTS.get(index, "AMELIORER"))

static func is_variant_approved(index: int) -> bool:
    return index in VISUAL_REVIEW_APPROVED_INDICES and variant_verdict(index) == "GARDER"

static func approved_count() -> int:
    return VISUAL_REVIEW_APPROVED_INDICES.size()

static func available_count() -> int:
    var count := 0
    for index: int in range(1, VARIANT_COUNT + 1):
        if ResourceLoader.exists(path_for_index(index)):
            count += 1
    return count

static func runtime_available_count() -> int:
    var count := 0
    for index: int in VISUAL_REVIEW_APPROVED_INDICES:
        if is_variant_approved(index) and ResourceLoader.exists(path_for_index(index)):
            count += 1
    return count

static func instantiate_for_seed(seed_value: int) -> Node3D:
    if not enabled():
        return null
    var variant_index := variant_index_for_seed(seed_value)
    if not is_variant_approved(variant_index):
        return null
    var path := path_for_index(variant_index)
    if not ResourceLoader.exists(path):
        return null
    var packed := load(path) as PackedScene
    if packed == null:
        return null
    var instance := packed.instantiate() as Node3D
    if instance == null:
        return null
    instance.name = "VisualUpgrade"
    instance.position = Vector3(0.0, -PROXY_Y_OFFSET, 0.0)
    instance.set_meta("gate8_external_visual", true)
    instance.set_meta("gate8_variant_path", path)
    instance.set_meta("gate8_visual_review_verdict", variant_verdict(variant_index))
    instance.set_meta("gate8_animation_retargeted", false)
    instance.set_meta("gate8_grounding_applied", false)
    return instance

static func ground_external_visual(instance: Node3D) -> float:
    if instance == null or not bool(instance.get_meta("gate8_external_visual", false)):
        return 0.0
    if not instance.is_inside_tree():
        push_warning("Gate-8 grounding requested before visual entered SceneTree")
        return 0.0

    var local_min_y := _minimum_mesh_y_relative_to(instance)
    if is_inf(local_min_y):
        push_warning("Gate-8 visual has no MeshInstance3D vertex bounds: %s" % instance.name)
        return 0.0

    # Skinned MeshInstance3D AABBs can include animation envelopes. Ground from
    # actual rest-pose vertices so the floor correction follows source geometry.
    instance.position.y -= local_min_y
    instance.set_meta("gate8_grounding_applied", true)
    instance.set_meta("gate8_grounding_correction_m", -local_min_y)
    instance.set_meta("gate8_grounding_measurement", "rest_vertices")
    return -local_min_y

static func _minimum_mesh_y_relative_to(root: Node3D) -> float:
    var minimum_y := INF
    var root_inverse := root.global_transform.affine_inverse()
    for raw: Node in root.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := raw as MeshInstance3D
        if mesh_instance == null or mesh_instance.mesh == null:
            continue
        var relative_transform := root_inverse * mesh_instance.global_transform
        for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
            var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
            if arrays.size() <= Mesh.ARRAY_VERTEX:
                continue
            var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            for vertex: Vector3 in vertices:
                minimum_y = minf(minimum_y, (relative_transform * vertex).y)
    return minimum_y

static func status() -> Dictionary:
    return {
        "enabled": enabled(),
        "available": runtime_available_count(),
        "source_available": available_count(),
        "approved": approved_count(),
        "pending_review": VARIANT_COUNT - approved_count(),
        "expected": VARIANT_COUNT,
        "asset_dir": ASSET_DIR,
        "source_generation_run": SOURCE_GENERATION_RUN,
        "source_generation_artifact": SOURCE_GENERATION_ARTIFACT,
        "production_activation_blocked": approved_count() == 0,
        "animation_retargeted": false,
        "movement_owner_changed": false,
        "navigation_changed": false,
        "dynamic_grounding": true,
        "grounding_measurement": "rest_vertices",
    }
