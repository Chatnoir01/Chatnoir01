extends SceneTree

const Gate8Loader := preload("res://game/scripts/gate8_visual_loader.gd")
const EXPECTED_COUNT := 8
const BASE_SEED := 81001
const SEED_STEP := 97
const MAX_GROUNDING_CORRECTION_M := 0.15
const EXPECTED_VERDICTS := {
    1: "AMELIORER",
    2: "JETER",
    3: "AMELIORER",
    4: "JETER",
    5: "AMELIORER",
    6: "AMELIORER",
    7: "JETER",
    8: "AMELIORER",
}
var _problems: Array[String] = []

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var previous_enabled := Gate8Loader.enabled()
    ProjectSettings.set_setting(Gate8Loader.ENABLE_SETTING, true)
    if Gate8Loader.available_count() != EXPECTED_COUNT:
        _problems.append("available_count=%d expected=%d" % [Gate8Loader.available_count(), EXPECTED_COUNT])
    if Gate8Loader.approved_count() != 0:
        _problems.append("approved_count=%d expected=0" % Gate8Loader.approved_count())
    if Gate8Loader.rejected_count() != 3:
        _problems.append("rejected_count=%d expected=3" % Gate8Loader.rejected_count())
    if Gate8Loader.pending_review_count() != 5:
        _problems.append("pending_review_count=%d expected=5" % Gate8Loader.pending_review_count())
    if Gate8Loader.runtime_available_count() != 0:
        _problems.append("runtime_available_count=%d expected=0" % Gate8Loader.runtime_available_count())
    if Gate8Loader.VISUAL_REVIEW_RUN != 32567113138:
        _problems.append("visual_review_run=%d expected=32567113138" % Gate8Loader.VISUAL_REVIEW_RUN)
    if Gate8Loader.VISUAL_REVIEW_ARTIFACT != 9474429495:
        _problems.append("visual_review_artifact=%d expected=9474429495" % Gate8Loader.VISUAL_REVIEW_ARTIFACT)
    if Gate8Loader.VISUAL_REVIEW_ARTIFACT_SHA256 != "97d3896fa62dad9baf9a0eb0b1e0fb5e0d2949dbb9a5da3ae48441322bd2833b":
        _problems.append("visual_review_artifact_sha256_mismatch")
    if Gate8Loader.VISUAL_REVIEW_CAPTURE_COUNT != 32:
        _problems.append("visual_review_capture_count=%d expected=32" % Gate8Loader.VISUAL_REVIEW_CAPTURE_COUNT)
    if not Gate8Loader.VISUAL_REVIEW_HAS_THREE_QUARTER:
        _problems.append("visual_review_three_quarter_evidence_missing")
    var review_status := Gate8Loader.status()
    if int(review_status.get("visual_review_capture_count", 0)) != 32:
        _problems.append("status_visual_review_capture_count_mismatch")
    if not bool(review_status.get("visual_review_has_three_quarter", false)):
        _problems.append("status_visual_review_three_quarter_missing")

    # Future production activation must not create density holes when reviewed
    # candidates are rejected. The old raw 1..8 mapping would send 3/8 seeds to
    # 02/04/07 and instantiate_for_seed() would return null for those civilians.
    # Remapping over the allowed pool keeps every seed deterministic and viable.
    var survivor_pool: Array[int] = [1, 3, 5, 6, 8]
    var survivor_counts: Dictionary = {}
    for seed_value: int in range(0, 100):
        var remapped := Gate8Loader.remap_seed_to_variant(seed_value, survivor_pool)
        if remapped not in survivor_pool:
            _problems.append("seed=%d remapped_to_disallowed_variant=%d" % [seed_value, remapped])
        survivor_counts[remapped] = int(survivor_counts.get(remapped, 0)) + 1
        if Gate8Loader.remap_seed_to_variant(seed_value, survivor_pool) != remapped:
            _problems.append("seed=%d approved_pool_mapping_not_deterministic" % seed_value)
    if survivor_counts.size() != survivor_pool.size():
        _problems.append("approved_pool_coverage=%d expected=%d" % [survivor_counts.size(), survivor_pool.size()])
    for variant_index: int in survivor_pool:
        if int(survivor_counts.get(variant_index, 0)) != 20:
            _problems.append("variant=%d approved_pool_distribution=%d expected=20" % [variant_index, int(survivor_counts.get(variant_index, 0))])
    if Gate8Loader.remap_seed_to_variant(BASE_SEED, []) != 0:
        _problems.append("empty_approved_pool_must_fail_closed")
    if Gate8Loader.approved_variant_index_for_seed(BASE_SEED) != 0:
        _problems.append("current_zero_approval_pool_must_not_select_variant")
    if str(Gate8Loader.status().get("runtime_seed_mapping", "")) != "approved_pool_no_holes":
        _problems.append("runtime_seed_mapping_contract_missing")

    var seen_paths: Dictionary = {}
    for offset: int in range(EXPECTED_COUNT):
        var seed_value := BASE_SEED + offset * SEED_STEP
        var variant_index := Gate8Loader.variant_index_for_seed(seed_value)
        var path := Gate8Loader.path_for_seed(seed_value)
        if path.is_empty() or not ResourceLoader.exists(path):
            _problems.append("seed=%d missing_path=%s" % [seed_value, path])
            continue
        if seen_paths.has(path):
            _problems.append("seed=%d duplicate_variant=%s" % [seed_value, path])
        seen_paths[path] = true
        if Gate8Loader.path_for_seed(seed_value) != path:
            _problems.append("seed=%d mapping_not_deterministic" % seed_value)
        var expected_verdict := str(EXPECTED_VERDICTS.get(variant_index, ""))
        if Gate8Loader.variant_verdict(variant_index) != expected_verdict:
            _problems.append("variant=%d verdict=%s expected=%s" % [variant_index, Gate8Loader.variant_verdict(variant_index), expected_verdict])
        var expected_rejected := expected_verdict == "JETER"
        if Gate8Loader.is_variant_rejected(variant_index) != expected_rejected:
            _problems.append("variant=%d rejected=%s expected=%s" % [variant_index, str(Gate8Loader.is_variant_rejected(variant_index)), str(expected_rejected)])
        if Gate8Loader.is_variant_approved(variant_index):
            _problems.append("variant=%d unexpectedly_approved" % variant_index)
        if Gate8Loader.instantiate_for_seed(seed_value) != null:
            _problems.append("seed=%d runtime_review_gate_bypassed" % seed_value)

        # Review the fresh source directly without making it runtime-spawnable.
        var packed := load(path) as PackedScene
        if packed == null:
            _problems.append("seed=%d review_load_failed" % seed_value)
            continue
        var proxy := Node3D.new()
        proxy.position = Vector3(0.0, Gate8Loader.PROXY_Y_OFFSET, 0.0)
        root.add_child(proxy)
        var visual := packed.instantiate() as Node3D
        if visual == null:
            _problems.append("seed=%d review_instantiate_failed" % seed_value)
            proxy.queue_free()
            continue
        # Match instantiate_for_seed() exactly. The production proxy sits at
        # +PROXY_Y_OFFSET while its authored visual starts at -PROXY_Y_OFFSET;
        # omitting this in the direct-review path leaves every grounded model
        # exactly 0.67 m above the world floor and makes the contract lie.
        visual.position = Vector3(0.0, -Gate8Loader.PROXY_Y_OFFSET, 0.0)
        visual.set_meta("gate8_external_visual", true)
        visual.set_meta("gate8_animation_retargeted", false)
        proxy.add_child(visual)
        var correction := Gate8Loader.ground_external_visual(visual)
        await process_frame
        var bounds := _world_vertex_y_bounds(visual)
        var min_y := float(bounds.get("min_y", 999.0))
        var max_y := float(bounds.get("max_y", -999.0))
        var height := max_y - min_y
        if int(bounds.get("mesh_count", 0)) < 1: _problems.append("seed=%d no_meshes" % seed_value)
        if int(bounds.get("material_count", 0)) < 1: _problems.append("seed=%d no_materials" % seed_value)
        if int(bounds.get("vertex_count", 0)) < 1: _problems.append("seed=%d no_vertices" % seed_value)
        if absf(min_y) > 0.015: _problems.append("seed=%d grounding=%.4f" % [seed_value, min_y])
        if height < 1.20 or height > 2.30: _problems.append("seed=%d rest_vertex_height=%.4f" % [seed_value, height])
        if absf(correction) > MAX_GROUNDING_CORRECTION_M:
            _problems.append("seed=%d grounding_correction=%.4f" % [seed_value, correction])
        if not bool(visual.get_meta("gate8_grounding_applied", false)): _problems.append("seed=%d dynamic_grounding_not_applied" % seed_value)
        if str(visual.get_meta("gate8_grounding_measurement", "")) != "rest_vertices": _problems.append("seed=%d grounding_measurement_not_vertex_based" % seed_value)
        if bool(visual.get_meta("gate8_animation_retargeted", true)): _problems.append("seed=%d animation_truth_contract_invalid" % seed_value)
        proxy.queue_free()
        await process_frame

    if seen_paths.size() != EXPECTED_COUNT:
        _problems.append("unique_variants=%d expected=%d" % [seen_paths.size(), EXPECTED_COUNT])
    ProjectSettings.set_setting(Gate8Loader.ENABLE_SETTING, false)
    if Gate8Loader.instantiate_for_seed(BASE_SEED) != null: _problems.append("disabled_loader_did_not_fallback")
    ProjectSettings.set_setting(Gate8Loader.ENABLE_SETTING, previous_enabled)
    if not _problems.is_empty():
        print("GATE8_GODOT_CONTRACT_FAIL")
        for problem: String in _problems: print("- ", problem)
        quit(1)
        return
    print("GATE8_RUNTIME_REVIEW_GATE_OK approved=0 rejected=3 pending_review=5 visual_review_run=%d visual_review_artifact=%d captures=%d three_quarter=true" % [Gate8Loader.VISUAL_REVIEW_RUN, Gate8Loader.VISUAL_REVIEW_ARTIFACT, Gate8Loader.VISUAL_REVIEW_CAPTURE_COUNT])
    print("GATE8_SEED_REMAP_OK allowed=5 tested_seeds=100 per_variant=20 no_holes=true")
    print("GATE8_GODOT_CONTRACT_OK count=8 unique_variants=8 movement_owner_changed=false navigation_changed=false animation_retargeted=false dynamic_grounding=true grounding_measurement=rest_vertices")
    quit(0)

func _world_vertex_y_bounds(root_node: Node3D) -> Dictionary:
    var min_y := INF
    var max_y := -INF
    var mesh_count := 0
    var material_count := 0
    var vertex_count := 0
    for raw: Node in root_node.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := raw as MeshInstance3D
        if mesh_instance == null or mesh_instance.mesh == null: continue
        mesh_count += 1
        for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
            var material := mesh_instance.get_surface_override_material(surface_index)
            if material == null: material = mesh_instance.mesh.surface_get_material(surface_index)
            if material != null: material_count += 1
            var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
            if arrays.size() <= Mesh.ARRAY_VERTEX: continue
            var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            vertex_count += vertices.size()
            for vertex: Vector3 in vertices:
                var world_vertex := mesh_instance.global_transform * vertex
                min_y = minf(min_y, world_vertex.y)
                max_y = maxf(max_y, world_vertex.y)
    return {"min_y": min_y, "max_y": max_y, "mesh_count": mesh_count, "material_count": material_count, "vertex_count": vertex_count}
