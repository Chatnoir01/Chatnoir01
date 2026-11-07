extends "res://game/scripts/traffic_manager_official_density_extension.gd"
class_name TrafficManagerRgsdevVehicleExtension

const RGSDEV_VEHICLE_VISUAL_SCRIPT := preload("res://game/scripts/rgsdev_vehicle_visual.gd")
const DRIVABLE_TRAFFIC_VEHICLE_SCRIPT := preload("res://game/scripts/drivable_traffic_vehicle.gd")
const LABO_CIVILIAN_MODEL_CYCLE := [
    "sedan", "sedan", "sedan", "sedan", "sedan", "sedan",
    "hatchback", "suv", "van", "pickup",
]

func _ready() -> void:
    super._ready()
    call_deferred("_upgrade_scene_vehicle_visuals")

func _configure_labo_civilian_visual(visual: Node, serial: int) -> void:
    if visual == null:
        return
    var model_id := str(LABO_CIVILIAN_MODEL_CYCLE[posmod(serial, LABO_CIVILIAN_MODEL_CYCLE.size())])
    visual.call("configure_model", model_id)
    visual.set_meta("labo_vehicle_mix", true)
    visual.set_meta("labo_vehicle_model", model_id)

func get_labo_civilian_model_cycle() -> Array:
    return LABO_CIVILIAN_MODEL_CYCLE.duplicate()

func _static_vehicle_position_respects_player_clearance(candidate_position: Vector3) -> bool:
    var planar_delta := candidate_position - _anchor_position()
    planar_delta.y = 0.0
    return planar_delta.length() >= MIN_SPAWN_CLEARANCE_M

func _create_vehicle_node() -> TrafficVehicleCore:
    var archetype := _choose_archetype()
    var vehicle := DRIVABLE_TRAFFIC_VEHICLE_SCRIPT.new() as TrafficVehicleCore
    vehicle.name = "%s_%03d" % [_archetype_node_prefix(archetype), _spawn_serial]
    vehicle.collision_layer = 1
    vehicle.collision_mask = 1
    vehicle.add_to_group("traffic_vehicle")
    vehicle.add_to_group("traffic_%s" % archetype)
    var body_size := _body_size_for(archetype)
    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var box_shape := BoxShape3D.new()
    box_shape.size = body_size
    collision.shape = box_shape
    vehicle.add_child(collision)
    match archetype:
        "scooter": _add_scooter_visual(vehicle)
        "motorcycle": _add_motorcycle_visual(vehicle)
        _: _add_car_visual(vehicle)
    var obstacle_ray := RayCast3D.new()
    obstacle_ray.name = "ObstacleRay"
    obstacle_ray.position = Vector3(0.0, 0.16, -body_size.z * 0.42)
    obstacle_ray.target_position = Vector3(0.0, 0.0, -9.0)
    obstacle_ray.collision_mask = 1
    obstacle_ray.exclude_parent = true
    obstacle_ray.enabled = true
    vehicle.add_child(obstacle_ray)
    vehicle.configure_archetype(archetype)
    vehicle.set_crossing_system(_crossing_system)
    vehicle.traffic_disabled.connect(_on_traffic_vehicle_disabled)
    _spawn_serial += 1
    return vehicle

func _add_car_visual(vehicle: Node3D) -> void:
    var visual := RGSDEV_VEHICLE_VISUAL_SCRIPT.new()
    visual.name = "RgsdevVisual"
    _configure_labo_civilian_visual(visual, _spawn_serial)
    vehicle.add_child(visual)

func _spawn_parked_vehicle(candidate: Dictionary) -> void:
    var candidate_position: Vector3 = candidate.get("position", Vector3.ZERO)
    if not _static_vehicle_position_respects_player_clearance(candidate_position):
        return

    var body := DRIVABLE_TRAFFIC_VEHICLE_SCRIPT.new()
    body.name = "ParkedCar_%03d" % int(candidate.get("id", 0))
    body.collision_layer = 1
    body.collision_mask = 1
    body.set_meta("parking_candidate_id", int(candidate.get("id", -1)))
    body.set_meta("simulated_occupancy", true)
    body.set_meta("parking_departed", false)
    body.set_meta("road_name", str(candidate.get("road_name", "")))
    body.set_meta("source_osm_id", int(candidate.get("osm_id", 0)))
    body.position = candidate_position
    body.rotation.y = float(candidate.get("yaw", 0.0))
    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var shape := BoxShape3D.new()
    shape.size = PARKED_CAR_SIZE
    collision.shape = shape
    body.add_child(collision)
    var visual := RGSDEV_VEHICLE_VISUAL_SCRIPT.new()
    visual.name = "RgsdevVisual"
    _configure_labo_civilian_visual(visual, int(candidate.get("id", 0)))
    body.add_child(visual)
    body.configure_archetype("car")
    body.call("configure_as_parked")
    _parking_root.add_child(body)

func _replenish_deliveries() -> void:
    if not auto_spawn_runtime or _delivery_root == null or max_delivery_vehicles <= 0:
        return
    var anchor := _anchor_position()
    var eligible: Array[Dictionary] = []
    for candidate: Dictionary in _parking_candidates:
        if not DELIVERY_CLASSES.has(str(candidate.get("road_class", ""))):
            continue
        var position: Vector3 = candidate.get("position", Vector3.ZERO)
        if position.distance_to(anchor) > delivery_spawn_radius_m:
            continue
        if not _static_vehicle_position_respects_player_clearance(position):
            continue
        var candidate_id := int(candidate.get("id", -1))
        if is_parking_candidate_available(candidate_id):
            eligible.append(candidate)
    var attempts := 0
    while get_delivery_vehicle_count() < max_delivery_vehicles and attempts < eligible.size() * 3:
        attempts += 1
        var candidate: Dictionary = eligible[_delivery_rng.randi_range(0, eligible.size() - 1)]
        var candidate_id := int(candidate.get("id", -1))
        var owner := "delivery:%d" % _delivery_serial
        if not reserve_parking_candidate(candidate_id, owner):
            continue
        _spawn_delivery_vehicle(candidate, owner)
        eligible.erase(candidate)
        if eligible.is_empty():
            break

func _spawn_delivery_vehicle(candidate: Dictionary, reservation_owner: String) -> void:
    var candidate_position: Vector3 = candidate.get("position", Vector3.ZERO)
    if not _static_vehicle_position_respects_player_clearance(candidate_position):
        release_parking_candidate(int(candidate.get("id", -1)), reservation_owner)
        return

    var van := DRIVABLE_TRAFFIC_VEHICLE_SCRIPT.new()
    van.name = "DeliveryVan_%03d" % _delivery_serial
    van.collision_layer = 1
    van.collision_mask = 1
    van.position = candidate_position
    van.rotation.y = float(candidate.get("yaw", 0.0))
    van.set_meta("parking_candidate_id", int(candidate.get("id", -1)))
    van.set_meta("reservation_owner", reservation_owner)
    van.set_meta("simulated_delivery", true)
    van.set_meta("road_name", str(candidate.get("road_name", "")))
    van.set_meta("source_osm_id", int(candidate.get("osm_id", 0)))
    var min_duration := maxf(0.1, minf(delivery_duration_min_s, delivery_duration_max_s))
    var max_duration := maxf(min_duration, maxf(delivery_duration_min_s, delivery_duration_max_s))
    van.set_meta("expires_at_s", float(Time.get_ticks_msec()) / 1000.0 + _delivery_rng.randf_range(min_duration, max_duration))
    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var shape := BoxShape3D.new()
    shape.size = DELIVERY_VAN_SIZE
    collision.shape = shape
    van.add_child(collision)
    var visual := RGSDEV_VEHICLE_VISUAL_SCRIPT.new()
    visual.name = "RgsdevVisual"
    visual.call("configure_model", "van")
    van.add_child(visual)
    van.configure_archetype("car")
    van.call("configure_as_parked")
    _delivery_root.add_child(van)
    _delivery_serial += 1

func _occupied_parking_candidate_ids() -> Dictionary:
    var occupied: Dictionary = {}
    if _parking_root == null:
        return occupied
    for child: Node in _parking_root.get_children():
        if child.is_queued_for_deletion() or bool(child.get_meta("parking_departed", false)):
            continue
        occupied[int(child.get_meta("parking_candidate_id", -1))] = true
    return occupied

func get_parked_vehicle_count() -> int:
    if _parking_root == null:
        return 0
    var count := 0
    for child: Node in _parking_root.get_children():
        if not child.is_queued_for_deletion() and not bool(child.get_meta("parking_departed", false)):
            count += 1
    return count

func _despawn_far_vehicles() -> void:
    if _traffic_root == null:
        return
    var anchor := _anchor_position()
    for child: Node in _traffic_root.get_children():
        if child is Node3D and not child.is_queued_for_deletion():
            if child.has_method("has_driver") and bool(child.call("has_driver")):
                continue
            if (child as Node3D).global_position.distance_to(anchor) > despawn_radius_m:
                _intersection_system.call("release_vehicle", child.get_instance_id())
                child.queue_free()

func _despawn_far_parked_vehicles() -> void:
    if _parking_root == null:
        return
    var anchor := _anchor_position()
    var limit := maxf(parking_spawn_radius_m * 1.6, 120.0)
    for child: Node in _parking_root.get_children():
        if child is Node3D and not child.is_queued_for_deletion():
            if child.has_method("has_driver") and bool(child.call("has_driver")):
                continue
            if (child as Node3D).global_position.distance_to(anchor) > limit:
                child.queue_free()

func expire_deliveries_at(now_seconds: float) -> int:
    if _delivery_root == null:
        return 0
    var expired := 0
    for child: Node in _delivery_root.get_children():
        if child.is_queued_for_deletion():
            continue
        if child.has_method("has_driver") and bool(child.call("has_driver")):
            continue
        if now_seconds < float(child.get_meta("expires_at_s", INF)):
            continue
        _release_delivery_slot(child)
        child.queue_free()
        expired += 1
    return expired

func _despawn_far_deliveries() -> void:
    if _delivery_root == null:
        return
    var anchor := _anchor_position()
    var limit := maxf(delivery_spawn_radius_m * 1.7, 140.0)
    for child: Node in _delivery_root.get_children():
        if child is Node3D and not child.is_queued_for_deletion():
            if child.has_method("has_driver") and bool(child.call("has_driver")):
                continue
            if (child as Node3D).global_position.distance_to(anchor) > limit:
                _release_delivery_slot(child)
                child.queue_free()

func _trim_excess_traffic(target: int) -> void:
    if _traffic_root == null:
        return
    var active: Array[Node] = []
    for child: Node in _traffic_root.get_children():
        if child.is_queued_for_deletion():
            continue
        if child.has_method("has_driver") and bool(child.call("has_driver")):
            continue
        active.append(child)
    if active.size() <= target:
        return
    var anchor := _anchor_position()
    active.sort_custom(func(a: Node, b: Node) -> bool:
        if not a is Node3D or not b is Node3D:
            return false
        return (a as Node3D).global_position.distance_to(anchor) > (b as Node3D).global_position.distance_to(anchor)
    )
    for index: int in range(target, active.size()):
        active[index].queue_free()

func cleanup_wrecks_at(now_seconds: float) -> int:
    if _traffic_root == null:
        return 0
    var cleared := 0
    for child: Node in _traffic_root.get_children():
        if child.is_queued_for_deletion() or not bool(child.get_meta("traffic_wrecked", false)):
            continue
        if child.has_method("has_driver") and bool(child.call("has_driver")):
            continue
        var wrecked_at := float(child.get_meta("traffic_wrecked_at_s", now_seconds))
        var delay := float(child.get_meta("traffic_wreck_clear_after_s", wreck_clear_delay_s))
        if now_seconds < wrecked_at + maxf(0.0, delay):
            continue
        child.queue_free()
        cleared += 1
    if cleared > 0 and auto_spawn_runtime:
        call_deferred("_replenish_traffic")
    return cleared

func _upgrade_scene_vehicle_visuals() -> void:
    var world := get_parent()
    if world == null:
        return

    # PhysicalCarB was an A/B physics prototype. Keeping it in the production
    # `vehicle` group gave the player a second, divergent driving model.
    # Remove it entirely at runtime so every selectable production vehicle uses
    # the same drivable traffic contract.
    var physical_prototype := world.get_node_or_null("PhysicalCarB")
    if physical_prototype != null:
        physical_prototype.queue_free()

    var vehicle := world.get_node_or_null("PrototypeCar") as Node3D
    if vehicle == null:
        return
    for legacy_name: String in ["Body", "Cabin", "VisualUpgrade", "ABLabel"]:
        var legacy := vehicle.get_node_or_null(legacy_name)
        if legacy != null:
            legacy.queue_free()
    if vehicle.get_node_or_null("RgsdevVisual") != null:
        return
    var visual := RGSDEV_VEHICLE_VISUAL_SCRIPT.new()
    visual.name = "RgsdevVisual"
    visual.call("configure_model", "sedan")
    visual.set_meta("labo_vehicle_mix", true)
    visual.set_meta("labo_vehicle_model", "sedan")
    vehicle.add_child(visual)
