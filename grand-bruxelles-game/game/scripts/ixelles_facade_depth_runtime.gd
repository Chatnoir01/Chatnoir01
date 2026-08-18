extends RefCounted

## Renderer-only authored street-level relief for the existing Ixelles source-backed
## building walls. UrbIS/source-plan footprints and accepted strong-height candidates
## remain the geometry owners. Panel spacing, frame proportions and physical offsets
## below are deliberately presentation conventions: they are not surveyed openings,
## measured facade depth, real materials, or floor-count evidence.

const FAMILY := "ixelles_authored_facade_depth_v1"
const ROOT_NAME := "IxellesAuthoredFacadeDepth"
const MAX_RECESS_PANELS_PER_TARGET := 4200
const MIN_EDGE_LENGTH_M := 3.4
const EDGE_MARGIN_M := 0.55
const TARGET_BAY_SPACING_M := 3.05
const MAX_BAYS_PER_EDGE := 4
const PANEL_HEIGHT_M := 2.20
const PANEL_MIN_WIDTH_M := 1.35
const PANEL_MAX_WIDTH_M := 2.30
const PANEL_DEPTH_M := 0.035
const FRAME_DEPTH_M := 0.14
const HEADER_HEIGHT_M := 0.13
const JAMB_WIDTH_M := 0.11
const PANEL_BASE_OFFSET_M := 0.24
const PANEL_WALL_OFFSET_M := 0.020
const FRAME_WALL_OFFSET_M := 0.065


static func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


static func _unit_multimesh(name: String, transforms: Array[Transform3D], material: Material) -> MultiMeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = Vector3.ONE
    mesh.material = material
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()
    for index: int in range(transforms.size()):
        multimesh.set_instance_transform(index, transforms[index])
    var instance := MultiMeshInstance3D.new()
    instance.name = name
    instance.multimesh = multimesh
    instance.set_meta("family", FAMILY)
    instance.set_meta("presentation_only", true)
    instance.set_meta("renderer_only", true)
    instance.set_meta("collision_changed", false)
    return instance


static func _ring(raw: Variant) -> PackedVector2Array:
    var ring := PackedVector2Array()
    if not raw is Array:
        return ring
    for item: Variant in raw:
        if item is Array and item.size() >= 2:
            ring.append(Vector2(float(item[0]), float(item[1])))
    if ring.size() >= 2 and ring[0].is_equal_approx(ring[ring.size() - 1]):
        ring.remove_at(ring.size() - 1)
    return ring


static func _eligible_heights(height_contract: Dictionary) -> Dictionary:
    var heights: Dictionary = {}
    var records: Variant = height_contract.get("records", [])
    if not records is Array:
        return heights
    for record: Variant in records:
        if not record is Dictionary:
            continue
        if not bool(record.get("visual_runtime_eligible", false)) or bool(record.get("runtime_approved", true)):
            continue
        if float(record.get("abs_delta_m", INF)) > 2.0:
            continue
        if float(record.get("semantic_match_score", -INF)) < 0.90 or float(record.get("semantic_match_margin", -INF)) < 0.25:
            continue
        var building_id := str(record.get("building_id", ""))
        var height := float(record.get("semantic_height_m", 0.0))
        if not building_id.is_empty() and height > 0.0:
            heights[building_id] = height
    return heights


static func _centroid(ring: PackedVector2Array) -> Vector2:
    var center := Vector2.ZERO
    for point: Vector2 in ring:
        center += point
    if not ring.is_empty():
        center /= float(ring.size())
    return center


static func _outward_for_edge(a: Vector2, b: Vector2, center: Vector2) -> Vector2:
    var edge := b - a
    if edge.length_squared() <= 0.000001:
        return Vector2.ZERO
    var normal := Vector2(-edge.y, edge.x).normalized()
    var midpoint := (a + b) * 0.5
    if (midpoint + normal * 0.25).distance_to(center) < midpoint.distance_to(center):
        normal = -normal
    return normal


static func _base_y(point: Vector2, sampler: Callable, fallback_base_y: float) -> float:
    if sampler.is_valid():
        var sampled: Variant = sampler.call(point)
        if sampled is float or sampled is int:
            var value := float(sampled)
            if is_finite(value):
                return value
    return fallback_base_y


static func _build_feature_transforms(
    ring: PackedVector2Array,
    semantic_height: float,
    sampler: Callable,
    fallback_base_y: float,
    panels: Array[Transform3D],
    headers: Array[Transform3D],
    jambs: Array[Transform3D]
) -> void:
    if ring.size() < 3 or semantic_height < PANEL_HEIGHT_M + 0.6:
        return
    var center := _centroid(ring)
    for edge_index: int in range(ring.size()):
        if panels.size() >= MAX_RECESS_PANELS_PER_TARGET:
            return
        var a := ring[edge_index]
        var b := ring[(edge_index + 1) % ring.size()]
        var edge := b - a
        var edge_length := edge.length()
        if edge_length < MIN_EDGE_LENGTH_M:
            continue
        var tangent := edge / edge_length
        var outward := _outward_for_edge(a, b, center)
        if outward.length_squared() <= 0.5:
            continue
        var available := edge_length - EDGE_MARGIN_M * 2.0
        if available <= PANEL_MIN_WIDTH_M:
            continue
        var bay_count := clampi(int(floor(available / TARGET_BAY_SPACING_M)), 1, MAX_BAYS_PER_EDGE)
        var bay_span := available / float(bay_count)
        var panel_width := clampf(bay_span * 0.70, PANEL_MIN_WIDTH_M, PANEL_MAX_WIDTH_M)
        var tangent3 := Vector3(tangent.x, 0.0, tangent.y)
        var outward3 := Vector3(outward.x, 0.0, outward.y)
        var rotation := Basis(tangent3, Vector3.UP, outward3).orthonormalized()
        var side_offset := panel_width * 0.5 + JAMB_WIDTH_M * 0.46
        var panel_center_y := PANEL_BASE_OFFSET_M + PANEL_HEIGHT_M * 0.5
        for bay_index: int in range(bay_count):
            if panels.size() >= MAX_RECESS_PANELS_PER_TARGET:
                return
            var along := EDGE_MARGIN_M + (float(bay_index) + 0.5) * bay_span
            var point := a + tangent * along
            var ground_y := _base_y(point, sampler, fallback_base_y)
            var origin := Vector3(point.x, ground_y + panel_center_y, point.y)
            panels.append(Transform3D(rotation.scaled(Vector3(panel_width, PANEL_HEIGHT_M, PANEL_DEPTH_M)), origin + outward3 * PANEL_WALL_OFFSET_M))
            headers.append(Transform3D(rotation.scaled(Vector3(panel_width + 0.22, HEADER_HEIGHT_M, FRAME_DEPTH_M)), origin + Vector3.UP * (PANEL_HEIGHT_M * 0.5 + HEADER_HEIGHT_M * 0.45) + outward3 * FRAME_WALL_OFFSET_M))
            var jamb_scale := Vector3(JAMB_WIDTH_M, PANEL_HEIGHT_M + 0.10, FRAME_DEPTH_M)
            jambs.append(Transform3D(rotation.scaled(jamb_scale), origin + tangent3 * side_offset + outward3 * FRAME_WALL_OFFSET_M))
            jambs.append(Transform3D(rotation.scaled(jamb_scale), origin - tangent3 * side_offset + outward3 * FRAME_WALL_OFFSET_M))


static func build_from_contract(
    parent: Node3D,
    cell_contract: Dictionary,
    height_contract: Dictionary,
    base_sampler: Callable = Callable(),
    fallback_base_y: float = 0.04,
    scope_id: String = ""
) -> Dictionary:
    var existing := parent.get_node_or_null(ROOT_NAME)
    if existing != null:
        return {
            "panels": int(existing.get_meta("recess_panels", 0)),
            "headers": int(existing.get_meta("headers", 0)),
            "jambs": int(existing.get_meta("jambs", 0)),
            "source_buildings": int(existing.get_meta("source_buildings", 0)),
        }

    var heights := _eligible_heights(height_contract)
    var buildings: Variant = cell_contract.get("buildings", [])
    if not buildings is Array or heights.is_empty():
        return {"panels": 0, "headers": 0, "jambs": 0, "source_buildings": 0}

    var panels: Array[Transform3D] = []
    var headers: Array[Transform3D] = []
    var jambs: Array[Transform3D] = []
    var source_buildings := 0
    for feature: Variant in buildings:
        if not feature is Dictionary:
            continue
        var building_id := str(feature.get("id", ""))
        if not heights.has(building_id):
            continue
        var ring := _ring(feature.get("footprint", []))
        if ring.size() < 3:
            continue
        source_buildings += 1
        _build_feature_transforms(ring, float(heights[building_id]), base_sampler, fallback_base_y, panels, headers, jambs)
        if panels.size() >= MAX_RECESS_PANELS_PER_TARGET:
            break

    if panels.is_empty():
        return {"panels": 0, "headers": 0, "jambs": 0, "source_buildings": source_buildings}

    var root := Node3D.new()
    root.name = ROOT_NAME
    root.set_meta("family", FAMILY)
    root.set_meta("scope_id", scope_id)
    root.set_meta("presentation_only", true)
    root.set_meta("renderer_only", true)
    root.set_meta("source_geometry_changed", false)
    root.set_meta("collision_changed", false)
    root.set_meta("surveyed_openings_claimed", false)
    root.set_meta("exact_depth_claimed", false)
    root.set_meta("floor_count_claimed", false)
    root.set_meta("building_material_claimed", false)
    root.set_meta("new_building_footprints_added", false)
    root.set_meta("recess_panels", panels.size())
    root.set_meta("headers", headers.size())
    root.set_meta("jambs", jambs.size())
    root.set_meta("source_buildings", source_buildings)

    var panel_material := _material(Color(0.065, 0.105, 0.125, 1.0), 0.42, 0.08)
    var frame_material := _material(Color(0.43, 0.395, 0.35, 1.0), 0.84, 0.02)
    root.add_child(_unit_multimesh("RecessPanels", panels, panel_material))
    root.add_child(_unit_multimesh("Headers", headers, frame_material))
    root.add_child(_unit_multimesh("Jambs", jambs, frame_material))
    parent.add_child(root)

    return {
        "panels": panels.size(),
        "headers": headers.size(),
        "jambs": jambs.size(),
        "source_buildings": source_buildings,
    }
