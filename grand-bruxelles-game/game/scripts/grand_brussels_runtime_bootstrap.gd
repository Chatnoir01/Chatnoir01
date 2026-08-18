extends Node

const MANIFEST := "res://data/runtime/runtime_registry.json"
const MANIFEST_SCHEMA := "grand-bruxelles-runtime-registry-v1"
const MODULE_SCHEMA := "grand-bruxelles-runtime-module-v1"
const MODULE_DIR := "res://data/runtime/modules"
const SCRIPT_DIR := "res://game/scripts/"

var _done := false
var _failed := false
var _loaded: Array[String] = []
var _expected := 0

func _ready() -> void:
    call_deferred("_boot")

func _stop(message: String) -> void:
    _failed = true
    _done = true
    push_error("Runtime bootstrap: %s" % message)

func _boot() -> void:
    var file := FileAccess.open(MANIFEST, FileAccess.READ)
    if file == null:
        _stop("manifest missing")
        return
    var manifest: Variant = JSON.parse_string(file.get_as_text())
    if not manifest is Dictionary:
        _stop("manifest invalid")
        return
    if str((manifest as Dictionary).get("schema", "")) != MANIFEST_SCHEMA:
        _stop("manifest schema mismatch")
        return
    if str((manifest as Dictionary).get("modules_dir", "")) != MODULE_DIR:
        _stop("module directory mismatch")
        return

    var directory := DirAccess.open(MODULE_DIR)
    if directory == null:
        _stop("module directory missing")
        return
    var files := directory.get_files()
    files.sort()
    var plans: Array[Dictionary] = []
    var names: Dictionary = {}

    for filename: String in files:
        if not filename.ends_with(".json"):
            continue
        var descriptor_file := FileAccess.open(MODULE_DIR.path_join(filename), FileAccess.READ)
        if descriptor_file == null:
            _stop("descriptor unreadable: %s" % filename)
            return
        var value: Variant = JSON.parse_string(descriptor_file.get_as_text())
        if not value is Dictionary:
            _stop("descriptor invalid: %s" % filename)
            return
        var descriptor := value as Dictionary
        if str(descriptor.get("schema", "")) != MODULE_SCHEMA:
            _stop("descriptor schema mismatch: %s" % filename)
            return
        if not bool(descriptor.get("enabled", true)):
            continue
        var module_name := str(descriptor.get("name", "")).strip_edges()
        var resource_path := str(descriptor.get("path", "")).strip_edges()
        if module_name.is_empty() or module_name.contains("/") or names.has(module_name):
            _stop("invalid or duplicate module name: %s" % module_name)
            return
        if not resource_path.begins_with(SCRIPT_DIR) or not resource_path.ends_with(".gd"):
            _stop("module path outside approved game scripts: %s" % resource_path)
            return
        if get_tree().root.get_node_or_null(NodePath(module_name)) != null:
            _stop("module root already exists: %s" % module_name)
            return
        var resource := ResourceLoader.load(resource_path)
        if resource == null or not resource is Script:
            _stop("module script unavailable: %s" % resource_path)
            return
        names[module_name] = true
        plans.append({"name": module_name, "resource": resource})

    var instances: Array[Node] = []
    for plan: Dictionary in plans:
        var script_resource := plan.get("resource") as Script
        var instance := script_resource.new() as Node
        if instance == null:
            _stop("module is not a Node: %s" % str(plan.get("name", "")))
            return
        instance.name = StringName(str(plan.get("name", "")))
        instances.append(instance)

    _expected = instances.size()
    for instance: Node in instances:
        get_tree().root.add_child(instance)
        _loaded.append(str(instance.name))
    _done = true
    print("GRAND_BRUSSELS_RUNTIME_BOOTSTRAP_READY: descriptors=%d loaded=%d" % [_expected, _loaded.size()])

func ready_complete() -> bool:
    return _done

func failed() -> bool:
    return _failed

func descriptor_count() -> int:
    return _expected

func loaded_count() -> int:
    return _loaded.size()

func loaded_names() -> Array[String]:
    return _loaded.duplicate()
