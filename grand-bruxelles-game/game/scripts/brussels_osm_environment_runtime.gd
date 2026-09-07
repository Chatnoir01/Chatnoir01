extends Node3D
class_name BrusselsOsmEnvironmentRuntime

## Generic visual-only renderer for zone-scoped OSM environment artifacts.
## Source points own presence + horizontal position. Shared asset families own
## presentation dimensions; none of those dimensions are source measurements.

const SOURCE_FORMAT := "grand-bruxelles-osm-zone-environment-v1"
const REQUIRED_SOURCE := "OpenStreetMap contributors via Overpass API"
const REQUIRED_LICENSE := "ODbL-1.0"
const SUPPORTED_KINDS := ["tree", "street_lamp", "bollard"]
const TREE_FAR_FOLIAGE_LOBE_INDICES := [0, 3, 6]
const MAX_EXACT_JSON_INTEGER := 9007199254740991.0
# Canonical environment bounds are serialized at 0.01 m while point positions
# retain 0.001 m precision. Half a bound quantization step is therefore the
# maximum source-preserving edge discrepancy; the epsilon is numeric only.
const BOUNDS_HALF_QUANTIZATION_M := 0.005
const BOUNDS_NUMERIC_EPSILON_M := 0.0000001

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
var _last_tree_lod_anchor := Vector3(INF, INF, INF)
var _rendered_trees: Array = []
var _owned_batches: Array[MultiMeshInstance3D] = []
var _batches_visible := true
var _tree_lod_boundary_margin_m := 0.0
var _tree_lod_boundary_margin_radius_m := INF
# Runtime-local cache: these meshes/materials are authored presentation resources,
# independent of source point selection. Keep them stable across transform refreshes.
var _presentation_meshes: Dictionary = {}

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

func _reset_loaded_source_state() -> void:
    _clear_owned_batches()
    _points = {"tree": [], "street_lamp": [], "bollard": []}
    _last_anchor = Vector3(INF, INF, INF)
    _last_tree_lod_anchor = Vector3(INF, INF, INF)
    _tree_lod_boundary_margin_m = 0.0
    _tree_lod_boundary_margin_radius_m = INF
    _rendered_trees.clear()
    last_render_counts = {"tree": 0, "street_lamp": 0, "bollard": 0}
    last_tree_lod_counts = {"near": 0, "far": 0, "foliage_instances": 0}
    for key: StringName in [&"source", &"license", &"source_dimensions_measured", &"render_counts", &"tree_lod_counts"]:
        if has_meta(key):
            remove_meta(key)

func _load_points() -> bool:
    # A replacement source is authoritative as soon as loading is attempted.
    # If validation fails, retaining any previously trusted points/provenance or
    # materialized batches would present stale data under the rejected data_path.
    _reset_loaded_source_state()
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
    var source := str(document.get("source", ""))
    if source != REQUIRED_SOURCE:
        push_error("OSM environment artifact source mismatch")
        return false
    var license := str(document.get("license", ""))
    if license != REQUIRED_LICENSE:
        push_error("OSM environment artifact license mismatch")
        return false
    var bounds_variant: Variant = _validated_bounds_m(document)
    if bounds_variant == null:
        return false
    var validated_points: Variant = _collect_validated_points(document, bounds_variant as Dictionary)
    if validated_points == null:
        return false
    _points = validated_points
    set_meta("source", source)
    set_meta("license", license)
    set_meta("source_dimensions_measured", false)
    return true

func _validated_bounds_m(document: Dictionary) -> Variant:
    var bounds_variant: Variant = document.get("bounds_m", null)
    if not bounds_variant is Array or bounds_variant.size() != 4:
        push_error("OSM environment artifact bounds_m must be an exact four-value array")
        return null
    var bounds := bounds_variant as Array
    var numbers: Array[float] = []
    for value: Variant in bounds:
        if typeof(value) not in [TYPE_FLOAT, TYPE_INT]:
            push_error("OSM environment artifact bounds_m values must be numeric")
            return null
        var number := float(value)
        if not is_finite(number):
            push_error("OSM environment artifact bounds_m values must be finite")
            return null
        numbers.append(number)
    if numbers[0] > numbers[2] or numbers[1] > numbers[3]:
        push_error("OSM environment artifact bounds_m min/max order is invalid")
        return null
    return {
        "min_x": numbers[0],
        "min_z": numbers[1],
        "max_x": numbers[2],
        "max_z": numbers[3],
    }

func _collect_validated_points(document: Dictionary, bounds: Dictionary) -> Variant:
    var rows_variant: Variant = document.get("environment_points", null)
    if not rows_variant is Array:
        push_error("OSM environment artifact environment_points must be an array")
        return null
    var validated := {"tree": [], "street_lamp": [], "bollard": []}
    var seen_osm_ids: Dictionary = {}
    var bounds_tolerance := BOUNDS_HALF_QUANTIZATION_M + BOUNDS_NUMERIC_EPSILON_M
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
        if x < float(bounds["min_x"]) - bounds_tolerance or x > float(bounds["max_x"]) + bounds_tolerance or z < float(bounds["min_z"]) - bounds_tolerance or z > float(bounds["max_z"]) + bounds_tolerance:
            push_error("OSM environment point lies outside declared bounds_m beyond source quantization")
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
        # Zone-scoped renderers must be owned by the authoritative current scene.
        # During scene replacement an old scene can remain alive until deferred
        # teardown; never let that stale renderer borrow the new scene's Player.
        if self != scene and not scene.is_ancestor_of(self):
            return null
        var canonical_player := scene.get_node_or_null("Player") as Node3D
        if canonical_player != null and not canonical_player.is_queued_for_deletion():
            return canonical_player
        for node: Node in tree.get_nodes_in_group("player"):
            var candidate := node as Node3D
            if candidate != null and not candidate.is_queued_for_deletion() and scene.is_ancestor_of(candidate):
                return candidate
        return null
    # Headless/dev witnesses legitimately run without current_scene. Scope that
    # fallback to the runtime's own top-level world so a stale nested renderer
    # cannot borrow a Player from a sibling replacement world during transitions.
    var direct_root_runtime := get_parent() == tree.root
    var scope: Node = self
    if not direct_root_runtime:
        while scope.get_parent() != null and scope.get_parent() != tree.root:
            scope = scope.get_parent()
    var scoped_player := scope.get_node_or_null("Player") as Node3D
    if scoped_player != null and not scoped_player.is_queued_for_deletion():
        return scoped_player
    for node: Node in tree.get_nodes_in_group("player"):
        var fallback := node as Node3D
        if fallback == null or fallback.is_queued_for_deletion():
            continue
        if scope.is_ancestor_of(fallback):
            return fallback
        # Preserve the explicit root-sibling harness contract only for a runtime
        # that is itself directly rooted. Nested worlds remain strictly scoped.
        if direct_root_runtime and fallback.get_parent() == tree.root:
            return fallback
    return null

func _prune_invalid_owned_batches() -> void:
    for index in range(_owned_batches.size() - 1, -1, -1):
        var batch := _owned_batches[index]
        if not is_instance_valid(batch) or batch.is_queued_for_deletion() or batch.get_parent() != self:
            _owned_batches.remove_at(index)

func _set_batches_visible(enabled: bool) -> void:
    _prune_invalid_owned_batches()
    if _batches_visible == enabled:
        return
    _batches_visible = enabled
    for batch: MultiMeshInstance3D in _owned_batches:
        batch.visible = enabled

func _tree_lod_boundary_crossed(anchor: Vector3) -> bool:
    if _rendered_trees.is_empty() or _last_tree_lod_anchor == Vector3(INF, INF, INF):
        return false
    if _tree_lod_boundary_margin_radius_m != tree_full_detail_radius_m:
        return true
    var anchor_dx := anchor.x - _last_tree_lod_anchor.x
    var anchor_dz := anchor.z - _last_tree_lod_anchor.z
    var anchor_distance_sq := anchor_dx * anchor_dx + anchor_dz * anchor_dz
    if anchor_distance_sq < _tree_lod_boundary_margin_m * _tree_lod_boundary_margin_m:
        return false
    var detail_radius_sq := tree_full_detail_radius_m * tree_full_detail_radius_m
    var minimum_boundary_margin := INF
    for row_variant in _rendered_trees:
        var row := row_variant as Dictionary
        var p: Vector3 = row["position"]
        var old_dx := p.x - _last_tree_lod_anchor.x
        var old_dz := p.z - _last_tree_lod_anchor.z
        var new_dx := p.x - anchor.x
        var new_dz := p.z - anchor.z
        var new_distance_sq := new_dx * new_dx + new_dz * new_dz
        var was_near := old_dx * old_dx + old_dz * old_dz <= detail_radius_sq
        var is_near := new_distance_sq <= detail_radius_sq
        if was_near != is_near:
            return true
        var radial_distance := sqrt(new_distance_sq)
        minimum_boundary_margin = min(minimum_boundary_margin, abs(radial_distance - tree_full_detail_radius_m))
    _tree_lod_boundary_margin_m = max(0.0, minimum_boundary_margin - BOUNDS_NUMERIC_EPSILON_M)
    _tree_lod_boundary_margin_radius_m = tree_full_detail_radius_m
    _last_tree_lod_anchor = anchor
    return false

func _clear_tree_foliage_batches() -> void:
    for index in range(_owned_batches.size() - 1, -1, -1):
        var batch := _owned_batches[index]
        if not is_instance_valid(batch):
            _owned_batches.remove_at(index)
            continue
        if not batch.name.begins_with("TreeFoliage"):
            continue
        if batch.get_parent() != self:
            _owned_batches.remove_at(index)
            continue
        remove_child(batch)
        if not batch.is_queued_for_deletion():
            batch.queue_free()
        _owned_batches.remove_at(index)

func _refresh_tree_lod(anchor: Vector3) -> void:
    _build_tree_foliage_batches(_rendered_trees, anchor, true)
    _last_tree_lod_anchor = anchor
    set_meta("tree_lod_counts", last_tree_lod_counts.duplicate(true))

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
        var horizontal_dx := anchor.x - _last_anchor.x
        var horizontal_dz := anchor.z - _last_anchor.z
        var horizontal_distance_sq := horizontal_dx * horizontal_dx + horizontal_dz * horizontal_dz
        if horizontal_distance_sq == 0.0 and _tree_lod_boundary_margin_radius_m == tree_full_detail_radius_m:
            return
        if horizontal_distance_sq < refresh_distance_m * refresh_distance_m:
            if _tree_lod_boundary_crossed(anchor):
                _refresh_tree_lod(anchor)
            return
    _last_anchor = anchor
    _rebuild(anchor)

func _select_rows(kind: String, anchor: Vector3, limit: int) -> Array:
    var selected: Array = []
    var radius_sq := render_radius_m * render_radius_m
    for row_variant in _points[kind]:
        var row := row_variant as Dictionary
        var p: Vector3 = row["position"]
        var dx := p.x - anchor.x
        var dz := p.z - anchor.z
        var distance_sq := dx * dx + dz * dz
        if distance_sq > radius_sq:
            continue
        selected.append({
            "osm_id": row["osm_id"],
            "position": p,
            "distance_sq": distance_sq,
        })
    selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if a["distance_sq"] == b["distance_sq"]:
            return int(a["osm_id"]) < int(b["osm_id"])
        return a["distance_sq"] < b["distance_sq"]
    )
    if selected.size() > limit:
        selected.resize(limit)
    return selected

func _batch(name: String, mesh: Mesh, transforms: Array[Transform3D], reuse_existing := false) -> MultiMeshInstance3D:
    _prune_invalid_owned_batches()
    var instance: MultiMeshInstance3D = null
    if reuse_existing:
        for candidate: MultiMeshInstance3D in _owned_batches:
            if candidate.name == name:
                instance = candidate
                break
    var multimesh: MultiMesh = null
    if instance == null:
        instance = MultiMeshInstance3D.new()
        instance.name = name
        multimesh = MultiMesh.new()
        multimesh.transform_format = MultiMesh.TRANSFORM_3D
        instance.multimesh = multimesh
        add_child(instance)
        _owned_batches.append(instance)
    else:
        multimesh = instance.multimesh
        if multimesh == null:
            multimesh = MultiMesh.new()
            multimesh.transform_format = MultiMesh.TRANSFORM_3D
            instance.multimesh = multimesh
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()
    for index in transforms.size():
        multimesh.set_instance_transform(index, transforms[index])
    instance.visible = _batches_visible
    return instance

func _ensure_tree_presentation_meshes() -> void:
    if _presentation_meshes.has("tree_trunk"):
        return
    var trunk_mesh := CylinderMesh.new()
    trunk_mesh.top_radius = 0.14
    trunk_mesh.bottom_radius = 0.19
    trunk_mesh.height = 3.4
    trunk_mesh.radial_segments = 6
    trunk_mesh.rings = 1
    var trunk_material := StandardMaterial3D.new()
    trunk_material.albedo_color = Color("66513c")
    trunk_material.roughness = 1.0
    trunk_mesh.material = trunk_material
    _presentation_meshes["tree_trunk"] = trunk_mesh

    var crown_mesh := SphereMesh.new()
    crown_mesh.radius = 1.45
    crown_mesh.height = 2.2
    crown_mesh.radial_segments = 8
    crown_mesh.rings = 4
    var crown_material := StandardMaterial3D.new()
    crown_material.albedo_color = Color("587650")
    crown_material.roughness = 0.95
    crown_mesh.material = crown_material
    _presentation_meshes["tree_crown"] = crown_mesh

    var far_lobe_mesh := SphereMesh.new()
    far_lobe_mesh.radius = 1.22
    far_lobe_mesh.height = 2.0
    far_lobe_mesh.radial_segments = 6
    far_lobe_mesh.rings = 3
    var far_lobe_material := StandardMaterial3D.new()
    far_lobe_material.albedo_color = Color("587650")
    far_lobe_material.roughness = 0.95
    far_lobe_mesh.material = far_lobe_material
    _presentation_meshes["tree_far_lobe"] = far_lobe_mesh

func _ensure_street_lamp_presentation_meshes() -> void:
    if _presentation_meshes.has("street_lamp_pole"):
        return
    var pole_mesh := CylinderMesh.new()
    pole_mesh.top_radius = 0.07
    pole_mesh.bottom_radius = 0.1
    pole_mesh.height = 4.4
    pole_mesh.radial_segments = 6
    pole_mesh.rings = 1
    var pole_material := StandardMaterial3D.new()
    pole_material.albedo_color = Color("20252a")
    pole_material.metallic = 0.4
    pole_material.roughness = 0.55
    pole_mesh.material = pole_material
    _presentation_meshes["street_lamp_pole"] = pole_mesh

    var head_mesh := BoxMesh.new()
    head_mesh.size = Vector3(0.36, 0.18, 0.36)
    var head_material := StandardMaterial3D.new()
    head_material.albedo_color = Color("d8d0a9")
    head_material.emission_enabled = true
    head_material.emission = Color("7a704b")
    head_material.emission_energy_multiplier = 0.55
    head_mesh.material = head_material
    _presentation_meshes["street_lamp_head"] = head_mesh

func _ensure_bollard_presentation_meshes() -> void:
    if _presentation_meshes.has("bollard_body"):
        return
    var body_mesh := CylinderMesh.new()
    body_mesh.top_radius = 0.12
    body_mesh.bottom_radius = 0.14
    body_mesh.height = 0.88
    body_mesh.radial_segments = 6
    body_mesh.rings = 1
    var body_material := StandardMaterial3D.new()
    body_material.albedo_color = Color("2a2d31")
    body_material.metallic = 0.25
    body_material.roughness = 0.65
    body_mesh.material = body_material
    _presentation_meshes["bollard_body"] = body_mesh

func _tree_transforms(rows: Array, anchor: Vector3) -> Dictionary:
    var trunk_transforms: Array[Transform3D] = []
    var near_crown_transforms: Array[Transform3D] = []
    var far_tree_positions: Array[Vector3] = []
    var detail_radius_sq := tree_full_detail_radius_m * tree_full_detail_radius_m
    for row_variant in rows:
        var row := row_variant as Dictionary
        var p: Vector3 = row["position"]
        var dx := p.x - anchor.x
        var dz := p.z - anchor.z
        trunk_transforms.append(Transform3D(Basis.IDENTITY, p + Vector3(0.0, 1.7, 0.0)))
        if dx * dx + dz * dz <= detail_radius_sq:
            near_crown_transforms.append(Transform3D(Basis.IDENTITY, p + Vector3(0.0, 4.25, 0.0)))
        else:
            far_tree_positions.append(p)
    return {
        "trunks": trunk_transforms,
        "near_crowns": near_crown_transforms,
        "far_positions": far_tree_positions,
    }

func _far_tree_lobe_offsets() -> Array[Vector3]:
    return [
        Vector3(0.0, 4.15, 0.0),
        Vector3(0.48, 4.25, 0.0),
        Vector3(-0.48, 4.25, 0.0),
        Vector3(0.0, 4.3, 0.48),
        Vector3(0.0, 4.3, -0.48),
        Vector3(0.34, 4.3, 0.34),
        Vector3(-0.34, 4.3, -0.34),
    ]

func _build_tree_foliage_batches(rows: Array, anchor: Vector3, replace_existing := false) -> void:
    _ensure_tree_presentation_meshes()
    var transforms := _tree_transforms(rows, anchor)
    var near_crowns := transforms["near_crowns"] as Array[Transform3D]
    var far_positions := transforms["far_positions"] as Array[Vector3]
    if replace_existing:
        _clear_tree_foliage_batches()
    _batch("TreeFoliageNear", _presentation_meshes["tree_crown"], near_crowns)
    var offsets := _far_tree_lobe_offsets()
    var far_foliage_instances := 0
    for lobe_index in TREE_FAR_FOLIAGE_LOBE_INDICES:
        var far_lobe_transforms: Array[Transform3D] = []
        for p in far_positions:
            far_lobe_transforms.append(Transform3D(Basis.IDENTITY, p + offsets[lobe_index]))
        far_foliage_instances += far_lobe_transforms.size()
        _batch("TreeFoliageFar_%d" % lobe_index, _presentation_meshes["tree_far_lobe"], far_lobe_transforms)
    last_tree_lod_counts = {
        "near": near_crowns.size(),
        "far": far_positions.size(),
        "foliage_instances": near_crowns.size() + far_foliage_instances,
    }

func _build_tree_batches(rows: Array, anchor: Vector3) -> void:
    _ensure_tree_presentation_meshes()
    var transforms := _tree_transforms(rows, anchor)
    _batch("TreeTrunks", _presentation_meshes["tree_trunk"], transforms["trunks"], true)
    _build_tree_foliage_batches(rows, anchor)

func _build_street_lamp_batches(rows: Array) -> void:
    _ensure_street_lamp_presentation_meshes()
    var poles: Array[Transform3D] = []
    var heads: Array[Transform3D] = []
    for row_variant in rows:
        var p: Vector3 = (row_variant as Dictionary)["position"]
        poles.append(Transform3D(Basis.IDENTITY, p + Vector3(0.0, 2.2, 0.0)))
        heads.append(Transform3D(Basis.IDENTITY, p + Vector3(0.0, 4.38, 0.0)))
    _batch("StreetLampPoles", _presentation_meshes["street_lamp_pole"], poles, true)
    _batch("StreetLampHeads", _presentation_meshes["street_lamp_head"], heads, true)

func _build_bollard_batches(rows: Array) -> void:
    _ensure_bollard_presentation_meshes()
    var transforms: Array[Transform3D] = []
    for row_variant in rows:
        var p: Vector3 = (row_variant as Dictionary)["position"]
        transforms.append(Transform3D(Basis.IDENTITY, p + Vector3(0.0, 0.44, 0.0)))
    _batch("Bollards", _presentation_meshes["bollard_body"], transforms, true)

func _clear_owned_batches() -> void:
    for batch: MultiMeshInstance3D in _owned_batches:
        if not is_instance_valid(batch):
            continue
        if batch.get_parent() != self:
            continue
        remove_child(batch)
        if not batch.is_queued_for_deletion():
            batch.queue_free()
    _owned_batches.clear()

func _rebuild(anchor: Vector3) -> void:
    var trees := _select_rows("tree", anchor, max_trees)
    var lamps := _select_rows("street_lamp", anchor, max_street_lamps)
    var bollards := _select_rows("bollard", anchor, max_bollards)
    _rendered_trees = trees.duplicate(false)
    _tree_lod_boundary_margin_m = 0.0
    _tree_lod_boundary_margin_radius_m = tree_full_detail_radius_m
    _clear_owned_batches()
    _build_tree_batches(trees, anchor)
    _build_street_lamp_batches(lamps)
    _build_bollard_batches(bollards)
    _last_tree_lod_anchor = anchor
    last_render_counts = {
        "tree": trees.size(),
        "street_lamp": lamps.size(),
        "bollard": bollards.size(),
    }
    set_meta("render_counts", last_render_counts.duplicate(true))
    set_meta("tree_lod_counts", last_tree_lod_counts.duplicate(true))
