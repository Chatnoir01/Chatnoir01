extends Node
class_name BrusselsSharedRailSurfaceRuntime

const MATERIAL_FAMILY := "brussels_shared_rail_surface_v1"
const TARGET_ROOT := "GeneratedRails"
const MAX_APPLY_ATTEMPTS := 240

var _rail_material: Material
var _sleeper_material: Material
var _legacy_materials: Dictionary = {}
var _targets: Array[CSGBox3D] = []
var _attempts := 0
var _ready_applied := false

func _ready() -> void:
    _rail_material = BrusselsSharedRailMaterial.create_rail_material()
    _sleeper_material = BrusselsSharedRailMaterial.create_sleeper_material()
    set_process(true)

func _process(_delta: float) -> void:
    if _ready_applied:
        set_process(false)
        return
    _attempts += 1
    var rails_root := _find_named_node(get_tree().root, TARGET_ROOT)
    if rails_root == null:
        if _attempts >= MAX_APPLY_ATTEMPTS:
            push_warning("BRUSSELS_SHARED_RAIL_MATERIAL_SKIPPED: GeneratedRails not found")
            set_process(false)
        return
    _collect_targets(rails_root)
    if _targets.is_empty():
        if _attempts >= MAX_APPLY_ATTEMPTS:
            push_warning("BRUSSELS_SHARED_RAIL_MATERIAL_SKIPPED: no rail/sleeper boxes found")
            set_process(false)
        return
    set_material_enabled(true)
    _ready_applied = true
    print("BRUSSELS_SHARED_RAIL_MATERIAL_READY: targets=%d family=%s geometry_changed=false" % [_targets.size(), MATERIAL_FAMILY])

func _find_named_node(node: Node, wanted: String) -> Node:
    if node.name == wanted:
        return node
    for child: Node in node.get_children():
        var found := _find_named_node(child, wanted)
        if found != null:
            return found
    return null

func _collect_targets(root: Node) -> void:
    _targets.clear()
    _legacy_materials.clear()
    for child: Node in root.get_children():
        if child is CSGBox3D:
            var box := child as CSGBox3D
            if _is_rail(box) or _is_sleeper(box):
                _targets.append(box)
                _legacy_materials[box.get_instance_id()] = box.material

func _is_rail(box: CSGBox3D) -> bool:
    return box.name.begins_with("Rail_") and is_equal_approx(box.size.x, 0.095) and is_equal_approx(box.size.y, 0.09)

func _is_sleeper(box: CSGBox3D) -> bool:
    return is_equal_approx(box.size.x, 2.15) and is_equal_approx(box.size.y, 0.055) and is_equal_approx(box.size.z, 0.22)

func set_material_enabled(enabled: bool) -> void:
    for box: CSGBox3D in _targets:
        if not is_instance_valid(box):
            continue
        if enabled:
            box.material = _rail_material if _is_rail(box) else _sleeper_material
        else:
            var legacy: Variant = _legacy_materials.get(box.get_instance_id())
            if legacy is Material:
                box.material = legacy

func material_enabled() -> bool:
    if _targets.is_empty():
        return false
    for box: CSGBox3D in _targets:
        if is_instance_valid(box) and box.material != _rail_material and box.material != _sleeper_material:
            return false
    return true

func target_count() -> int:
    return _targets.size()

func ready_applied() -> bool:
    return _ready_applied
