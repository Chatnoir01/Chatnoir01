extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("CIVILIAN_VEHICLE_SILHOUETTE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var host := Node3D.new()
    root.add_child(host)
    var visual := Node3D.new()
    visual.set_script(load("res://game/scripts/civilian_vehicle_visual.gd"))
    host.add_child(visual)
    for _frame: int in range(3):
        await process_frame

    var shell := visual.get_node_or_null("BodyShell") as MeshInstance3D
    if shell == null:
        _fail("shared renderer has no shaped BodyShell")
        return
    if not (shell.mesh is ArrayMesh):
        _fail("BodyShell must be authored as a faceted ArrayMesh, got %s" % shell.mesh.get_class())
        return
    var cabin := visual.get_node_or_null("GlassHouse") as MeshInstance3D
    if cabin == null or not (cabin.mesh is ArrayMesh):
        _fail("shared renderer has no shaped GlassHouse ArrayMesh")
        return
    for legacy_name: String in ["LowerBody", "Hood", "Cabin"]:
        if visual.get_node_or_null(legacy_name) != null:
            _fail("legacy rectangular mass remains: %s" % legacy_name)
            return
    var wheels := 0
    for child: Node in visual.get_children():
        if child.name == "Wheel":
            wheels += 1
    if wheels != 4:
        _fail("expected 4 wheels, got %d" % wheels)
        return

    print("CIVILIAN_VEHICLE_SILHOUETTE_OK: shell=%s cabin=%s wheels=%d" % [shell.mesh.get_class(), cabin.mesh.get_class(), wheels])
    host.queue_free()
    quit(0)
