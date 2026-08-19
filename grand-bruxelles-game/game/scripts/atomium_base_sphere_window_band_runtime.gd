extends Node

## Registry-mounted Atomium base-sphere glazing cue.
## Keeps the source hero core untouched: this module waits for the production
## AtomiumDirectHero, binds only to its existing Sphere_00, then mounts the
## semantics-only presentation component as a child of the hero.

const BAND_SCRIPT := preload("res://game/zones/laeken_jette/atomium_base_sphere_window_band.gd")
const HERO_NODE_NAME := "AtomiumDirectHero"
const BASE_SPHERE_NODE_NAME := "Sphere_00"
const EXPECTED_SPHERE_DIAMETER_M := 18.0
const EXPECTED_BASE_CENTER := Vector3(0.0, 9.0, 0.0)
const RUNTIME_APPROVED := false
const REALISM_COMPLETE := false

var _band: Node3D = null
var _hero: Node3D = null
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_process(true)

func _process(_delta: float) -> void:
    if _band != null and not is_instance_valid(_band):
        _band = null
        _hero = null
        _ready_complete = false
        _failed = false

    if is_instance_valid(_band):
        _band.call("set_enabled", _enhanced_enabled)
        return

    var scene := get_tree().current_scene
    if scene == null:
        return
    var hero := scene.get_node_or_null(HERO_NODE_NAME) as Node3D
    if hero == null or not bool(hero.get("hero_built")):
        return

    var base_sphere := hero.get_node_or_null(BASE_SPHERE_NODE_NAME) as MeshInstance3D
    if base_sphere == null:
        _fail_mount("production Sphere_00 missing")
        return
    var diameter := float(hero.get("source_sphere_diameter_m"))
    if absf(diameter - EXPECTED_SPHERE_DIAMETER_M) > 0.001:
        _fail_mount("production sphere diameter drifted")
        return
    if base_sphere.position.distance_to(EXPECTED_BASE_CENTER) > 0.001:
        _fail_mount("production Sphere_00 local centre drifted")
        return

    var band := BAND_SCRIPT.new() as Node3D
    if band == null:
        _fail_mount("window-band component did not instantiate")
        return
    band.name = "AtomiumBaseSphereWindowBand"
    hero.add_child(band)
    if not bool(band.call("build_on_sphere", base_sphere.position, diameter)):
        band.queue_free()
        _fail_mount("window-band component failed to build")
        return

    band.call("set_enabled", _enhanced_enabled)
    band.set_meta("registry_mounted", true)
    band.set_meta("runtime_approved", RUNTIME_APPROVED)
    band.set_meta("realism_complete", REALISM_COMPLETE)
    band.set_meta("source_position_changed", false)
    band.set_meta("collision_changed", false)
    _band = band
    _hero = hero
    _ready_complete = true
    _failed = false
    print("ATOMIUM_BASE_SPHERE_WINDOW_BAND_REGISTRY_READY: mounted=true sphere=Sphere_00 runtime_approved=false realism_complete=false position_changed=false collision_changed=false")

func _fail_mount(message: String) -> void:
    _failed = true
    _ready_complete = true
    set_process(false)
    push_error("Atomium base-sphere glazing runtime: %s" % message)

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

func source_position_changed() -> bool:
    return false

func collision_changed() -> bool:
    return false
