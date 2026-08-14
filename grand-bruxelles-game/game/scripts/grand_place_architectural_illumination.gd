extends Node3D

const TARGET_NODE_NAME := "GrandPlaceOfficialLod2"
const SOURCE_PROVIDER := "Beliris"
const SOURCE_URL := "https://www.beliris.be/projets/grand-place.html"
const SQUARE_SIDE_REFERENCE := Vector3(365.0, 1.0, -505.0)
const WASH_COUNT := 4
const WARM_LIGHT := Color(1.0, 0.72, 0.46, 1.0)

var wash_light_count: int = 0
var _presentation_enabled := true
var _installed := false
var _wash_lights: Array[SpotLight3D] = []

func _ready() -> void:
    set_meta("source_provider", SOURCE_PROVIDER)
    set_meta("source_url", SOURCE_URL)
    set_meta("fixture_positions_measured", false)
    set_meta("fixture_count_historic_or_measured", false)
    set_meta("geometry_changed", false)
    set_meta("reusable_family", "brussels_architectural_facade_wash")
    call_deferred("_install_when_ready")

func _install_when_ready() -> void:
    for _attempt: int in range(90):
        var target := get_tree().root.get_node_or_null(TARGET_NODE_NAME)
        if target != null and bool(target.get("geometry_loaded")):
            if _install_on_target(target as Node3D):
                _installed = true
                set_presentation_enabled(_presentation_enabled)
                print("GRAND_PLACE_ARCHITECTURAL_ILLUMINATION_READY: lights=%d source=%s" % [wash_light_count, SOURCE_PROVIDER])
                return
        await get_tree().process_frame
    push_error("Grand-Place architectural illumination could not find loaded Town Hall geometry")

func _find_wall_mesh(target: Node3D) -> MeshInstance3D:
    var stack: Array[Node] = [target]
    while not stack.is_empty():
        var node := stack.pop_back()
        if node is MeshInstance3D:
            var mesh_node := node as MeshInstance3D
            if "WALLSURFACE" in mesh_node.name and mesh_node.mesh != null:
                return mesh_node
        for child: Node in node.get_children():
            stack.append(child)
    return null

func _world_aabb(mesh_node: MeshInstance3D) -> AABB:
    var local := mesh_node.get_aabb()
    var points: Array[Vector3] = []
    for x_index: int in range(2):
        for y_index: int in range(2):
            for z_index: int in range(2):
                var local_point := local.position + Vector3(
                    local.size.x * float(x_index),
                    local.size.y * float(y_index),
                    local.size.z * float(z_index)
                )
                points.append(mesh_node.global_transform * local_point)
    var min_point := points[0]
    var max_point := points[0]
    for point: Vector3 in points:
        min_point = Vector3(min(min_point.x, point.x), min(min_point.y, point.y), min(min_point.z, point.z))
        max_point = Vector3(max(max_point.x, point.x), max(max_point.y, point.y), max(max_point.z, point.z))
    return AABB(min_point, max_point - min_point)

func _install_on_target(target: Node3D) -> bool:
    if _installed:
        return true
    var wall := _find_wall_mesh(target)
    if wall == null:
        return false
    var bounds := _world_aabb(wall)
    if bounds.size.y < 10.0:
        return false

    var center := bounds.position + bounds.size * 0.5
    var toward_square := Vector3(SQUARE_SIDE_REFERENCE.x - center.x, 0.0, SQUARE_SIDE_REFERENCE.z - center.z)
    if toward_square.length() < 0.01:
        return false
    toward_square = toward_square.normalized()
    var tangent := Vector3(-toward_square.z, 0.0, toward_square.x)
    var horizontal_span := max(bounds.size.x, bounds.size.z)
    var fixture_distance := clamp(horizontal_span * 0.15, 7.0, 12.0)
    var low_y := bounds.position.y + max(1.1, bounds.size.y * 0.035)
    var aim_y := bounds.position.y + bounds.size.y * 0.46

    for index: int in range(WASH_COUNT):
        var t := (float(index) / float(WASH_COUNT - 1)) - 0.5
        var light := SpotLight3D.new()
        light.name = "TownHallFacadeWash%02d" % (index + 1)
        light.light_color = WARM_LIGHT
        light.light_energy = 7.5
        light.shadow_enabled = false
        light.spot_range = max(34.0, bounds.size.y + fixture_distance + 8.0)
        light.spot_angle = 41.0
        light.spot_attenuation = 1.15
        light.position = center + toward_square * fixture_distance + tangent * (horizontal_span * t * 0.72)
        light.position.y = low_y
        add_child(light)
        light.look_at(Vector3(center.x, aim_y, center.z) + tangent * (horizontal_span * t * 0.58), Vector3.UP)
        light.set_meta("target_building_id", "https://databrussels.be/id/building/1655673")
        light.set_meta("placement_measured", false)
        light.set_meta("source_provider", SOURCE_PROVIDER)
        _wash_lights.append(light)

    wash_light_count = _wash_lights.size()
    return wash_light_count == WASH_COUNT

func set_presentation_enabled(enabled: bool) -> void:
    _presentation_enabled = enabled
    for light: SpotLight3D in _wash_lights:
        if is_instance_valid(light):
            light.visible = enabled

func presentation_enabled() -> bool:
    return _presentation_enabled
