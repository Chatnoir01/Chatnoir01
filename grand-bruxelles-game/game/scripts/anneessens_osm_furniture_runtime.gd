extends Node

const DATA_PATH := "res://data/osm/zones/anneessens/environment.game.json"
const EXPECTED_DATA_SHA256 := "df88c0af132d78f8c7252211546278b6bf26271958641434c08c0ce69d7cac5c"
const ANNEESSENS := Vector3(-272.04, 0.0, -217.07)
const TREE_ASSET := preload("res://game/scripts/brussels_street_tree_asset.gd")
const VISUAL_OWNER_META := "shared_environment_visual_owner"
const VISUAL_OWNER_ID := "anneessens_osm_furniture_runtime"
const MAX_EXACT_JSON_INTEGER := 9007199254740991.0
const COLLISION_POLICY := "disabled_until_source_backed_trunk_profile"
const EXPECTED_COVERAGE_POLICY := "preserve_existing_runtime_subset_v1"
const EXPECTED_COVERAGE_RADIUS_M := 130.0
const EXPECTED_ACTIVATION_RADIUS_M := 170.0
const EXPECTED_UPSTREAM_PATH := "data/osm/vertical_slice_01.game.json"
const UPSTREAM_PATH := "res://data/osm/vertical_slice_01.game.json"
const EXPECTED_UPSTREAM_FORMAT := "grand-bruxelles-osm-v1"
const EXPECTED_UPSTREAM_SHA256 := "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
const EXPECTED_UPSTREAM_LAT := 50.8419
const EXPECTED_UPSTREAM_LON := 4.348
const UPSTREAM_ORIGIN_EPSILON_DEGREES := 0.0000001
const SOURCE_POSITION_EPSILON_M := 0.0001
const EXPECTED_SOURCE_POSITIONS := {
    4672009403: Vector2(-186.799, -120.437),
    4672009414: Vector2(-165.05, -147.654),
    4672009415: Vector2(-169.929, -141.509),
    4672009416: Vector2(-175.018, -135.231),
    4672009417: Vector2(-179.918, -128.83),
    11929097332: Vector2(-313.793, -143.858),
    11929097333: Vector2(-306.074, -147.576),
}

@export var activation_radius_m: float = EXPECTED_ACTIVATION_RADIUS_M

var _scene: Node3D = null
var _player: Node3D = null
var _root: Node3D = null
var _tree_materials: Dictionary = {}
var _tree_meshes: Dictionary = {}
var _trees: Array[StaticBody3D] = []
var _enhanced_trees_enabled := true
var _manual_binding := false
var _watching_tree := false
var _tearing_down := false
var _tree_activation_initialized := false
var _tree_active := false
var _activation_radius_error_reported := false

func _ready() -> void:
    _tearing_down = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    _start_watching()
    call_deferred("_try_bind")

func _exit_tree() -> void:
    _tearing_down = true
    _stop_watching()
    _release_owned_root()
    _scene = null
    _player = null
    _manual_binding = false

func _validated_activation_radius_m() -> Variant:
    var valid := (
        is_finite(activation_radius_m)
        and activation_radius_m > 0.0
        and activation_radius_m == EXPECTED_ACTIVATION_RADIUS_M
    )
    if valid:
        _activation_radius_error_reported = false
        return EXPECTED_ACTIVATION_RADIUS_M
    if not _activation_radius_error_reported:
        push_error("Anneessens OSM furniture activation radius must remain exactly %.1fm" % EXPECTED_ACTIVATION_RADIUS_M)
        _activation_radius_error_reported = true
    return null

func _process(_delta: float) -> void:
    if _tearing_down or not is_inside_tree():
        return
    if not is_instance_valid(_scene):
        _reset()
        _start_watching()
        call_deferred("_try_bind")
        return
    if not is_instance_valid(_player):
        _player = _scene.get_node_or_null("Player") as Node3D
    if is_instance_valid(_player) and not _player.is_inside_tree():
        _player = _scene.get_node_or_null("Player") as Node3D
    if is_instance_valid(_root) and _root.get_parent() != _scene:
        _release_owned_root()
    if not is_instance_valid(_player) or not _player.is_inside_tree():
        _apply_tree_activation(false)
        return
    var activation_radius_value: Variant = _validated_activation_radius_m()
    if activation_radius_value == null:
        _apply_tree_activation(false)
        return
    if not is_instance_valid(_root):
        _build_once()
    if is_instance_valid(_root) and is_instance_valid(_player):
        var active := Vector2(_player.global_position.x - ANNEESSENS.x, _player.global_position.z - ANNEESSENS.z).length() <= float(activation_radius_value)
        _apply_tree_activation(active)

func _start_watching() -> void:
    if _tearing_down or not is_inside_tree() or _manual_binding or _watching_tree:
        return
    var tree: SceneTree = get_tree()
    if tree == null:
        return
    if not tree.node_added.is_connected(_on_tree_node_added):
        tree.node_added.connect(_on_tree_node_added)
    if not tree.node_removed.is_connected(_on_tree_node_removed):
        tree.node_removed.connect(_on_tree_node_removed)
    _watching_tree = true

func _stop_watching() -> void:
    var tree: SceneTree = get_tree()
    if tree != null:
        if tree.node_added.is_connected(_on_tree_node_added):
            tree.node_added.disconnect(_on_tree_node_added)
        if tree.node_removed.is_connected(_on_tree_node_removed):
            tree.node_removed.disconnect(_on_tree_node_removed)
    _watching_tree = false

func _release_owned_root() -> void:
    if is_instance_valid(_root):
        var parent := _root.get_parent()
        if parent != null and not _tearing_down:
            parent.remove_child(_root)
        _root.queue_free()
    _root = null
    _trees.clear()
    _tree_materials.clear()
    _tree_meshes.clear()
    _tree_activation_initialized = false
    _tree_active = false

func _on_tree_node_added(node: Node) -> void:
    if _tearing_down or not is_inside_tree() or _manual_binding or is_instance_valid(_scene):
        return
    var node_name := str(node.name)
    if node_name not in ["Main", "BrusselsOSM", "UrbISMidiExact", "Player"]:
        return
    call_deferred("_try_bind")

func _on_tree_node_removed(node: Node) -> void:
    if _tearing_down or not is_inside_tree() or _manual_binding or not is_instance_valid(_scene) or node != _scene:
        return
    _reset()
    _start_watching()
    call_deferred("_try_bind")

func _is_production_scene(candidate: Node3D) -> bool:
    return (
        candidate.get_node_or_null("BrusselsOSM") != null
        and candidate.get_node_or_null("UrbISMidiExact") != null
        and candidate.get_node_or_null("Player") is Node3D
    )

func _is_authoritative_production_scene(candidate: Node3D) -> bool:
    if candidate == null or not _is_production_scene(candidate) or not is_inside_tree():
        return false
    var tree: SceneTree = get_tree()
    if tree == null:
        return false
    if tree.current_scene == candidate:
        return true
    var parent := candidate.get_parent()
    if parent == tree.root:
        return true
    return (
        str(candidate.name) == "Main"
        and parent is Viewport
        and parent.get_parent() == tree.root
    )

func _find_nested_production_scene(node: Node) -> Node3D:
    if node is Node3D and _is_authoritative_production_scene(node as Node3D):
        return node as Node3D
    for child: Node in node.get_children():
        var nested := _find_nested_production_scene(child)
        if nested != null:
            return nested
    return null

func _find_production_scene() -> Node3D:
    if _tearing_down or not is_inside_tree():
        return null
    var tree: SceneTree = get_tree()
    if tree == null:
        return null
    var current := tree.current_scene
    if current is Node3D and _is_authoritative_production_scene(current as Node3D):
        return current as Node3D
    return _find_nested_production_scene(tree.root)

func _try_bind() -> void:
    if _tearing_down or not is_inside_tree() or _manual_binding or is_instance_valid(_scene):
        return
    var candidate := _find_production_scene()
    if candidate == null:
        return
    _bind_scene(candidate, false)

func bind_scene(scene: Node3D) -> void:
    if _tearing_down:
        return
    _bind_scene(scene, true)

func _bind_scene(scene: Node3D, manual: bool) -> void:
    if _tearing_down or scene == null:
        return
    if not manual and not is_inside_tree():
        return
    var player := scene.get_node_or_null("Player") as Node3D
    if player == null:
        return
    if is_instance_valid(_root) and _scene != scene:
        _release_owned_root()
    _manual_binding = manual
    _scene = scene
    _player = player
    if manual:
        _stop_watching()
    else:
        _start_watching()
    _build_once()

func _reset() -> void:
    _release_owned_root()
    _scene = null
    _player = null
    _manual_binding = false

func _skip_json_whitespace(text: String, index: int) -> int:
    var cursor := index
    while cursor < text.length() and text.substr(cursor, 1) in [" ", "\t", "\r", "\n"]:
        cursor += 1
    return cursor

func _scan_json_string_end(text: String, index: int) -> int:
    if index >= text.length() or text.substr(index, 1) != "\"":
        return -1
    var cursor := index + 1
    while cursor < text.length():
        var ch := text.substr(cursor, 1)
        if ch == "\"":
            return cursor + 1
        if ch == "\\":
            cursor += 1
            if cursor >= text.length():
                return -1
            if text.substr(cursor, 1) == "u":
                if cursor + 4 >= text.length():
                    return -1
                cursor += 5
                continue
        cursor += 1
    return -1

func _scan_json_value(text: String, index: int) -> int:
    var cursor := _skip_json_whitespace(text, index)
    if cursor >= text.length():
        return -1
    var ch := text.substr(cursor, 1)
    if ch == "\"":
        return _scan_json_string_end(text, cursor)
    if ch == "{":
        return _scan_json_object(text, cursor)
    if ch == "[":
        cursor = _skip_json_whitespace(text, cursor + 1)
        if cursor < text.length() and text.substr(cursor, 1) == "]":
            return cursor + 1
        while cursor < text.length():
            cursor = _scan_json_value(text, cursor)
            if cursor < 0:
                return -1
            cursor = _skip_json_whitespace(text, cursor)
            if cursor >= text.length():
                return -1
            ch = text.substr(cursor, 1)
            if ch == "]":
                return cursor + 1
            if ch != ",":
                return -1
            cursor = _skip_json_whitespace(text, cursor + 1)
        return -1
    while cursor < text.length():
        ch = text.substr(cursor, 1)
        if ch in [",", "]", "}", " ", "\t", "\r", "\n"]:
            break
        cursor += 1
    return cursor if cursor > index else -1

func _scan_json_object(text: String, index: int) -> int:
    if index >= text.length() or text.substr(index, 1) != "{":
        return -1
    var seen: Dictionary = {}
    var cursor := _skip_json_whitespace(text, index + 1)
    if cursor < text.length() and text.substr(cursor, 1) == "}":
        return cursor + 1
    while cursor < text.length():
        if text.substr(cursor, 1) != "\"":
            return -1
        var key_end := _scan_json_string_end(text, cursor)
        if key_end < 0:
            return -1
        var key_literal := text.substr(cursor, key_end - cursor)
        var decoded_key: Variant = JSON.parse_string(key_literal)
        if typeof(decoded_key) != TYPE_STRING:
            return -1
        var key := str(decoded_key)
        if seen.has(key):
            push_error("Anneessens OSM furniture JSON object contains duplicate key: %s" % key)
            return -1
        seen[key] = true
        cursor = _skip_json_whitespace(text, key_end)
        if cursor >= text.length() or text.substr(cursor, 1) != ":":
            return -1
        cursor = _scan_json_value(text, cursor + 1)
        if cursor < 0:
            return -1
        cursor = _skip_json_whitespace(text, cursor)
        if cursor >= text.length():
            return -1
        var separator := text.substr(cursor, 1)
        if separator == "}":
            return cursor + 1
        if separator != ",":
            return -1
        cursor = _skip_json_whitespace(text, cursor + 1)
    return -1

func _parse_strict_json_object(raw_text: String) -> Variant:
    var start := _skip_json_whitespace(raw_text, 0)
    if start >= raw_text.length() or raw_text.substr(start, 1) != "{":
        return null
    var end := _scan_json_object(raw_text, start)
    if end < 0 or _skip_json_whitespace(raw_text, end) != raw_text.length():
        return null
    var parsed: Variant = JSON.parse_string(raw_text)
    if not parsed is Dictionary:
        return null
    return parsed

func _validate_file_identity(path: String, expected_sha256: String, label: String) -> Variant:
    if not FileAccess.file_exists(path):
        push_error("Anneessens OSM furniture %s missing" % label)
        return null
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Anneessens OSM furniture %s unreadable" % label)
        return null
    var hashing := HashingContext.new()
    if hashing.start(HashingContext.HASH_SHA256) != OK:
        file.close()
        push_error("Anneessens OSM furniture %s SHA-256 initialization failed" % label)
        return null
    var file_length := file.get_length()
    while file.get_position() < file_length:
        var remaining := file_length - file.get_position()
        var chunk := file.get_buffer(min(65536, remaining))
        if chunk.is_empty() and remaining > 0:
            file.close()
            push_error("Anneessens OSM furniture %s read stalled" % label)
            return null
        if hashing.update(chunk) != OK:
            file.close()
            push_error("Anneessens OSM furniture %s SHA-256 update failed" % label)
            return null
    file.close()
    var digest := hashing.finish().hex_encode()
    if digest != expected_sha256:
        push_error("Anneessens OSM furniture %s digest drifted" % label)
        return null
    return {
        "identity_validated": true,
        "sha256": digest,
        "bytes": file_length,
    }

func _validate_data_artifact_identity(path: String = DATA_PATH) -> Variant:
    var identity_value: Variant = _validate_file_identity(path, EXPECTED_DATA_SHA256, "derived artifact")
    if identity_value == null:
        return null
    var identity := identity_value as Dictionary
    return {
        "data_artifact_identity_validated": bool(identity["identity_validated"]),
        "sha256": str(identity["sha256"]),
        "bytes": int(identity["bytes"]),
    }

func _validate_upstream_snapshot_identity(path: String = UPSTREAM_PATH) -> Variant:
    var identity_value: Variant = _validate_file_identity(path, EXPECTED_UPSTREAM_SHA256, "pinned upstream snapshot")
    if identity_value == null:
        return null
    var identity := identity_value as Dictionary
    return {
        "upstream_snapshot_identity_validated": bool(identity["identity_validated"]),
        "sha256": str(identity["sha256"]),
        "bytes": int(identity["bytes"]),
    }

func _collect_validated_tree_points(data: Dictionary) -> Variant:
    var environment_points: Variant = data.get("environment_points", null)
    if not environment_points is Array:
        push_error("Anneessens OSM furniture environment_points invalid")
        return null
    var validated: Array = []
    var seen_osm_ids: Dictionary = {}
    for raw: Variant in environment_points as Array:
        if not raw is Dictionary:
            push_error("Anneessens OSM furniture point invalid")
            return null
        var point := raw as Dictionary
        if str(point.get("kind", "")) != "tree":
            continue
        var osm_id_value: Variant = point.get("osm_id", null)
        if typeof(osm_id_value) != TYPE_INT:
            push_error("Anneessens OSM tree osm_id must be an integer source identity")
            return null
        var osm_id_number := float(osm_id_value)
        if not is_finite(osm_id_number) or osm_id_number <= 0.0 or osm_id_number > MAX_EXACT_JSON_INTEGER or floor(osm_id_number) != osm_id_number:
            push_error("Anneessens OSM tree osm_id must be a positive exact integer")
            return null
        var osm_id := int(osm_id_number)
        if seen_osm_ids.has(osm_id):
            push_error("Anneessens OSM tree osm_id duplicated")
            return null
        var position_value: Variant = point.get("position", null)
        if not position_value is Array or (position_value as Array).size() != 2:
            push_error("Anneessens OSM tree position must be exact [x,z]")
            return null
        var position := position_value as Array
        var x_value: Variant = position[0]
        var z_value: Variant = position[1]
        if typeof(x_value) not in [TYPE_FLOAT, TYPE_INT] or typeof(z_value) not in [TYPE_FLOAT, TYPE_INT]:
            push_error("Anneessens OSM tree coordinates must be numeric")
            return null
        var x := float(x_value)
        var z := float(z_value)
        if not is_finite(x) or not is_finite(z):
            push_error("Anneessens OSM tree coordinates must be finite")
            return null
        seen_osm_ids[osm_id] = true
        validated.append({"osm_id": osm_id, "position": Vector3(x, 0.0, z)})
    return validated

func _validate_selection_radius_membership(tree_points: Array) -> Variant:
    var max_distance_m := 0.0
    for tree_point: Variant in tree_points:
        if not tree_point is Dictionary:
            push_error("Anneessens OSM furniture radius membership point invalid")
            return null
        var point := tree_point as Dictionary
        var position_value: Variant = point.get("position", null)
        if not position_value is Vector3:
            push_error("Anneessens OSM furniture radius membership position invalid")
            return null
        var position := position_value as Vector3
        var distance_m := Vector2(position.x - ANNEESSENS.x, position.z - ANNEESSENS.z).length()
        if not is_finite(distance_m) or distance_m > EXPECTED_COVERAGE_RADIUS_M + 0.0001:
            push_error("Anneessens OSM furniture tree escaped declared 130m source subset")
            return null
        max_distance_m = max(max_distance_m, distance_m)
    return {
        "radius_membership_validated": true,
        "max_distance_m": max_distance_m,
    }

func _validate_source_position_identity(tree_points: Array) -> Variant:
    if tree_points.size() != EXPECTED_SOURCE_POSITIONS.size():
        push_error("Anneessens OSM furniture source-position point count drifted")
        return null
    var seen: Dictionary = {}
    var max_position_error_m := 0.0
    for tree_point: Variant in tree_points:
        if not tree_point is Dictionary:
            push_error("Anneessens OSM furniture source-position point invalid")
            return null
        var point := tree_point as Dictionary
        var osm_id_value: Variant = point.get("osm_id", null)
        var position_value: Variant = point.get("position", null)
        if typeof(osm_id_value) != TYPE_INT or not position_value is Vector3:
            push_error("Anneessens OSM furniture source-position identity shape invalid")
            return null
        var osm_id := int(osm_id_value)
        if seen.has(osm_id) or not EXPECTED_SOURCE_POSITIONS.has(osm_id):
            push_error("Anneessens OSM furniture source-position identity id invalid")
            return null
        var position := position_value as Vector3
        if not is_finite(position.x) or not is_finite(position.z):
            push_error("Anneessens OSM furniture source-position coordinate non-finite")
            return null
        var expected := EXPECTED_SOURCE_POSITIONS[osm_id] as Vector2
        var position_error_m := Vector2(position.x - expected.x, position.z - expected.y).length()
        if not is_finite(position_error_m) or position_error_m > SOURCE_POSITION_EPSILON_M:
            push_error("Anneessens OSM furniture selected OSM position drifted from pinned upstream")
            return null
        seen[osm_id] = true
        max_position_error_m = max(max_position_error_m, position_error_m)
    if seen.size() != EXPECTED_SOURCE_POSITIONS.size():
        push_error("Anneessens OSM furniture source-position identity incomplete")
        return null
    return {
        "source_position_identity_validated": true,
        "max_position_error_m": max_position_error_m,
        "source_position_epsilon_m": SOURCE_POSITION_EPSILON_M,
        "upstream_source_sha256": EXPECTED_UPSTREAM_SHA256,
    }

func _validate_selection_integrity(data: Dictionary, tree_points: Array) -> Variant:
    var selection_value: Variant = data.get("selection", null)
    if not selection_value is Dictionary:
        push_error("Anneessens OSM furniture selection contract missing")
        return null
    var selection := selection_value as Dictionary
    var anchor_value: Variant = selection.get("anchor", null)
    if not anchor_value is Array or (anchor_value as Array).size() != 2:
        push_error("Anneessens OSM furniture selection anchor invalid")
        return null
    var anchor := anchor_value as Array
    if typeof(anchor[0]) not in [TYPE_FLOAT, TYPE_INT] or typeof(anchor[1]) not in [TYPE_FLOAT, TYPE_INT]:
        push_error("Anneessens OSM furniture selection anchor must be numeric")
        return null
    var anchor_x := float(anchor[0])
    var anchor_z := float(anchor[1])
    if not is_finite(anchor_x) or not is_finite(anchor_z) or abs(anchor_x - ANNEESSENS.x) > 0.0001 or abs(anchor_z - ANNEESSENS.z) > 0.0001:
        push_error("Anneessens OSM furniture selection anchor drifted")
        return null

    var selected_value: Variant = selection.get("osm_ids", null)
    if not selected_value is Array:
        push_error("Anneessens OSM furniture selection osm_ids invalid")
        return null
    var selected_ids: Array[int] = []
    var selected_seen: Dictionary = {}
    for raw_id: Variant in selected_value as Array:
        if typeof(raw_id) != TYPE_INT:
            push_error("Anneessens OSM furniture selection osm_id must be an integer source identity")
            return null
        var selected_number := float(raw_id)
        if not is_finite(selected_number) or selected_number <= 0.0 or selected_number > MAX_EXACT_JSON_INTEGER or floor(selected_number) != selected_number:
            push_error("Anneessens OSM furniture selection osm_id must be a positive exact integer")
            return null
        var selected_id := int(selected_number)
        if selected_seen.has(selected_id):
            push_error("Anneessens OSM furniture selection osm_id duplicated")
            return null
        selected_seen[selected_id] = true
        selected_ids.append(selected_id)

    var point_ids: Array[int] = []
    for tree_point: Variant in tree_points:
        point_ids.append(int((tree_point as Dictionary)["osm_id"]))
    var selected_sorted := selected_ids.duplicate()
    var point_sorted := point_ids.duplicate()
    selected_sorted.sort()
    point_sorted.sort()
    if selected_sorted != point_sorted:
        push_error("Anneessens OSM furniture selection ids do not match mounted tree points")
        return null

    var stats_value: Variant = data.get("stats", null)
    if not stats_value is Dictionary:
        push_error("Anneessens OSM furniture stats contract missing")
        return null
    var stats := stats_value as Dictionary
    for key: String in ["tree", "total", "bollard", "street_lamp"]:
        var stat_value: Variant = stats.get(key, null)
        if typeof(stat_value) not in [TYPE_FLOAT, TYPE_INT]:
            push_error("Anneessens OSM furniture stats %s invalid" % key)
            return null
        var stat_number := float(stat_value)
        if not is_finite(stat_number) or stat_number < 0.0 or floor(stat_number) != stat_number:
            push_error("Anneessens OSM furniture stats %s must be a non-negative integer" % key)
            return null
    var environment_points := data.get("environment_points", []) as Array
    if int(stats.get("tree", -1)) != tree_points.size() or int(stats.get("total", -1)) != environment_points.size():
        push_error("Anneessens OSM furniture stats accounting drifted")
        return null
    if int(stats.get("bollard", -1)) != 0 or int(stats.get("street_lamp", -1)) != 0 or environment_points.size() != tree_points.size():
        push_error("Anneessens OSM furniture preserved subset contains unsupported non-tree points")
        return null
    return {
        "selection_osm_ids": selected_ids,
        "selection_anchor": ANNEESSENS,
    }

func _validate_coverage_contract(data: Dictionary) -> Variant:
    var selection_value: Variant = data.get("selection", null)
    if not selection_value is Dictionary:
        push_error("Anneessens OSM furniture selection contract missing")
        return null
    var selection := selection_value as Dictionary
    var coverage_complete_value: Variant = selection.get("coverage_complete", null)
    if typeof(coverage_complete_value) != TYPE_BOOL:
        push_error("Anneessens OSM furniture coverage_complete must be a boolean")
        return null
    if bool(coverage_complete_value):
        push_error("Anneessens OSM furniture partial subset must not claim complete coverage")
        return null
    if str(selection.get("policy", "")) != EXPECTED_COVERAGE_POLICY:
        push_error("Anneessens OSM furniture coverage policy invalid")
        return null
    var radius_value: Variant = selection.get("radius_m", null)
    if typeof(radius_value) not in [TYPE_FLOAT, TYPE_INT]:
        push_error("Anneessens OSM furniture coverage radius invalid")
        return null
    var coverage_radius_m := float(radius_value)
    if not is_finite(coverage_radius_m) or coverage_radius_m <= 0.0:
        push_error("Anneessens OSM furniture coverage radius must be finite and positive")
        return null
    if coverage_radius_m != EXPECTED_COVERAGE_RADIUS_M:
        push_error("Anneessens OSM furniture coverage radius drifted")
        return null
    var upstream_value: Variant = data.get("upstream", null)
    if not upstream_value is Dictionary:
        push_error("Anneessens OSM furniture upstream contract missing")
        return null
    var upstream := upstream_value as Dictionary
    if str(upstream.get("format", "")) != EXPECTED_UPSTREAM_FORMAT:
        push_error("Anneessens OSM furniture upstream format invalid")
        return null
    if str(upstream.get("path", "")) != EXPECTED_UPSTREAM_PATH:
        push_error("Anneessens OSM furniture upstream path invalid")
        return null
    if str(upstream.get("sha256", "")) != EXPECTED_UPSTREAM_SHA256:
        push_error("Anneessens OSM furniture upstream digest invalid")
        return null
    var origin_value: Variant = upstream.get("origin", null)
    if not origin_value is Dictionary:
        push_error("Anneessens OSM furniture upstream origin missing")
        return null
    var origin := origin_value as Dictionary
    var lat_value: Variant = origin.get("lat", null)
    var lon_value: Variant = origin.get("lon", null)
    if typeof(lat_value) not in [TYPE_FLOAT, TYPE_INT] or typeof(lon_value) not in [TYPE_FLOAT, TYPE_INT]:
        push_error("Anneessens OSM furniture upstream origin must be numeric")
        return null
    var upstream_lat := float(lat_value)
    var upstream_lon := float(lon_value)
    if not is_finite(upstream_lat) or not is_finite(upstream_lon):
        push_error("Anneessens OSM furniture upstream origin must be finite")
        return null
    if abs(upstream_lat - EXPECTED_UPSTREAM_LAT) > UPSTREAM_ORIGIN_EPSILON_DEGREES or abs(upstream_lon - EXPECTED_UPSTREAM_LON) > UPSTREAM_ORIGIN_EPSILON_DEGREES:
        push_error("Anneessens OSM furniture upstream origin drifted")
        return null
    return {
        "coverage_complete": false,
        "coverage_policy": EXPECTED_COVERAGE_POLICY,
        "coverage_radius_m": EXPECTED_COVERAGE_RADIUS_M,
        "upstream_source_sha256": EXPECTED_UPSTREAM_SHA256,
        "upstream_origin_validated": true,
        "upstream_origin_lat": EXPECTED_UPSTREAM_LAT,
        "upstream_origin_lon": EXPECTED_UPSTREAM_LON,
    }

func _build_once() -> void:
    if _tearing_down or not is_instance_valid(_scene) or is_instance_valid(_root):
        return
    var activation_radius_value: Variant = _validated_activation_radius_m()
    if activation_radius_value == null:
        return
    var data_artifact_identity_value: Variant = _validate_data_artifact_identity()
    if data_artifact_identity_value == null:
        return
    var data_artifact_identity := data_artifact_identity_value as Dictionary
    var upstream_snapshot_identity_value: Variant = _validate_upstream_snapshot_identity()
    if upstream_snapshot_identity_value == null:
        return
    var upstream_snapshot_identity := upstream_snapshot_identity_value as Dictionary
    var parsed: Variant = _parse_strict_json_object(FileAccess.get_file_as_string(DATA_PATH))
    if not parsed is Dictionary:
        push_error("Anneessens OSM furniture JSON invalid or ambiguous")
        return
    var data := parsed as Dictionary
    if str(data.get("format", "")) != "grand-bruxelles-osm-zone-environment-v1":
        push_error("Anneessens OSM furniture schema invalid")
        return
    if str(data.get("zone", "")) != "anneessens":
        push_error("Anneessens OSM furniture zone invalid")
        return
    if str(data.get("source", "")) != "OpenStreetMap contributors via Overpass API":
        push_error("Anneessens OSM furniture source invalid")
        return
    if str(data.get("license", "")) != "ODbL-1.0":
        push_error("Anneessens OSM furniture license missing")
        return
    if str(data.get("coordinate_space", "")) != "game_xz_m":
        push_error("Anneessens OSM furniture coordinate space invalid")
        return

    var coverage_contract_value: Variant = _validate_coverage_contract(data)
    if coverage_contract_value == null:
        return
    var coverage_contract := coverage_contract_value as Dictionary
    var validated_tree_points: Variant = _collect_validated_tree_points(data)
    if validated_tree_points == null:
        return
    var tree_points := validated_tree_points as Array
    var radius_membership_value: Variant = _validate_selection_radius_membership(tree_points)
    if radius_membership_value == null:
        return
    var radius_membership := radius_membership_value as Dictionary
    var selection_integrity_value: Variant = _validate_selection_integrity(data, tree_points)
    if selection_integrity_value == null:
        return
    var selection_integrity := selection_integrity_value as Dictionary
    var source_position_identity_value: Variant = _validate_source_position_identity(tree_points)
    if source_position_identity_value == null:
        return
    var source_position_identity := source_position_identity_value as Dictionary

    _root = Node3D.new()
    _root.name = "AnneessensOsmFurniture"
    _root.set_meta("source", str(data.get("source", "")))
    _root.set_meta("license", str(data.get("license", "")))
    _root.set_meta("placement_source_backed", true)
    _root.set_meta("visual_dimensions_source_backed", false)
    _root.set_meta("source_height_measured", false)
    _root.set_meta("source_species_measured", false)
    _root.set_meta("collision_source_backed", false)
    _root.set_meta("collision_authorized", false)
    _root.set_meta("collision_policy", COLLISION_POLICY)
    _root.set_meta("coverage_complete", false)
    _root.set_meta("full_environment_coverage_claimed", false)
    _root.set_meta("coverage_policy", str(coverage_contract["coverage_policy"]))
    _root.set_meta("coverage_radius_m", float(coverage_contract["coverage_radius_m"]))
    _root.set_meta("activation_radius_validated", true)
    _root.set_meta("activation_radius_m", float(activation_radius_value))
    _root.set_meta("data_artifact_identity_validated", true)
    _root.set_meta("data_artifact_sha256", str(data_artifact_identity["sha256"]))
    _root.set_meta("data_artifact_bytes", int(data_artifact_identity["bytes"]))
    _root.set_meta("upstream_snapshot_identity_validated", true)
    _root.set_meta("upstream_source_sha256", str(upstream_snapshot_identity["sha256"]))
    _root.set_meta("upstream_source_bytes", int(upstream_snapshot_identity["bytes"]))
    _root.set_meta("upstream_origin_validated", bool(coverage_contract["upstream_origin_validated"]))
    _root.set_meta("upstream_origin_lat", float(coverage_contract["upstream_origin_lat"]))
    _root.set_meta("upstream_origin_lon", float(coverage_contract["upstream_origin_lon"]))
    _root.set_meta("radius_membership_validated", bool(radius_membership["radius_membership_validated"]))
    _root.set_meta("selection_max_distance_m", float(radius_membership["max_distance_m"]))
    _root.set_meta("selection_identity_validated", true)
    _root.set_meta("selection_tree_count", tree_points.size())
    _root.set_meta("selection_osm_ids", selection_integrity["selection_osm_ids"])
    _root.set_meta("source_position_identity_validated", bool(source_position_identity["source_position_identity_validated"]))
    _root.set_meta("source_position_max_error_m", float(source_position_identity["max_position_error_m"]))
    _root.set_meta("source_position_epsilon_m", float(source_position_identity["source_position_epsilon_m"]))
    _scene.add_child(_root)
    _tree_materials = TREE_ASSET.create_materials()
    _tree_meshes = TREE_ASSET.create_meshes(_tree_materials)
    var legacy_trunk := CylinderMesh.new()
    legacy_trunk.top_radius = 0.16
    legacy_trunk.bottom_radius = 0.21
    legacy_trunk.height = 2.6
    _tree_meshes["legacy_trunk"] = legacy_trunk
    var legacy_crown := SphereMesh.new()
    legacy_crown.radius = 1.45
    legacy_crown.height = 2.9
    _tree_meshes["legacy_crown"] = legacy_crown

    for tree_point: Variant in tree_points:
        var validated_point := tree_point as Dictionary
        var world_position: Vector3 = validated_point["position"]
        _add_tree(int(validated_point["osm_id"]), world_position)

    _tree_activation_initialized = false
    var active := Vector2(_player.global_position.x - ANNEESSENS.x, _player.global_position.z - ANNEESSENS.z).length() <= float(activation_radius_value)
    _apply_tree_activation(active)
    print("ANNEESSENS_OSM_FURNITURE_READY: trees=%d selection_identity_validated=true radius_membership_validated=true selection_max_distance_m=%.3f source_position_identity_validated=true source_position_max_error_m=%.6f upstream_origin_validated=true data_artifact_identity_validated=true upstream_snapshot_identity_validated=true strict_json=true coverage_complete=false coverage_policy=%s coverage_radius_m=%.1f activation_radius_m=%.1f activation_radius_validated=true asset_family=%s source=OSM license=ODbL-1.0 collision_policy=%s" % [tree_points.size(), float(radius_membership["max_distance_m"]), float(source_position_identity["max_position_error_m"]), str(coverage_contract["coverage_policy"]), float(coverage_contract["coverage_radius_m"]), float(activation_radius_value), TREE_ASSET.ASSET_FAMILY, COLLISION_POLICY])

func _apply_tree_activation(active: bool) -> void:
    if not is_instance_valid(_root):
        _tree_active = active
        _tree_activation_initialized = false
        return
    if _tree_activation_initialized and _tree_active == active:
        return
    _tree_active = active
    _tree_activation_initialized = true
    _root.visible = active

func _add_tree(osm_id: int, world_position: Vector3) -> void:
    var tree := StaticBody3D.new()
    tree.name = "OsmTree_%d" % osm_id
    tree.position = world_position
    tree.add_to_group("osm_environment_furniture")
    tree.set_meta("osm_id", osm_id)
    tree.set_meta("source", "OpenStreetMap contributors via Overpass API")
    tree.set_meta("license", "ODbL-1.0")
    tree.set_meta("placement_source_backed", true)
    tree.set_meta("visual_dimensions_source_backed", false)
    tree.set_meta("collision_source_backed", false)
    tree.set_meta("collision_authorized", false)
    tree.set_meta("collision_policy", COLLISION_POLICY)
    _root.add_child(tree)
    _trees.append(tree)

    _rebuild_tree_visual(tree)

func _is_owned_tree_visual(node: Node) -> bool:
    return str(node.get_meta(VISUAL_OWNER_META, "")) == VISUAL_OWNER_ID

func _mark_owned_tree_visual(node: Node) -> void:
    if node != null:
        node.set_meta(VISUAL_OWNER_META, VISUAL_OWNER_ID)

func _remove_owned_tree_visuals(tree: StaticBody3D) -> void:
    for child: Node in tree.get_children():
        if not _is_owned_tree_visual(child):
            continue
        tree.remove_child(child)
        child.queue_free()

func _rebuild_tree_visual(tree: StaticBody3D) -> void:
    _remove_owned_tree_visuals(tree)
    var osm_id := int(tree.get_meta("osm_id", 0))
    if _enhanced_trees_enabled:
        var enhanced_visual := TREE_ASSET.populate(tree, osm_id, _tree_materials, _tree_meshes)
        _mark_owned_tree_visual(enhanced_visual)
        return
    tree.set_meta("asset_family", "legacy_primitive_tree")
    tree.set_meta("source_dimensions_measured", false)
    tree.set_meta("species_claimed", false)
    var legacy := Node3D.new()
    legacy.name = "LegacyTreeVisual"
    _mark_owned_tree_visual(legacy)
    tree.add_child(legacy)
    var trunk_mesh := MeshInstance3D.new()
    trunk_mesh.name = "Trunk"
    trunk_mesh.mesh = _tree_meshes["legacy_trunk"] as Mesh
    trunk_mesh.material_override = _tree_materials["trunk"] as Material
    trunk_mesh.position.y = 1.3
    legacy.add_child(trunk_mesh)
    var crown := MeshInstance3D.new()
    crown.name = "Crown"
    crown.mesh = _tree_meshes["legacy_crown"] as Mesh
    crown.material_override = _tree_materials["foliage_dark"] as Material
    crown.position.y = 3.15
    legacy.add_child(crown)

func set_enhanced_trees_enabled(enabled: bool) -> void:
    if _enhanced_trees_enabled == enabled:
        return
    _enhanced_trees_enabled = enabled
    for tree: StaticBody3D in _trees:
        if is_instance_valid(tree):
            _rebuild_tree_visual(tree)

func enhanced_trees_enabled() -> bool:
    return _enhanced_trees_enabled

func tree_count() -> int:
    return _trees.size()