extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("CORRIDOR_SHOPFRONT_FRAME_FAIL: %s" % message)
    quit(1)

func _count_prefix(details: Node, prefix: String) -> int:
    var total := 0
    for child: Node in details.get_children():
        if not child.name.begins_with(prefix) or not child is MultiMeshInstance3D:
            continue
        var mm := (child as MultiMeshInstance3D).multimesh
        if mm == null:
            continue
        if not mm.mesh is BoxMesh:
            _fail("%s must use low-cost BoxMesh geometry" % prefix)
            return -1
        total += mm.instance_count
    return total

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame
    await process_frame
    var details := scene.get_node_or_null("BrusselsOSM/GeneratedFacadeDetails")
    if details == null:
        _fail("GeneratedFacadeDetails is missing")
        return
    var shops := details.get_node_or_null("CorridorShopfronts") as MultiMeshInstance3D
    if shops == null or shops.multimesh == null or shops.multimesh.instance_count < 1:
        _fail("baseline shopfront source disappeared")
        return
    var shop_count := shops.multimesh.instance_count
    var headers := _count_prefix(details, "CorridorShopfrontHeaders")
    var jambs := _count_prefix(details, "CorridorShopfrontJambs")
    var mullions := _count_prefix(details, "CorridorShopfrontMullions")
    if headers != shop_count:
        _fail("every shopfront needs one architectural header; shops=%d headers=%d" % [shop_count, headers])
        return
    if jambs != shop_count * 2:
        _fail("every shopfront needs two side jambs; shops=%d jambs=%d" % [shop_count, jambs])
        return
    if mullions != shop_count:
        _fail("every shopfront needs one restrained central mullion; shops=%d mullions=%d" % [shop_count, mullions])
        return
    print("CORRIDOR_SHOPFRONT_FRAME_OK shops=%d headers=%d jambs=%d mullions=%d" % [shop_count, headers, jambs, mullions])
    scene.queue_free()
    quit(0)
