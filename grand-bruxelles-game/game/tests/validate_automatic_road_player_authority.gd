extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")

func _init() -> void:
    call_deferred("_run")


func _run() -> void:
    var tree_root := root
    var runtime := RUNTIME_SCRIPT.new()
    runtime.name = "AutomaticRoadAuthorityProbe"
    tree_root.add_child(runtime)

    # Foreign recursive decoy: this is exactly what root.find_child("Player",
    # true, false) could capture before the production Main existed.
    var foreign_shell := Node.new()
    foreign_shell.name = "ForeignNested"
    tree_root.add_child(foreign_shell)
    var foreign_main := Node3D.new()
    foreign_main.name = "Main"
    foreign_shell.add_child(foreign_main)
    var foreign_player := CharacterBody3D.new()
    foreign_player.name = "Player"
    foreign_main.add_child(foreign_player)

    var before: Variant = runtime.call("_authoritative_player", tree_root)
    if before != null:
        _fail("foreign nested Player captured authority before production Main")
        return

    # Validated production mount: SceneTree.root -> SubViewport -> Main -> Player.
    var viewport := SubViewport.new()
    viewport.name = "ProductionViewport"
    tree_root.add_child(viewport)
    var production_main := Node3D.new()
    production_main.name = "Main"
    viewport.add_child(production_main)
    var production_player := CharacterBody3D.new()
    production_player.name = "Player"
    production_main.add_child(production_player)

    var resolved: Variant = runtime.call("_authoritative_player", tree_root)
    if resolved != production_player:
        _fail("root-level Viewport -> Main -> Player was not selected")
        return

    # A Player must be the direct child owned by the authoritative Main; another
    # nested homonym inside that Main may not substitute for it.
    production_main.remove_child(production_player)
    production_player.queue_free()
    var nested_shell := Node3D.new()
    nested_shell.name = "Nested"
    production_main.add_child(nested_shell)
    var nested_player := CharacterBody3D.new()
    nested_player.name = "Player"
    nested_shell.add_child(nested_player)
    if runtime.call("_authoritative_player", tree_root) != null:
        _fail("nested Player inside authoritative Main captured direct-child contract")
        return

    print("AUTOMATIC_ROAD_PLAYER_AUTHORITY_OK")
    quit(0)


func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_PLAYER_AUTHORITY_FAIL: %s" % message)
    quit(1)