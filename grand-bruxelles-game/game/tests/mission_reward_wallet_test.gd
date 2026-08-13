extends SceneTree

const AUTOSAVE_PATH := "user://grand_bruxelles_reward_autosave_test.json"
const CHECKPOINTS: Array[Vector3] = [
    Vector3(-272.04, 0.08, -217.07),
    Vector3(81.54, 0.08, -664.58),
    Vector3(319.01, 0.08, -535.20),
]


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MISSION_REWARD_WALLET_FAIL: %s" % message)
    _cleanup()
    quit(1)


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
    var vehicle: CharacterBody3D = scene.get_node("PrototypeCar")
    if int(wallet.call("get_cash_cents")) != 0 or wallet_label.text != "0 €":
        _fail("wallet did not start empty")
        return

    vehicle.call("enter_driver", player)
    await physics_frame
    for checkpoint: Vector3 in CHECKPOINTS:
        vehicle.global_position = checkpoint
        vehicle.velocity = Vector3.ZERO
        vehicle.set("speed", 0.0)
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
    if not bool(runtime.call("can_restore_state", legacy_runtime)):
        _fail("pre-wallet runtime save is not backward compatible")
        return
    if not bool(runtime.call("restore_state", legacy_runtime)):
        _fail("pre-wallet runtime save could not load")
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
    if bool(runtime.call("can_restore_state", invalid_state)):
        _fail("negative wallet passed restore precheck")
        return
    if bool(runtime.call("restore_state", invalid_state)):
        _fail("negative wallet state was restored")
        return
    if int(wallet.call("get_cash_cents")) != cash_before_rejection:
        _fail("rejected wallet state mutated live cash")
        return

    scene.queue_free()
    await process_frame
    _cleanup()
    print("MISSION_REWARD_WALLET_OK")
    quit(0)


func _cleanup() -> void:
    var absolute := ProjectSettings.globalize_path(AUTOSAVE_PATH)
    for suffix: String in ["", ".tmp", ".bak"]:
        var candidate := absolute + suffix
        if FileAccess.file_exists(candidate):
            DirAccess.remove_absolute(candidate)
