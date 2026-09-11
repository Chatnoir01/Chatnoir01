extends Node

## Renderer-only bridge for the first close-camera authored civilian car witness.
## It never changes the vehicle body, physics, collision, controls, traffic or geography.
## The procedural production visual is hidden only after a valid authored mesh mounts.

const MODEL_PATH := "res://assets/vehicles/mmc_generic_sedan/generic_sedan.glb"
const SOURCE_URL := "https://sketchfab.com/3d-models/generic-sedan-car-58c33766470d46e7b2aed542650494e5"
const SOURCE_AUTHOR := "MMC Works"
const SOURCE_LICENSE := "CC Attribution"
const AUTHORED_NODE_NAME := "MMCGenericSedanCAR1"
const FALLBACK_NODE_NAME := "VisualUpgrade"
const TARGET_VEHICLE_NAME := "PhysicalCarB"
const REVIEW_OFF_ARG := "--mmc-sedan-off"
const EXPECTED_TRIANGLES := 113200

var _review_enabled := true
var _mount_attempted := false
var _mount_succeeded := false
var _mount_reason := "not_attempted"


func _ready() -> void:
    _review_enabled = not OS.get_cmdline_user_args().has(REVIEW_OFF_ARG)
    get_tree().node_added.connect(_on_node_added)
    call_deferred("_scan")


func _on_node_added(node: Node) -> void:
    if node is Node3D and str(node.name) == TARGET_VEHICLE_NAME:
        call_deferred("_try_apply_deferred", node)


func _try_apply_deferred(node: Node) -> void:
    if is_instance_valid(node) and node is Node3D:
        apply_to_vehicle(node as Node3D)


func _scan() -> void:
    var root_node := get_tree().root
    if root_node == null:
        return
    for node: Node in _walk(root_node):
        if node is Node3D and str(node.name) == TARGET_VEHICLE_NAME:
            apply_to_vehicle(node as Node3D)


func apply_to_vehicle(vehicle: Node3D) -> bool:
    if str(vehicle.name) != TARGET_VEHICLE_NAME:
        _mount_reason = "wrong_target"
        return false

    var existing := vehicle.get_node_or_null(AUTHORED_NODE_NAME) as Node3D
    if existing != null:
        _set_pair_visibility(vehicle, existing, _review_enabled)
        _mount_succeeded = true
        _mount_reason = "already_mounted"
        return true

    _mount_attempted = true

    var fallback := vehicle.get_node_or_null(FALLBACK_NODE_NAME) as Node3D
    if fallback == null:
        _mount_reason = "fallback_missing"
        return false

    # Fail closed while the authenticated official asset download is pending.
    if not ResourceLoader.exists(MODEL_PATH):
        fallback.visible = true
        _mount_reason = "official_asset_missing"
        return false

    var packed := load(MODEL_PATH) as PackedScene
    if packed == null:
        fallback.visible = true
        _mount_reason = "asset_load_failed"
        return false

    var imported := packed.instantiate() as Node3D
    if imported == null:
        fallback.visible = true
        _mount_reason = "asset_instantiate_failed"
        return false

    var holder := Node3D.new()
    holder.name = AUTHORED_NODE_NAME
    holder.set_meta("source_url", SOURCE_URL)
    holder.set_meta("source_author", SOURCE_AUTHOR)
    holder.set_meta("source_license", SOURCE_LICENSE)
    holder.set_meta("expected_triangles", EXPECTED_TRIANGLES)
    holder.set_meta("renderer_only", true)
    holder.set_meta("production_authorized", false)
    holder.set_meta("owner_review_required", true)
    vehicle.add_child(holder)
    holder.add_child(imported)

    var raw_bounds := _combined_aabb_in_space(imported, imported)
    if raw_bounds.size.length_squared() <= 0.0001:
        holder.queue_free()
        fallback.visible = true
        _mount_reason = "asset_mesh_bounds_empty"
        return false

    var fallback_bounds := _combined_aabb_in_space(fallback, vehicle)
    var target_length := 4.28
    var target_floor_y := -0.60
    var target_center_xz := Vector2.ZERO
    if fallback_bounds.size.length_squared() > 0.0001:
        target_length = maxf(fallback_bounds.size.x, fallback_bounds.size.z)
        target_floor_y = fallback_bounds.position.y
        var fallback_center := fallback_bounds.get_center()
        target_center_xz = Vector2(fallback_center.x, fallback_center.z)

    # Detect whether the imported package uses X or Z as its longitudinal axis.
    var imported_long_x := raw_bounds.size.x > raw_bounds.size.z
    var yaw := PI * 0.5 if imported_long_x else 0.0
    imported.rotation.y = yaw

    var oriented_bounds := _transform_aabb(
        raw_bounds,
        Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
    )
    var imported_length := maxf(oriented_bounds.size.x, oriented_bounds.size.z)
    if imported_length <= 0.001:
        holder.queue_free()
        fallback.visible = true
        _mount_reason = "asset_length_invalid"
        return false

    var uniform_scale := clampf(target_length / imported_length, 0.05, 20.0)
    imported.scale = Vector3.ONE * uniform_scale

    var authored_center := oriented_bounds.get_center() * uniform_scale
    imported.position = Vector3(
        target_center_xz.x - authored_center.x,
        target_floor_y - oriented_bounds.position.y * uniform_scale,
        target_center_xz.y - authored_center.z
    )

    holder.set_meta("raw_aabb", raw_bounds)
    holder.set_meta("oriented_aabb", oriented_bounds)
    holder.set_meta("uniform_scale", uniform_scale)
    holder.set_meta("yaw_radians", yaw)
    holder.set_meta("target_length_m", target_length)

    vehicle.set_meta("mmc_generic_sedan_car1", true)
    vehicle.set_meta("mmc_generic_sedan_model", MODEL_PATH)
    vehicle.set_meta("mmc_generic_sedan_renderer_only", true)

    _set_pair_visibility(vehicle, holder, _review_enabled)
    _mount_succeeded = true
    _mount_reason = "mounted"
    print("MMC_GENERIC_SEDAN_CAR1_READY: target=%s model=%s scale=%.5f yaw=%.3f" % [
        str(vehicle.name), MODEL_PATH, uniform_scale, yaw
    ])
    return true


func set_review_enabled(enabled: bool) -> void:
    _review_enabled = enabled
    var root_node := get_tree().root
    if root_node == null:
        return
    for node: Node in _walk(root_node):
        if node is Node3D and str(node.name) == TARGET_VEHICLE_NAME:
            var vehicle := node as Node3D
            var holder := vehicle.get_node_or_null(AUTHORED_NODE_NAME) as Node3D
            if holder != null:
                _set_pair_visibility(vehicle, holder, enabled)


func review_enabled() -> bool:
    return _review_enabled


func mount_attempted() -> bool:
    return _mount_attempted


func mount_succeeded() -> bool:
    return _mount_succeeded


func mount_reason() -> String:
    return _mount_reason


func model_available() -> bool:
    return ResourceLoader.exists(MODEL_PATH)


func get_contract() -> Dictionary:
    return {
        "target": TARGET_VEHICLE_NAME,
        "model_path": MODEL_PATH,
        "source_url": SOURCE_URL,
        "source_author": SOURCE_AUTHOR,
        "source_license": SOURCE_LICENSE,
        "expected_triangles": EXPECTED_TRIANGLES,
        "renderer_only": true,
        "changes_physics": false,
        "changes_collision": false,
        "changes_traffic": false,
        "changes_geography": false,
        "fallback_required": true,
        "production_authorized": false,
    }


func _set_pair_visibility(vehicle: Node3D, holder: Node3D, authored_visible: bool) -> void:
    holder.visible = authored_visible
    var fallback := vehicle.get_node_or_null(FALLBACK_NODE_NAME) as Node3D
    if fallback != null:
        fallback.visible = not authored_visible


func _walk(root_node: Node) -> Array[Node]:
    var result: Array[Node] = [root_node]
    for child: Node in root_node.get_children():
        result.append_array(_walk(child))
    return result


func _combined_aabb_in_space(root_node: Node3D, space: Node3D) -> AABB:
    var result := AABB()
    var found := false
    var space_inverse := space.global_transform.affine_inverse()
    for node: Node in _walk(root_node):
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
