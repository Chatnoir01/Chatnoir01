extends Node3D
class_name BrusselsOsmEnvironmentRuntime

## Generic visual-only renderer for zone-scoped OSM environment artifacts.
## Source points own presence + horizontal position. Shared asset families own
## presentation dimensions; none of those dimensions are source measurements.

const SOURCE_FORMAT := "grand-bruxelles-osm-zone-environment-v1"
const SUPPORTED_KINDS := ["tree", "street_lamp", "bollard"]

@export_file("*.json") var data_path := ""
@export var render_radius_m := 350.0
@export var refresh_distance_m := 80.0
@export var max_trees := 450
@export var max_street_lamps := 220
@export var max_bollards := 160

var last_render_counts := {"tree": 0, "street_lamp": 0, "bollard": 0}
var _points := {"tree": [], "street_lamp": [], "bollard": []}
var _last_anchor := Vector3(INF, INF, INF)

func _ready() -> void:
    if not _load_points():
        set_process(false)
        return
    call_deferred("_refresh", true)

func _process(_delta: float) -> void:
    _refresh(false)

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
    for row_variant in document.get("environment_points", []):
        if not row_variant is Dictionary:
            continue
        var row := row_variant as Dictionary
        var kind := str(row.get("kind", ""))
        if kind not in SUPPORTED_KINDS:
            push_error("Unsupported OSM environment kind: %s" % kind)
            return false
        var position = row.get("position", [])
        if not position is Array or position.size() < 2:
            push_error("OSM environment point missing X/Z position")
            return false
        (_points[kind] as Array).append({
            "osm_id": int(row.get("osm_id", 0)),
            "position": Vector3(float(position[0]), 0.0, float(position[1])),
        })
    set_meta("source", str(document.get("source", "")))
    set_meta("license", str(document.get("license", "")))
    set_meta("source_dimensions_measured", false)
    return true

func _target() -> Node3D:
    var player := get_tree().get_first_node_in_group("player") as Node3D
    if player != null:
        return player
    var scene := get_tree().current_scene
    return scene.get_node_or_null("Player") as Node3D if scene != null else null

func _refresh(force: bool) -> void:
    var target := _target()
    if target == null:
        return
    var anchor := target.global_position
    if not force and _last_anchor != Vector3(INF, INF, INF) and anchor.distance_to(_last_anchor) < refresh_distance_m:
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
        child.queue_free()
    var trees := _nearby("tree", anchor, max_trees)
    var lamps := _nearby("street_lamp", anchor, max_street_lamps)
    var bollards := _nearby("bollard", anchor, max_bollards)
    last_render_counts = {"tree": trees.size(), "street_lamp": lamps.size(), "bollard": bollards.size()}
    _build_tree_batches(trees)
    _build_lamp_batches(lamps)
    _build_bollard_batches(bollards)
    set_meta("render_counts", last_render_counts.duplicate(true))
    print("BRUSSELS_OSM_ENVIRONMENT_READY: %s radius=%.0fm" % [JSON.stringify(last_render_counts), render_radius_m])

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
        return
    var materials := BrusselsStreetTreeAsset.create_materials()
    var trunk: Array = []
    var dark: Array = []
    var light: Array = []
    for row_variant in rows:
        var row := row_variant as Dictionary
        var base: Vector3 = row["position"]
        var osm_id := int(row["osm_id"])
        trunk.append(BrusselsStreetTreeAsset.trunk_transform(base))
        for index in range(BrusselsStreetTreeAsset.FOLIAGE_LOBE_COUNT):
            var transform := BrusselsStreetTreeAsset.foliage_lobe_transform(base, osm_id, index)
            (light if BrusselsStreetTreeAsset.foliage_is_light(index) else dark).append(transform)
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
