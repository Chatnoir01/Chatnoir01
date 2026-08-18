extends SceneTree

const AUTOSAVE_PATH := "user://grand_bruxelles_reward_autosave_test.json"
const CHECKPOINTS: Array[Vector3] = [
    Vector3(-272.04, 0.0, -217.07),
    Vector3(81.54, 0.0, -664.58),
    Vector3(319.01, 0.0, -535.20),
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MISSION_REWARD_WALLET_FAIL: %s" % message)
    _cleanup()
    quit(1)

func _primary_vehicle(scene: Node, mission: Node) -> Node3D:
    var vehicle_name := "PrototypeCar"
    if mission.has_method("primary_vehicle_node_name"):
        vehicle_name = str(mission.call("primary_vehicle_node_name"))
    return scene.get_node_or_null(vehicle_name) as Node3D

func _set_vehicle_motion(vehicle: Node3D, linear: Vector3, angular: Vector3 = Vector3.ZERO, scalar_speed: float = 0.0) -> void:
    if vehicle is RigidBody3D:
        var rigid := vehicle as RigidBody3D
        rigid.linear_velocity = linear
        rigid.angular_velocity = angular
    elif vehicle is CharacterBody3D:
        var character := vehicle as CharacterBody3D
        character.velocity = linear
        character.set("speed", scalar_speed)

func _move_vehicle_xz(vehicle: Node3D, target: Vector3) -> void:
    vehicle.global_position = Vector3(target.x, vehicle.global_position.y, target.z)
    _set_vehicle_motion(vehicle, Vector3.ZERO)

func _run() -> void:
    _cleanup()
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    scene.get_node("MissionCheckpointAutosave").set("autosave_path", AUTOSAVE_PATH)
    root.add_child(scene)
    await process_frame
    await physics_frame

    var mission: Node = scene.get_node("MissionDriveToCenter")
    var wallet: Node = scene.get_node("Wallet")
    var runtime: Node = scene.get_node("RuntimeGameplayState")
    var wallet_label: Label = scene.get_node("WalletLabel")
    var mission_label: Label = scene.get_node("MissionLabel")
    var player: CharacterBody3D = scene.get_node("Player")
    var vehicle: Node3D = _primary_vehicle(scene, mission)
    if vehicle == null:
        _fail("mission primary vehicle missing")
        return
    if int(wallet.call("get_cash_cents")) != 0 or wallet_label.text != "0 €":
        _fail("wallet did not start empty")
        return

    vehicle.call("enter_driver", player)
    await physics_frame
    for checkpoint: Vector3 in CHECKPOINTS:
        _move_vehicle_xz(vehicle, checkpoint)
        await physics_frame
        await process_frame

    if int(mission.call("get_stage")) != mission.call("get_stage_count"):
        _fail("mission did not complete through its real checkpoints")
        return
    if int(wallet.call("get_cash_cents")) != 35000:
        _fail("mission reward was not credited exactly once")
        return
    if wallet_label.text != "350 €" or not mission_label.text.contains("Récompense 350 €"):
        _fail("reward is not visible in the HUD")
        return

    await physics_frame
    await physics_frame
    if int(wallet.call("get_cash_cents")) != 35000:
        _fail("completed mission credited a duplicate reward")
        return

    var completed_state: Dictionary = runtime.call("export_state")
    wallet.call("reset")
    if not bool(runtime.call("restore_state", completed_state)):
        _fail("runtime wallet round trip was rejected")
        return
    if int(wallet.call("get_cash_cents")) != 35000 or wallet_label.text != "350 €":
        _fail("runtime restore did not restore wallet and HUD")
        return

    var legacy_runtime := completed_state.duplicate(true)
    legacy_runtime.erase("wallet")
    wallet.call("reset")
    wallet.call("credit", 12500)
    if not bool(runtime.call("can_restore_state", legacy_runtime)) or not bool(runtime.call("restore_state", legacy_runtime)):
        _fail("pre-wallet runtime save is not backward compatible")
        return
    if int(wallet.call("get_cash_cents")) != 12500:
        _fail("pre-wallet runtime save overwrote current cash")
        return

    var legacy_mission := legacy_runtime.duplicate(true)
    legacy_mission["mission"].erase("reward_claimed")
    if not bool(runtime.call("restore_state", legacy_mission)):
        _fail("pre-reward mission state could not load")
        return
    if not bool((mission.call("export_state") as Dictionary).get("reward_claimed", false)):
        _fail("completed legacy mission could claim its reward again")
        return

    var invalid_state := completed_state.duplicate(true)
    invalid_state["wallet"]["cash_cents"] = -1
    var cash_before_rejection := int(wallet.call("get_cash_cents"))
    if bool(runtime.call("can_restore_state", invalid_state)) or bool(runtime.call("restore_state", invalid_state)):
        _fail("negative wallet state was accepted")
        return
    if int(wallet.call("get_cash_cents")) != cash_before_rejection:
        _fail("rejected wallet state mutated live cash")
        return

    scene.queue_free()
    await process_frame
    _cleanup()
    print("MISSION_REWARD_WALLET_OK: reward flow follows mission primary vehicle at physical ride height")
    quit(0)

func _cleanup() -> void:
    var absolute := ProjectSettings.globalize_path(AUTOSAVE_PATH)
    for suffix: String in ["", ".tmp", ".bak"]:
        var candidate := absolute + suffix
        if FileAccess.file_exists(candidate):
            DirAccess.remove_absolute(candidate)
