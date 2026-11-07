extends RefCounted
class_name Gate8VisualLoader

const ENABLE_SETTING := "grand_bruxelles/npc/gate8_visuals_enabled"
const ASSET_DIR := "res://game/assets/characters/civilians/gate8"
const VARIANT_COUNT := 8
const PROXY_Y_OFFSET := 0.67
# Source generation was rebuilt on #1099 with helpers/masks/shapekeys baked.
# The isolated Godot 4.7.1 player-view review is anchored to run 32567113138:
# 32 exact 1280x720 PNGs = front 2m/5m/8m + three-quarter 2m for all 8.
# Three-quarter review confirms 02/04/07 remain rejected for obvious body/clothing
# fit defects. The remaining five are visually viable enough to continue only to
# the separate idle/walk/run + grounding/foot-slide gate; none is production-approved.
const VISUAL_REVIEW_APPROVED_INDICES := []
const VISUAL_REVIEW_REJECTED_INDICES := [2, 4, 7]
const VISUAL_REVIEW_VERDICTS := {
    1: "AMELIORER",
    2: "JETER",
    3: "AMELIORER",
    4: "JETER",
    5: "AMELIORER",
    6: "AMELIORER",
    7: "JETER",
    8: "AMELIORER",
}
const VISUAL_REVIEW_REASONS := {
    1: "static_pose_dynamic_locomotion_gate_pending",
    2: "body_clothing_fit_reject_confirmed_front_and_three_quarter",
    3: "static_pose_dynamic_locomotion_gate_pending",
    4: "body_clothing_fit_reject_confirmed_front_and_three_quarter",
    5: "static_pose_dynamic_locomotion_gate_pending",
    6: "static_pose_dynamic_locomotion_gate_pending",
    7: "body_clothing_fit_reject_confirmed_front_and_three_quarter",
    8: "static_pose_dynamic_locomotion_gate_pending",
}
const SOURCE_GENERATION_RUN := 32552758284
const SOURCE_GENERATION_ARTIFACT := 9470539830
const VISUAL_REVIEW_RUN := 32567113138
const VISUAL_REVIEW_ARTIFACT := 9474429495
const VISUAL_REVIEW_ARTIFACT_SHA256 := "97d3896fa62dad9baf9a0eb0b1e0fb5e0d2949dbb9a5da3ae48441322bd2833b"
const VISUAL_REVIEW_CAPTURE_COUNT := 32
const VISUAL_REVIEW_HAS_THREE_QUARTER := true

static func enabled() -> bool:
    return bool(ProjectSettings.get_setting(ENABLE_SETTING, false))

static func variant_index_for_seed(seed_value: int) -> int:
    return 1 + posmod(seed_value, VARIANT_COUNT)

static func remap_seed_to_variant(seed_value: int, allowed_indices: Array[int]) -> int:
    if allowed_indices.is_empty():
        return 0
    return allowed_indices[posmod(seed_value, allowed_indices.size())]

static func approved_variant_indices() -> Array[int]:
    var indices: Array[int] = []
    for index: int in VISUAL_REVIEW_APPROVED_INDICES:
        if is_variant_approved(index):
            indices.append(index)
    return indices

static func approved_variant_index_for_seed(seed_value: int) -> int:
    return remap_seed_to_variant(seed_value, approved_variant_indices())

static func path_for_seed(seed_value: int) -> String:
    return "%s/npc_gate_%02d.glb" % [ASSET_DIR, variant_index_for_seed(seed_value)]

static func path_for_index(index: int) -> String:
    if index < 1 or index > VARIANT_COUNT:
        return ""
    return "%s/npc_gate_%02d.glb" % [ASSET_DIR, index]

static func variant_verdict(index: int) -> String:
    return str(VISUAL_REVIEW_VERDICTS.get(index, "AMELIORER"))

static func variant_review_reason(index: int) -> String:
    return str(VISUAL_REVIEW_REASONS.get(index, "review_reason_missing"))

static func is_variant_approved(index: int) -> bool:
    return index in VISUAL_REVIEW_APPROVED_INDICES and variant_verdict(index) == "GARDER"

static func is_variant_rejected(index: int) -> bool:
    return index in VISUAL_REVIEW_REJECTED_INDICES and variant_verdict(index) == "JETER"

static func approved_count() -> int:
    return approved_variant_indices().size()

static func rejected_count() -> int:
    return VISUAL_REVIEW_REJECTED_INDICES.size()

static func pending_review_count() -> int:
    return VARIANT_COUNT - approved_count() - rejected_count()

static func available_count() -> int:
    var count := 0
    for index: int in range(1, VARIANT_COUNT + 1):
        if ResourceLoader.exists(path_for_index(index)):
            count += 1
    return count

static func runtime_available_count() -> int:
    var count := 0
    for index: int in approved_variant_indices():
        if ResourceLoader.exists(path_for_index(index)):
            count += 1
    return count

static func instantiate_for_seed(seed_value: int) -> Node3D:
    if not enabled():
        return null
    var variant_index := approved_variant_index_for_seed(seed_value)
    if variant_index == 0:
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
    instance.set_meta("gate8_visual_review_reason", variant_review_reason(variant_index))
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
        "rejected": rejected_count(),
        "pending_review": pending_review_count(),
        "expected": VARIANT_COUNT,
        "asset_dir": ASSET_DIR,
        "source_generation_run": SOURCE_GENERATION_RUN,
        "source_generation_artifact": SOURCE_GENERATION_ARTIFACT,
        "visual_review_run": VISUAL_REVIEW_RUN,
        "visual_review_artifact": VISUAL_REVIEW_ARTIFACT,
        "visual_review_artifact_sha256": VISUAL_REVIEW_ARTIFACT_SHA256,
        "visual_review_capture_count": VISUAL_REVIEW_CAPTURE_COUNT,
        "visual_review_has_three_quarter": VISUAL_REVIEW_HAS_THREE_QUARTER,
        "production_activation_blocked": approved_count() == 0,
        "runtime_seed_mapping": "approved_pool_no_holes",
        "animation_retargeted": false,
        "movement_owner_changed": false,
        "navigation_changed": false,
        "dynamic_grounding": true,
        "grounding_measurement": "rest_vertices",
    }
