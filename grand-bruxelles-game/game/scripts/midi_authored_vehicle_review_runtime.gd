extends Node

const MODEL_PATHS: Array[String] = [
    "res://assets/vehicles/kenney_car_kit/models/sedan.glb",
    "res://assets/vehicles/kenney_car_kit/models/hatchback-sports.glb",
    "res://assets/vehicles/kenney_car_kit/models/suv.glb",
    "res://assets/vehicles/kenney_car_kit/models/van.glb",
    "res://assets/vehicles/kenney_car_kit/models/taxi.glb",
]

const AUTHORED_NODE_NAME := "KenneyAuthoredVehicleReview"
const FALLBACK_NODE_NAME := "ProductionVisual"
const TARGET_PREFIXES: Array[String] = ["ParkedCar_", "AmbientTraffic_"]

var _review_enabled := true
var _applied_count := 0


func _ready() -> void:
    _review_enabled = not OS.get_cmdline_user_args().has("--kenney-vehicles-off")
    get_tree().node_added.connect(_on_node_added)
    call_deferred("_scan")


func _on_node_added(node: Node) -> void:
    if node is Node3D and _is_target_name(str(node.name)):
        call_deferred("_try_apply_deferred", node)


func _scan() -> void:
    for node: Node in _walk(get_tree().root):
        if node is Node3D and _is_target_name(str(node.name)):
            apply_to_vehicle(node as Node3D)


func _walk(root: Node) -> Array[Node]:
    var result: Array[Node] = [root]
    for child: Node in root.get_children():
        result.append_array(_walk(child))
    return result


func _try_apply_deferred(node: Node) -> void:
    if is_instance_valid(node) and node is Node3D:
        apply_to_vehicle(node as Node3D)


func apply_to_vehicle(vehicle: Node3D) -> bool:
    if not _is_midi_vehicle(vehicle):
        return false
    var existing := vehicle.get_node_or_null(AUTHORED_NODE_NAME) as Node3D
    if existing != null:
        _set_pair_visibility(vehicle, existing, _review_enabled)
        return true

    var fallback := vehicle.get_node_or_null(FALLBACK_NODE_NAME) as Node3D
    if fallback == null:
        return false

    var fallback_bounds := _combined_aabb_in_space(fallback, vehicle)
    if fallback_bounds.size.length_squared() <= 0.0001:
        return false

    var model_index := _vehicle_index(vehicle) % MODEL_PATHS.size()
    var model_path := MODEL_PATHS[model_index]
    if not ResourceLoader.exists(model_path):
        push_warning("Midi authored vehicle review: model missing: %s" % model_path)
        return false

    var packed := load(model_path) as PackedScene
    if packed == null:
        push_warning("Midi authored vehicle review: model failed to load: %s" % model_path)
        return false

    var imported := packed.instantiate() as Node3D
    if imported == null:
        return false

    var holder := Node3D.new()
    holder.name = AUTHORED_NODE_NAME
    holder.set_meta("source", "Kenney Car Kit CC0")
    holder.set_meta("model_path", model_path)
    holder.set_meta("review_only", true)
    vehicle.add_child(holder)
    holder.add_child(imported)

    var raw_bounds := _combined_aabb_in_space(imported, imported)
    if raw_bounds.size.length_squared() <= 0.0001:
        holder.queue_free()
        return false

    var fallback_long_x := fallback_bounds.size.x > fallback_bounds.size.z
    var imported_long_x := raw_bounds.size.x > raw_bounds.size.z
    var yaw := PI * 0.5 if fallback_long_x != imported_long_x else 0.0
    imported.rotation.y = yaw

    var oriented_bounds := _transform_aabb(raw_bounds, Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO))
    var fallback_length := maxf(fallback_bounds.size.x, fallback_bounds.size.z)
    var imported_length := maxf(oriented_bounds.size.x, oriented_bounds.size.z)
    if imported_length <= 0.001:
        holder.queue_free()
        return false

    var uniform_scale := clampf(fallback_length / imported_length, 0.2, 5.0)
    imported.scale = Vector3.ONE * uniform_scale

    var fallback_center := fallback_bounds.get_center()
    var authored_center := oriented_bounds.get_center() * uniform_scale
    imported.position = Vector3(
        fallback_center.x - authored_center.x,
        fallback_bounds.position.y - oriented_bounds.position.y * uniform_scale,
        fallback_center.z - authored_center.z
    )

    vehicle.set_meta("kenney_authored_vehicle_review", true)
    vehicle.set_meta("kenney_authored_vehicle_model", model_path)
    _set_pair_visibility(vehicle, holder, _review_enabled)
    _applied_count += 1
    return true


func set_review_enabled(enabled: bool) -> void:
    _review_enabled = enabled
    for node: Node in _walk(get_tree().root):
        if node is Node3D and _is_target_name(str(node.name)):
            var holder := node.get_node_or_null(AUTHORED_NODE_NAME) as Node3D
            if holder != null:
                _set_pair_visibility(node as Node3D, holder, enabled)


func review_enabled() -> bool:
    return _review_enabled


func applied_count() -> int:
    return _applied_count


func _set_pair_visibility(vehicle: Node3D, holder: Node3D, authored_visible: bool) -> void:
    holder.visible = authored_visible
    var fallback := vehicle.get_node_or_null(FALLBACK_NODE_NAME) as Node3D
    if fallback != null:
        fallback.visible = not authored_visible


func _is_target_name(value: String) -> bool:
    for prefix: String in TARGET_PREFIXES:
        if value.begins_with(prefix):
            return true
    return false


func _is_midi_vehicle(vehicle: Node3D) -> bool:
    if not _is_target_name(str(vehicle.name)):
        return false
    var cursor: Node = vehicle
    while cursor != null:
        if str(cursor.name) == "MidiUrbanLife":
            return true
        cursor = cursor.get_parent()
    return false


func _vehicle_index(vehicle: Node3D) -> int:
    var parts := str(vehicle.name).split("_")
    if parts.is_empty():
        return 0
    return maxi(int(parts[parts.size() - 1]), 0)


func _combined_aabb_in_space(root: Node3D, space: Node3D) -> AABB:
    var result := AABB()
    var found := false
    var space_inverse := space.global_transform.affine_inverse()
    for node: Node in _walk(root):
        if not node is MeshInstance3D:
            continue
        var mesh_node := node as MeshInstance3D
        if mesh_node.mesh == null:
            continue
        var transform_to_space := space_inverse * mesh_node.global_transform
        var transformed := _transform_aabb(mesh_node.mesh.get_aabb(), transform_to_space)
        if not found:
            result = transformed
            found = true
        else:
            result = result.merge(transformed)
    return result if found else AABB()


func _transform_aabb(source: AABB, transform_value: Transform3D) -> AABB:
    var first := true
    var output := AABB()
    for x: int in range(2):
        for y: int in range(2):
            for z: int in range(2):
                var point := source.position + Vector3(
                    source.size.x * float(x),
                    source.size.y * float(y),
                    source.size.z * float(z)
                )
                var transformed_point := transform_value * point
                if first:
                    output = AABB(transformed_point, Vector3.ZERO)
                    first = false
                else:
                    output = output.expand(transformed_point)
    return output
