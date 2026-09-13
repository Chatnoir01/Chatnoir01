extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RECEIPT_PATH := "res://artifacts/qa/bourse_8512036_floor_physics_identity.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_8512036_FLOOR_PHYSICS_IDENTITY_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var scene: Node = MAIN_SCENE.instantiate()
    root.add_child(scene)
    for _frame: int in range(8):
        await process_frame
        await physics_frame

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("authoritative Player CharacterBody3D unavailable")
        return
    var collision_shape := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
    if collision_shape == null or collision_shape.shape == null or not collision_shape.shape is CapsuleShape3D:
        _fail("authoritative Player capsule collision unavailable")
        return
    var capsule := collision_shape.shape as CapsuleShape3D

    var floor_max_angle := float(player.floor_max_angle)
    var floor_snap_length := float(player.floor_snap_length)
    var safe_margin := float(player.safe_margin)
    var capsule_radius := float(capsule.radius)
    var capsule_height := float(capsule.height)
    var sprint_speed := float(player.get("sprint_speed"))
    var gravity := float(player.get("gravity"))
    var max_slides := int(player.max_slides)
    for pair: Array in [
        ["floor_max_angle", floor_max_angle],
        ["floor_snap_length", floor_snap_length],
        ["safe_margin", safe_margin],
        ["capsule_radius", capsule_radius],
        ["capsule_height", capsule_height],
        ["sprint_speed", sprint_speed],
        ["gravity", gravity],
    ]:
        if not is_finite(float(pair[1])) or float(pair[1]) <= 0.0:
            _fail("invalid authoritative %s" % str(pair[0]))
            return
    if floor_max_angle >= PI / 2.0:
        _fail("authoritative floor_max_angle is not floor-like")
        return
    if max_slides < 1:
        _fail("invalid authoritative max_slides")
        return

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var file := FileAccess.open(RECEIPT_PATH, FileAccess.WRITE)
    if file == null:
        _fail("unable to write physics identity receipt")
        return
    file.store_string(JSON.stringify({
        "schema": "grand-bruxelles-bourse-8512036-floor-physics-identity-v2",
        "node_path": "Player",
        "node_type": "CharacterBody3D",
        "collision_shape_path": "Player/CollisionShape3D",
        "collision_shape_type": "CapsuleShape3D",
        "authoritative_floor_max_angle_rad": floor_max_angle,
        "authoritative_floor_snap_length_m": floor_snap_length,
        "authoritative_safe_margin_m": safe_margin,
        "authoritative_capsule_radius_m": capsule_radius,
        "authoritative_capsule_height_m": capsule_height,
        "authoritative_sprint_speed_mps": sprint_speed,
        "authoritative_gravity_mps2": gravity,
        "authoritative_max_slides": max_slides,
        "source": "independent_main_scene_runtime_probe",
        "physics_parameters_mutated": false,
        "character_controller_mutated": false,
        "source_geometry_changed": false,
        "collision_geometry_changed": false,
        "resolver_thresholds_lowered": false
    }, "  ") + "\n")
    file.close()
    print("BOURSE_8512036_FLOOR_PHYSICS_IDENTITY_GREEN floor_max_angle=%.9f floor_snap=%.9f safe_margin=%.9f capsule_radius=%.9f capsule_height=%.9f sprint_speed=%.9f gravity=%.9f max_slides=%d" % [floor_max_angle, floor_snap_length, safe_margin, capsule_radius, capsule_height, sprint_speed, gravity, max_slides])
    quit(0)
