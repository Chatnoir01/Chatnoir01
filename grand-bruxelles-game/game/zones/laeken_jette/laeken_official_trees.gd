extends Node3D

## Source-grounded public-tree population for Laeken/Heysel.
## Positions + species come from City of Brussels Open Data (CC BY 4.0).
## Per-tree dimensions are deterministic visual approximations because the City
## aggregation does not guarantee dimensional fields for every source record.
## The lawful Atomium ground-oblique benchmark has a deterministic source audit;
## only those already-official tree records receive a denser hero mesh. No tree
## position is invented to fill gaps in the explicitly incomplete inventory.

const DATA_PATH := "res://data/environment/laeken_jette/official_city_trees.game.json"
const HERO_AUDIT_PATH := "res://data/reference/laeken_jette/atomium_ground_foreground_inventory.json"
const CONIFER_TOKENS := [
    "abies", "cedrus", "chamaecyparis", "cryptomeria", "cupress", "juniper",
    "larix", "picea", "pinus", "pseudotsuga", "sequo", "taxus", "thuja",
]
const COLUMNAR_TOKENS := ["fastigiata", "columnaris", "populus nigra", "cupressus"]

var trees_loaded: bool = false
var official_tree_count: int = 0
var hero_tree_count: int = 0
var hero_tree_expected_count: int = 0
var broadleaf_count: int = 0
var conifer_count: int = 0
var columnar_count: int = 0
var terrain_grounded_count: int = 0
var skipped_count: int = 0

var _trunk_material: StandardMaterial3D
var _broadleaf_material: StandardMaterial3D
var _conifer_material: StandardMaterial3D
var _columnar_material: StandardMaterial3D


func _ready() -> void:
    call_deferred("_build_official_trees")


func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material


func _make_materials() -> void:
    _trunk_material = _material(Color(0.20, 0.125, 0.075, 1.0), 0.96)
    _broadleaf_material = _material(Color(0.075, 0.20, 0.075, 1.0), 0.94)
    _conifer_material = _material(Color(0.055, 0.15, 0.075, 1.0), 0.95)
    _columnar_material = _material(Color(0.085, 0.19, 0.075, 1.0), 0.94)


func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _load_document() -> Dictionary:
    return _load_json(DATA_PATH)


func _load_hero_tree_ids() -> Dictionary:
    var document := _load_json(HERO_AUDIT_PATH)
    var ids := {}
    var rows = document.get("known_trees", [])
    if not (rows is Array):
        return ids
    hero_tree_expected_count = int(document.get("known_tree_count", rows.size()))
    for row in rows:
        if row is Dictionary:
            var id_text := str(row.get("id", ""))
            if not id_text.is_empty():
                ids[id_text] = true
    return ids


func _tree_class(species: String) -> String:
    var lower := species.to_lower()
    for token in COLUMNAR_TOKENS:
        if lower.contains(token):
            return "columnar"
    for token in CONIFER_TOKENS:
        if lower.contains(token):
            return "conifer"
    return "broadleaf"


func _seed_for(feature: Dictionary, species: String) -> int:
    var id_text := str(feature.get("id", ""))
    return absi((id_text + "|" + species).hash())


func _dimensions(tree_class: String, seed: int) -> Dictionary:
    var unit_a := float(seed % 1000) / 999.0
    var unit_b := float((seed / 1000) % 1000) / 999.0
    match tree_class:
        "conifer":
            var height := lerpf(8.5, 18.0, unit_a)
            return {
                "height": height,
                "trunk_height": height * 0.34,
                "trunk_radius": clampf(height * 0.026, 0.18, 0.46),
                "crown_radius": lerpf(2.1, 4.1, unit_b),
                "crown_height": height * 0.76,
            }
        "columnar":
            var height := lerpf(10.0, 20.0, unit_a)
            return {
                "height": height,
                "trunk_height": height * 0.30,
                "trunk_radius": clampf(height * 0.024, 0.18, 0.44),
                "crown_radius": lerpf(1.25, 2.3, unit_b),
                "crown_height": height * 0.82,
            }
        _:
            var height := lerpf(7.0, 15.5, unit_a)
            return {
                "height": height,
                "trunk_height": height * 0.43,
                "trunk_radius": clampf(height * 0.032, 0.18, 0.52),
                "crown_radius": lerpf(2.0, 4.4, unit_b),
                "crown_height": height * 0.62,
            }


func _create_trunk_mesh(hero: bool = false) -> CylinderMesh:
    var mesh := CylinderMesh.new()
    mesh.top_radius = 1.0
    mesh.bottom_radius = 1.12
    mesh.height = 1.0
    mesh.radial_segments = 12 if hero else 6
    mesh.rings = 1
    mesh.material = _trunk_material
    return mesh


func _create_broadleaf_mesh(hero: bool = false) -> SphereMesh:
    var mesh := SphereMesh.new()
    mesh.radius = 1.0
    mesh.height = 2.0
    mesh.radial_segments = 18 if hero else 8
    mesh.rings = 10 if hero else 5
    mesh.material = _broadleaf_material
    return mesh


func _create_conifer_mesh(hero: bool = false) -> CylinderMesh:
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.08
    mesh.bottom_radius = 1.0
    mesh.height = 2.0
    mesh.radial_segments = 18 if hero else 8
    mesh.rings = 1
    mesh.material = _conifer_material
    return mesh


func _create_columnar_mesh(hero: bool = false) -> SphereMesh:
    var mesh := SphereMesh.new()
    mesh.radius = 1.0
    mesh.height = 2.0
    mesh.radial_segments = 14 if hero else 7
    mesh.rings = 8 if hero else 5
    mesh.material = _columnar_material
    return mesh


func _make_multimesh(mesh: Mesh, transforms: Array[Transform3D], node_name: String) -> void:
    if transforms.is_empty():
        return
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.use_colors = false
    multimesh.use_custom_data = false
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()
    for index in range(transforms.size()):
        multimesh.set_instance_transform(index, transforms[index])
    var instance := MultiMeshInstance3D.new()
    instance.name = node_name
    instance.multimesh = multimesh
    add_child(instance)


func _transform_for(origin: Vector3, yaw: float, scale: Vector3) -> Transform3D:
    var basis := Basis(Vector3.UP, yaw).scaled(scale)
    return Transform3D(basis, origin)


func _build_official_trees() -> void:
    _make_materials()
    var document := _load_document()
    var features = document.get("features", [])
    if not (features is Array) or features.is_empty():
        push_warning("LaekenOfficialTrees: official tree runtime not available yet")
        return

    var terrain = get_parent().get_node_or_null("LaekenTerrain")
    if terrain == null or not bool(terrain.get("terrain_loaded")):
        push_warning("LaekenOfficialTrees: official DTM terrain unavailable")
        return

    var hero_tree_ids := _load_hero_tree_ids()
    if hero_tree_ids.is_empty():
        push_warning("LaekenOfficialTrees: Atomium hero-tree audit unavailable; retaining standard LOD for all official trees")

    var trunk_transforms: Array[Transform3D] = []
    var broadleaf_transforms: Array[Transform3D] = []
    var conifer_transforms: Array[Transform3D] = []
    var columnar_transforms: Array[Transform3D] = []
    var hero_trunk_transforms: Array[Transform3D] = []
    var hero_broadleaf_transforms: Array[Transform3D] = []
    var hero_conifer_transforms: Array[Transform3D] = []
    var hero_columnar_transforms: Array[Transform3D] = []

    for feature in features:
        if not (feature is Dictionary):
            skipped_count += 1
            continue
        var geometry = feature.get("geometry", {})
        if not (geometry is Dictionary) or str(geometry.get("type", "")) != "Point":
            skipped_count += 1
            continue
        var coordinates = geometry.get("coordinates", [])
        if not (coordinates is Array) or coordinates.size() < 2:
            skipped_count += 1
            continue
        var x := float(coordinates[0])
        var z := float(coordinates[1])
        if not bool(terrain.call("contains_game_point", x, z)):
            skipped_count += 1
            continue
        var y := float(terrain.call("sample_height", x, z))
        terrain_grounded_count += 1

        var properties = feature.get("properties", {})
        if not (properties is Dictionary):
            properties = {}
        var species := str(properties.get("species", ""))
        var tree_class := _tree_class(species)
        var seed := _seed_for(feature, species)
        var dims := _dimensions(tree_class, seed)
        var trunk_height := float(dims["trunk_height"])
        var trunk_radius := float(dims["trunk_radius"])
        var crown_radius := float(dims["crown_radius"])
        var crown_height := float(dims["crown_height"])
        var yaw := deg_to_rad(float(seed % 360))
        var feature_id := str(feature.get("id", ""))
        var is_hero := hero_tree_ids.has(feature_id)

        var trunk_transform := _transform_for(
            Vector3(x, y + trunk_height * 0.5, z),
            yaw,
            Vector3(trunk_radius, trunk_height, trunk_radius)
        )
        if is_hero:
            hero_trunk_transforms.append(trunk_transform)
            hero_tree_count += 1
        else:
            trunk_transforms.append(trunk_transform)

        var crown_base := maxf(trunk_height * 0.72, float(dims["height"]) - crown_height)
        var crown_origin := Vector3(x, y + crown_base + crown_height * 0.5, z)
        var crown_scale := Vector3(crown_radius, crown_height * 0.5, crown_radius)
        var crown_transform := _transform_for(crown_origin, yaw, crown_scale)
        match tree_class:
            "conifer":
                if is_hero:
                    hero_conifer_transforms.append(crown_transform)
                else:
                    conifer_transforms.append(crown_transform)
                conifer_count += 1
            "columnar":
                if is_hero:
                    hero_columnar_transforms.append(crown_transform)
                else:
                    columnar_transforms.append(crown_transform)
                columnar_count += 1
            _:
                if is_hero:
                    hero_broadleaf_transforms.append(crown_transform)
                else:
                    broadleaf_transforms.append(crown_transform)
                broadleaf_count += 1
        official_tree_count += 1

    _make_multimesh(_create_trunk_mesh(false), trunk_transforms, "OfficialTreeTrunks")
    _make_multimesh(_create_broadleaf_mesh(false), broadleaf_transforms, "OfficialBroadleafCrowns")
    _make_multimesh(_create_conifer_mesh(false), conifer_transforms, "OfficialConiferCrowns")
    _make_multimesh(_create_columnar_mesh(false), columnar_transforms, "OfficialColumnarCrowns")
    _make_multimesh(_create_trunk_mesh(true), hero_trunk_transforms, "AtomiumHeroTreeTrunks")
    _make_multimesh(_create_broadleaf_mesh(true), hero_broadleaf_transforms, "AtomiumHeroBroadleafCrowns")
    _make_multimesh(_create_conifer_mesh(true), hero_conifer_transforms, "AtomiumHeroConiferCrowns")
    _make_multimesh(_create_columnar_mesh(true), hero_columnar_transforms, "AtomiumHeroColumnarCrowns")

    trees_loaded = official_tree_count > 0
    if trees_loaded:
        # The old approach trees were explicitly photo-guided placeholders. Once
        # official inventory positions are available, remove only those fake tree
        # nodes while retaining their separately sourced lamps/road markings.
        await get_tree().process_frame
        var approach := get_parent().get_node_or_null("AtomiumApproachPhotoGuided")
        if approach != null:
            for child in approach.get_children():
                if child.name == "ApproachTree":
                    child.queue_free()

    print("LAEKEN_OFFICIAL_TREES_READY: total=%d hero=%d/%d terrain=%d broadleaf=%d conifer=%d columnar=%d skipped=%d" % [
        official_tree_count,
        hero_tree_count,
        hero_tree_expected_count,
        terrain_grounded_count,
        broadleaf_count,
        conifer_count,
        columnar_count,
        skipped_count,
    ])
