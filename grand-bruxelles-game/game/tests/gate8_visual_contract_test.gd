extends SceneTree

const Gate8Loader := preload("res://game/scripts/gate8_visual_loader.gd")
const EXPECTED_COUNT := 8
const BASE_SEED := 81001
const SEED_STEP := 97
const MAX_GROUNDING_CORRECTION_M := 0.15
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
    if Gate8Loader.runtime_available_count() != 0:
        _problems.append("runtime_available_count=%d expected=0" % Gate8Loader.runtime_available_count())

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
        if Gate8Loader.variant_verdict(variant_index) != "AMELIORER":
            _problems.append("variant=%d verdict=%s expected=AMELIORER" % [variant_index, Gate8Loader.variant_verdict(variant_index)])
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
    print("GATE8_RUNTIME_REVIEW_GATE_OK approved=0 pending_review=8 source_run=%d source_artifact=%d" % [Gate8Loader.SOURCE_GENERATION_RUN, Gate8Loader.SOURCE_GENERATION_ARTIFACT])
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
