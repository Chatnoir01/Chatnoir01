extends Node3D
class_name BrusselsOsmEnvironmentRuntime

## Generic visual-only renderer for zone-scoped OSM environment artifacts.
## Source points own presence + horizontal position. Shared asset families own
## presentation dimensions; none of those dimensions are source measurements.

const SOURCE_FORMAT := "grand-bruxelles-osm-zone-environment-v1"
const SUPPORTED_KINDS := ["tree", "street_lamp", "bollard"]
const TREE_FAR_FOLIAGE_LOBE_INDICES := [0, 3, 6]
const MAX_EXACT_JSON_INTEGER := 9007199254740991.0

@export_file("*.json") var data_path := ""
@export var render_radius_m := 350.0
@export var refresh_distance_m := 80.0
@export var tree_full_detail_radius_m := 140.0
@export var max_trees := 450
@export var max_street_lamps := 220
@export var max_bollards := 160

var last_render_counts := {"tree": 0, "street_lamp": 0, "bollard": 0}
var last_tree_lod_counts := {"near": 0, "far": 0, "foliage_instances": 0}
var _points := {"tree": [], "street_lamp": [], "bollard": []}
var _last_anchor := Vector3(INF, INF, INF)

func _ready() -> void:
    if not _validate_configuration():
        set_process(false)
        return
    if not _load_points():
        set_process(false)
        return
    call_deferred("_refresh", true)

func _process(_delta: float) -> void:
    _refresh(false)

func _validate_configuration() -> bool:
    if not is_finite(render_radius_m) or render_radius_m < 0.0:
        push_error("OSM environment render_radius_m must be finite and non-negative")
        return false
    if not is_finite(refresh_distance_m) or refresh_distance_m < 0.0:
        push_error("OSM environment refresh_distance_m must be finite and non-negative")
        return false
    if refresh_distance_m > render_radius_m:
        push_error("OSM environment refresh_distance_m must not exceed render_radius_m")
        return false
    if not is_finite(tree_full_detail_radius_m) or tree_full_detail_radius_m < 0.0:
        push_error("OSM environment tree_full_detail_radius_m must be finite and non-negative")
        return false
    if tree_full_detail_radius_m > render_radius_m:
        push_error("OSM environment tree_full_detail_radius_m must not exceed render_radius_m")
        return false
    if max_trees < 0 or max_street_lamps < 0 or max_bollards < 0:
        push_error("OSM environment instance limits must be non-negative")
        return false
    return true

func _load_points() -> bool:
    if data_path.is_empty() or not FileAccess.file_exists(data_path):
        push_error("OSM environment artifact missing: %s" % data_path)
        return false
    var file := FileAccess.open(data_path, FileAccess.READ)
    if file == null:
        push_error("OSM environment artifact unreadable: %s" % data_path)
        return false
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("OSM environment artifact invalid JSON object")
        return false
    var document := parsed as Dictionary
    if str(document.get("format", "")) != SOURCE_FORMAT:
        push_error("OSM environment artifact format mismatch")
        return false
    var validated_points: Variant = _collect_validated_points(document)
    if validated_points == null:
        return false
    _points = validated_points
    set_meta("source", str(document.get("source", "")))
    set_meta("license", str(document.get("license", "")))
    set_meta("source_dimensions_measured", false)
    return true

func _collect_validated_points(document: Dictionary) -> Variant:
    var rows_variant: Variant = document.get("environment_points", null)
    if not rows_variant is Array:
        push_error("OSM environment artifact environment_points must be an array")
        return null
    var validated := {"tree": [], "street_lamp": [], "bollard": []}
    var seen_osm_ids: Dictionary = {}
    for row_variant in rows_variant as Array:
        if not row_variant is Dictionary:
            push_error("OSM environment point must be an object")
            return null
        var row := row_variant as Dictionary
        var kind := str(row.get("kind", ""))
        if kind not in SUPPORTED_KINDS:
            push_error("Unsupported OSM environment kind: %s" % kind)
            return null
        var osm_id_value: Variant = row.get("osm_id", null)
        if typeof(osm_id_value) not in [TYPE_FLOAT, TYPE_INT]:
            push_error("OSM environment point osm_id must be numeric")
            return null
        var osm_id_number := float(osm_id_value)
        if not is_finite(osm_id_number) or osm_id_number <= 0.0 or osm_id_number > MAX_EXACT_JSON_INTEGER or floor(osm_id_number) != osm_id_number:
            push_error("OSM environment point osm_id must be a positive exact JSON integer")
            return null
        var osm_id := int(osm_id_number)
        if seen_osm_ids.has(osm_id):
            push_error("Duplicate OSM environment point osm_id: %d" % osm_id)
            return null
        seen_osm_ids[osm_id] = true
        var position: Variant = row.get("position", null)
        if not position is Array or position.size() != 2:
            push_error("OSM environment point missing exact X/Z position")
            return null
        var x_value: Variant = position[0]
        var z_value: Variant = position[1]
        if typeof(x_value) not in [TYPE_FLOAT, TYPE_INT] or typeof(z_value) not in [TYPE_FLOAT, TYPE_INT]:
            push_error("OSM environment point X/Z must be numeric")
            return null
        var x := float(x_value)
        var z := float(z_value)
        if not is_finite(x) or not is_finite(z):
            push_error("OSM environment point X/Z must be finite")
            return null
        (validated[kind] as Array).append({
            "osm_id": osm_id,
            "position": Vector3(x, 0.0, z),
        })
    return validated

func _target() -> Node3D:
    var tree := get_tree()
    var scene := tree.current_scene
    if scene != null:
        if scene.is_queued_for_deletion():
            return null
        var canonical_player := scene.get_node_or_null("Player") as Node3D
        if canonical_player != null and not canonical_player.is_queued_for_deletion():
            return canonical_player
        for node: Node in tree.get_nodes_in_group("player"):
            var candidate := node as Node3D
            if candidate != null and not candidate.is_queued_for_deletion() and scene.is_ancestor_of(candidate):
                return candidate
        return null
    var fallback := tree.get_first_node_in_group("player") as Node3D
    if fallback != null and fallback.is_queued_for_deletion():
        return null
    return fallback

func _set_batches_visible(enabled: bool) -> void:
    for child: Node in get_children():
        if child is MultiMeshInstance3D:
            (child as MultiMeshInstance3D).visible = enabled

func _refresh(force: bool) -> void:
    var target := _target()
    if target == null:
        _set_batches_visible(false)
        return
    var anchor := target.global_position
    if not is_finite(anchor.x) or not is_finite(anchor.y) or not is_finite(anchor.z):
        _set_batches_visible(false)
        return
    _set_batches_visible(true)
    if not force and _last_anchor != Vector3(INF, INF, INF):
        var horizontal_delta := Vector2(anchor.x - _last_anchor.x, anchor.z - _last_anchor.z)
        if horizontal_delta.length() < refresh_distance_m:
            return
    _last_anchor = anchor
    _rebuild(anchor)

func _nearby(kind: String, anchor: Vector3, limit: int) -> Array:
    var rows: Array = []
    var radius_sq := render_radius_m * render_radius_m
    for item_variant in _points[kind]:
        var item := item_variant as Dictionary
        var p: Vector3 = item["position"]
        var dx := p.x - anchor.x
        var dz := p.z - anchor.z
        var distance_sq := dx * dx + dz * dz
        if distance_sq <= radius_sq:
            rows.append({"osm_id": item["osm_id"], "position": p, "distance_sq": distance_sq})
    rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if float(a["distance_sq"]) == float(b["distance_sq"]):
            return int(a["osm_id"]) < int(b["osm_id"])
        return float(a["distance_sq"]) < float(b["distance_sq"])
    )
    if rows.size() > limit:
        rows.resize(limit)
    return rows

func _rebuild(anchor: Vector3) -> void:
    for child in get_children():
        remove_child(child)
        child.queue_free()
    var trees := _nearby("tree", anchor, max_trees)
    var lamps := _nearby("street_lamp", anchor, max_street_lamps)
    var bollards := _nearby("bollard", anchor, max_bollards)
    last_render_counts = {"tree": trees.size(), "street_lamp": lamps.size(), "bollard": bollards.size()}
    _build_tree_batches(trees)
    _build_lamp_batches(lamps)
    _build_bollard_batches(bollards)
    set_meta("render_counts", last_render_counts.duplicate(true))
    set_meta("tree_lod_counts", last_tree_lod_counts.duplicate(true))
    print("BRUSSELS_OSM_ENVIRONMENT_READY: %s radius=%.0fm tree_lod=%s" % [JSON.stringify(last_render_counts), render_radius_m, JSON.stringify(last_tree_lod_counts)])

func _batch(name_value: String, mesh: Mesh, transforms: Array) -> void:
    if transforms.is_empty():
        return
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()
    for index in range(transforms.size()):
        multimesh.set_instance_transform(index, transforms[index] as Transform3D)
    var instance := MultiMeshInstance3D.new()
    instance.name = name_value
    instance.multimesh = multimesh
    instance.set_meta("source_dimensions_measured", false)
    add_child(instance)

func _build_tree_batches(rows: Array) -> void:
    if rows.is_empty():
        last_tree_lod_counts = {"near": 0, "far": 0, "foliage_instances": 0}
        return
    var materials := BrusselsStreetTreeAsset.create_materials()
    var trunk: Array = []
    var dark: Array = []
    var light: Array = []
    var near_count := 0
    var far_count := 0
    var full_detail_radius_sq := tree_full_detail_radius_m * tree_full_detail_radius_m
    for row_variant in rows:
        var row := row_variant as Dictionary
        var base: Vector3 = row["position"]
        var osm_id := int(row["osm_id"])
        trunk.append(BrusselsStreetTreeAsset.trunk_transform(base))
        var lobe_indices: Array = []
        if float(row.get("distance_sq", 0.0)) <= full_detail_radius_sq:
            near_count += 1
            for index in range(BrusselsStreetTreeAsset.FOLIAGE_LOBE_COUNT):
                lobe_indices.append(index)
        else:
            far_count += 1
            lobe_indices.assign(TREE_FAR_FOLIAGE_LOBE_INDICES)
        for index_variant in lobe_indices:
            var index := int(index_variant)
            var transform := BrusselsStreetTreeAsset.foliage_lobe_transform(base, osm_id, index)
            (light if BrusselsStreetTreeAsset.foliage_is_light(index) else dark).append(transform)
    last_tree_lod_counts = {"near": near_count, "far": far_count, "foliage_instances": dark.size() + light.size()}
    _batch("TreeTrunks", BrusselsStreetTreeAsset.create_trunk_mesh(materials["trunk"]), trunk)
    _batch("TreeFoliageDark", BrusselsStreetTreeAsset.create_foliage_mesh(materials["foliage_dark"]), dark)
    _batch("TreeFoliageLight", BrusselsStreetTreeAsset.create_foliage_mesh(materials["foliage_light"]), light)

func _build_lamp_batches(rows: Array) -> void:
    if rows.is_empty():
        return
    var materials := BrusselsStreetLampAsset.create_materials()
    var poles: Array = []
    var arms: Array = []
    var luminaires: Array = []
    for row_variant in rows:
        var base: Vector3 = (row_variant as Dictionary)["position"]
        poles.append(BrusselsStreetLampAsset.pole_transform(base))
        arms.append(BrusselsStreetLampAsset.arm_transform(base))
        luminaires.append(BrusselsStreetLampAsset.luminaire_transform(base))
    _batch("LampPoles", BrusselsStreetLampAsset.create_pole_mesh(materials["metal"]), poles)
    _batch("LampArms", BrusselsStreetLampAsset.create_arm_mesh(materials["metal"]), arms)
    _batch("LampLuminaires", BrusselsStreetLampAsset.create_luminaire_mesh(materials["luminaire"]), luminaires)

func _build_bollard_batches(rows: Array) -> void:
    if rows.is_empty():
        return
    var materials := BrusselsBollardAsset.create_materials()
    var bodies: Array = []
    var caps: Array = []
    for row_variant in rows:
        var base: Vector3 = (row_variant as Dictionary)["position"]
        bodies.append(BrusselsBollardAsset.body_transform(base))
        caps.append(BrusselsBollardAsset.cap_transform(base))
    _batch("BollardBodies", BrusselsBollardAsset.create_body_mesh(materials["body"]), bodies)
    _batch("BollardCaps", BrusselsBollardAsset.create_cap_mesh(materials["cap"]), caps)
