extends SceneTree

const VISUAL_SCRIPT := preload("res://game/scripts/rgsdev_vehicle_visual.gd")
const DRIVABLE_SCRIPT := preload("res://game/scripts/drivable_traffic_vehicle.gd")

func _init() -> void:
    var failures: Array[String] = []
    var visual := VISUAL_SCRIPT.new()
    if visual.MODEL_PATHS.size() != 21:
        failures.append("expected 21 RGSDEV models")
    for model_id: String in visual.MODEL_PATHS.keys():
        var path := str(visual.MODEL_PATHS[model_id])
        if not ResourceLoader.exists(path):
            failures.append("missing model %s at %s" % [model_id, path])
    var vehicle := DRIVABLE_SCRIPT.new()
    if not vehicle.has_method("enter_driver"):
        failures.append("traffic vehicle is not player-drivable")
    if not vehicle.has_method("assign_external_driver") or not vehicle.has_method("set_external_drive_input"):
        failures.append("future NPC driver contract is missing")
    if failures.is_empty():
        print("RGSDEV_VEHICLE_PACK_CONTRACT_OK models=21 player_drive=true npc_drive_contract=true")
        quit(0)
    for failure: String in failures:
        push_error(failure)
    quit(1)
