extends SceneTree

const CASES := [
    {
        "autoload": "BrusselsBollardRuntime",
        "script": "res://game/scripts/brussels_bollard_runtime.gd",
        "owned_root": "BrusselsSourceBackedBollards",
        "count_method": "point_count",
        "expected": 27,
    },
    {
        "autoload": "BrusselsStreetLampRuntime",
        "script": "res://game/scripts/brussels_street_lamp_runtime.gd",
        "owned_root": "BrusselsSourceBackedStreetLamps",
        "count_method": "point_count",
        "expected": 8,
    },
    {
        "autoload": "BrusselsCorridorTreeRuntime",
        "script": "res://game/scripts/brussels_corridor_tree_runtime.gd",
        "owned_root": "BrusselsCorridorTrees",
        "count_method": "tree_count",
        "expected": 266,
    },
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("SHARED_ENVIRONMENT_PROP_TEARDOWN_FAIL: %s" % message)
    quit(1)

func _remove_canonical_autoloads() -> void:
    for case: Dictionary in CASES:
        var canonical := root.get_node_or_null(str(case["autoload"]))
        if canonical != null:
            root.remove_child(canonical)

func _new_runtime(case: Dictionary, suffix: String) -> Node:
    var runtime_script := load(str(case["script"])) as Script
    if runtime_script == null:
        _fail("runtime script missing: %s" % str(case["script"]))
        return null
    var runtime := runtime_script.new() as Node
    if runtime == null:
        _fail("runtime is not a Node: %s" % str(case["script"]))
        return null
    runtime.name = "%s_%s" % [str(case["autoload"]), suffix]
    return runtime

func _count(runtime: Node, case: Dictionary) -> int:
    return int(runtime.call(str(case["count_method"])))

func _run() -> void:
    _remove_canonical_autoloads()

    # Phase 1: deferred startup queued before teardown must never bind later.
    var detached_runtimes: Array[Node] = []
    for case: Dictionary in CASES:
        var runtime := _new_runtime(case, "PreBindTeardown")
        if runtime == null:
            return
        root.add_child(runtime)
        root.remove_child(runtime)
        detached_runtimes.append(runtime)

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return
    var scene := packed.instantiate() as Node3D
    if scene == null:
        _fail("production main did not instantiate as Node3D")
        return
    root.add_child(scene)

    if scene.get_node_or_null("BrusselsOSM") == null or scene.get_node_or_null("UrbISMidiExact") == null or scene.get_node_or_null("Player") == null:
        _fail("production scene anchors missing")
        return

    await process_frame
    await process_frame

    for index: int in range(CASES.size()):
        var case: Dictionary = CASES[index]
        var runtime: Node = detached_runtimes[index]
        if scene.get_node_or_null(str(case["owned_root"])) != null:
            _fail("pre-bind teardown later mutated production scene: %s" % str(case["autoload"]))
            return
        if _count(runtime, case) != 0:
            _fail("pre-bind teardown left populated registry: %s count=%d" % [str(case["autoload"]), _count(runtime, case)])
            return

    # Phase 2: a bound autoload owns its generated subtree and must remove it
    # from the still-live Main when the autoload itself leaves the SceneTree.
    for case: Dictionary in CASES:
        var runtime := _new_runtime(case, "BoundTeardown")
        if runtime == null:
            return
        root.add_child(runtime)

        var expected := int(case["expected"])
        for _frame: int in range(40):
            if _count(runtime, case) == expected:
                break
            await process_frame

        if _count(runtime, case) != expected:
            _fail("runtime did not bind before teardown: %s count=%d expected=%d" % [str(case["autoload"]), _count(runtime, case), expected])
            return
        if scene.get_node_or_null(str(case["owned_root"])) == null:
            _fail("runtime-owned root missing before teardown: %s" % str(case["autoload"]))
            return

        root.remove_child(runtime)
        await process_frame
        await process_frame

        if scene.get_node_or_null(str(case["owned_root"])) != null:
            _fail("runtime-owned root survived teardown: %s" % str(case["autoload"]))
            return
        if _count(runtime, case) != 0:
            _fail("runtime registry survived teardown: %s count=%d" % [str(case["autoload"]), _count(runtime, case)])
            return

    print("SHARED_ENVIRONMENT_PROP_TEARDOWN_OK: runtimes=3 no_post_teardown_bind=true owned_root_cleanup=true registries_cleared=true")
    quit(0)
