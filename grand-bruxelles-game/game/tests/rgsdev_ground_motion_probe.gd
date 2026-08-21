extends SceneTree

const DRIVABLE_SCRIPT := preload("res://game/scripts/drivable_traffic_vehicle.gd")
const VISUAL_SCRIPT := preload("res://game/scripts/rgsdev_vehicle_visual.gd")

func _initialize() -> void:
    quit(0)
