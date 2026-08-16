extends Node3D

@export var player_clearance_m: float = 1.05
@export var car_clearance_m: float = 0.58


func _ready() -> void:
    call_deferred("_snap_spawns")


func _snap_spawns() -> void:
    var terrain = get_node_or_null("LaekenJetteZone/LaekenTerrain")
    if terrain == null or not bool(terrain.get("terrain_loaded")):
        return
    _snap_node($Player, terrain, player_clearance_m)
    _snap_node($PrototypeCar, terrain, car_clearance_m)


func _snap_node(node: Node3D, terrain: Node, clearance: float) -> void:
    if not bool(terrain.call("contains_game_point", node.position.x, node.position.z)):
        return
    var terrain_y := float(terrain.call("sample_height", node.position.x, node.position.z))
    node.position.y = terrain_y + clearance
    print("LAEKEN_PLAYTEST_SPAWN: %s terrain_y=%.3f spawn_y=%.3f" % [node.name, terrain_y, node.position.y])
