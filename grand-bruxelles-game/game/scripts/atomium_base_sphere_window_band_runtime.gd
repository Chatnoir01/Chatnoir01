extends Node

## Registry-mounted Atomium base-sphere glazing cue.
##
## Keep atomium_hero_core.gd byte-stable: this wrapper waits for the production
## AtomiumDirectHero, binds only to its existing Sphere_00 local centre and mounts
## the source-bounded presentation component as a child of the hero. No hero,
## terrain, camera, collision or source position is changed.

const BAND_SCRIPT := preload("res://game/zones/laeken_jette/atomium_base_sphere_window_band.gd")
const HERO_NODE_NAME := "AtomiumDirectHero"
const BASE_SPHERE_NODE_NAME := "Sphere_00"
const BAND_NODE_NAME := "AtomiumBaseSphereWindowBand"
const RUNTIME_APPROVED := false
const REALISM_COMPLETE := false

var _enhanced_enabled := true
var _hero: Node3D = null
var _band: Node3D = null
var _ready_complete := false
var _failed := false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_process(true)

func _process(_delta: float) -> void:
    if _hero != null and not is_instance_valid(_hero):
        _reset_binding()
    if _band != null and not is_instance_valid(_band):
        _band = null
        _ready_complete = false

    if is_instance_valid(_band):
        _band.call("set_enabled", _enhanced_enabled)
        return

    var scene := _find_production_scene()
    if scene == null:
        return
    var hero := scene.get_node_or_null(HERO_NODE_NAME) as Node3D
    if hero == null or not bool(hero.get("hero_built")):
        return
    if _failed and hero == _hero:
        return

    _hero = hero
    var sphere := hero.get_node_or_null(BASE_SPHERE_NODE_NAME) as MeshInstance3D
    if sphere == null or not sphere.mesh is SphereMesh:
        _fail_for_hero("base sphere missing")
        return
    var source_diameter := float(hero.get("source_sphere_diameter_m"))
    if absf(source_diameter - 18.0) > 0.001:
        _fail_for_hero("source sphere diameter drifted")
        return

    var band := BAND_SCRIPT.new() as Node3D
    if band == null:
        _fail_for_hero("band component did not instantiate")
        return
    band.name = BAND_NODE_NAME
    hero.add_child(band)
    if not bool(band.call("build_on_sphere", sphere.position, source_diameter)):
        band.queue_free()
        _fail_for_hero("source-bounded band failed to build")
        return

    band.call("set_enabled", _enhanced_enabled)
    band.set_meta("registry_mounted", true)
    band.set_meta("runtime_approved", RUNTIME_APPROVED)
    band.set_meta("realism_complete", REALISM_COMPLETE)
    band.set_meta("source_geometry_moved", false)
    band.set_meta("collision_changed", false)
    _band = band
    _ready_complete = true
    _failed = false
    print("ATOMIUM_BASE_SPHERE_WINDOW_BAND_REGISTRY_READY: mounted=true sphere=Sphere_00 hero_core_modified=false runtime_approved=false realism_complete=false geometry_moved=false collision_changed=false")

func _find_production_scene() -> Node:
    var scene := get_tree().current_scene
    if scene != null:
        return scene
    for child: Node in get_tree().root.get_children():
        if child.get_node_or_null(HERO_NODE_NAME) != null:
            return child
    return null

func _fail_for_hero(message: String) -> void:
    _failed = true
    _ready_complete = true
    push_error("Atomium base-sphere window-band runtime: %s" % message)

func _reset_binding() -> void:
    _hero = null
    _band = null
    _ready_complete = false
    _failed = false

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    if is_instance_valid(_band):
        _band.call("set_enabled", enabled)

func enhanced_enabled() -> bool:
    return _enhanced_enabled

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func band_node() -> Node3D:
    return _band if is_instance_valid(_band) else null

func hero_node() -> Node3D:
    return _hero if is_instance_valid(_hero) else null

func runtime_approved() -> bool:
    return RUNTIME_APPROVED

func realism_complete() -> bool:
    return REALISM_COMPLETE

func source_geometry_moved() -> bool:
    return false

func collision_changed() -> bool:
    return false

func hero_core_modified() -> bool:
    return false
