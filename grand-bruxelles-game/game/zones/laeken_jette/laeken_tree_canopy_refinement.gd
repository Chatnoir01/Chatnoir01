extends Node3D

## Visual-only canopy refinement for the authoritative City tree positions.
## The base OfficialTrees pass provides cheap source-grounded crowns. For
## broadleaf trees this pass replaces the single primary sphere with three
## deterministic asymmetric lobes, while source X/Z and DTM grounding stay exact.
## When the Atomium benchmark promotes known official trees to a denser primary
## mesh, that primary hero sphere is hidden too: the replacement lobes already
## represent the same source tree and must not create a second artificial crown.

const DATA_PATH := "res://data/environment/laeken_jette/official_city_trees.game.json"
const CONIFER_TOKENS := [
    "abies", "cedrus", "chamaecyparis", "cryptomeria", "cupress", "juniper",
    "larix", "picea", "pinus", "pseudotsuga", "sequo", "taxus", "thuja",
]
const COLUMNAR_TOKENS := ["fastigiata", "columnaris", "populus nigra", "cupressus"]

var refinement_ready: bool = false
var primary_broadleaf_replaced: bool = false
var hero_primary_broadleaf_replaced: bool = false
var broadleaf_lobe_instances: int = 0
var conifer_tier_instances: int = 0
var columnar_lobe_instances: int = 0
var refined_tree_count: int = 0

var _broadleaf_material: StandardMaterial3D
var _conifer_material: StandardMaterial3D
var _columnar_material: StandardMaterial3D


func _ready() -> void:
    call_deferred("_build_refinement")


func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.94
    return material


func _make_materials() -> void:
    _broadleaf_material = _material(Color(0.105, 0.265, 0.085, 1.0))
    _conifer_material = _material(Color(0.065, 0.185, 0.085, 1.0))
    _columnar_material = _material(Color(0.095, 0.235, 0.080, 1.0))


func _load_document() -> Dictionary:
    if not FileAccess.file_exists(DATA_PATH):
        return {}
    var file := FileAccess.open(DATA_PATH, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


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
    return absi((str(feature.get("id", "")) + "|" + species).hash())


func _dimensions(tree_class: String, seed: int) -> Dictionary:
    var a := float(seed % 1000) / 999.0
    var b := float((seed / 1000) % 1000) / 999.0
    match tree_class:
        "conifer":
            var height := lerpf(8.5, 18.0, a)
            return {"height": height, "trunk_height": height * 0.34, "crown_radius": lerpf(2.1, 4.1, b), "crown_height": height * 0.76}
        "columnar":
            var height := lerpf(10.0, 20.0, a)
            return {"height": height, "trunk_height": height * 0.30, "crown_radius": lerpf(1.25, 2.3, b), "crown_height": height * 0.82}
        _:
            var height := lerpf(7.0, 15.5, a)
            return {"height": height, "trunk_height": height * 0.43, "crown_radius": lerpf(2.0, 4.4, b), "crown_height": height * 0.62}


func _sphere_mesh(material: Material, segments: int = 7) -> SphereMesh:
    var mesh := SphereMesh.new()
    mesh.radius = 1.0
    mesh.height = 2.0
    mesh.radial_segments = segments
    mesh.rings = 4
    mesh.material = material
    return mesh


func _cone_mesh(material: Material) -> CylinderMesh:
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.10
    mesh.bottom_radius = 1.0
    mesh.height = 2.0
    mesh.radial_segments = 7
    mesh.rings = 1
    mesh.material = material
    return mesh


func _transform(origin: Vector3, yaw: float, scale: Vector3) -> Transform3D:
    return Transform3D(Basis(Vector3.UP, yaw).scaled(scale), origin)


func _make_multimesh(mesh: Mesh, transforms: Array[Transform3D], node_name: String) -> void:
    if transforms.is_empty():
        return
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.mesh = mesh
    mm.instance_count = transforms.size()
    for index in range(transforms.size()):
        mm.set_instance_transform(index, transforms[index])
    var node := MultiMeshInstance3D.new()
    node.name = node_name
    node.multimesh = mm
    add_child(node)


func _append_broadleaf_lobes(target: Array[Transform3D], origin: Vector3, yaw: float, radius: float, height: float, seed: int) -> void:
    var axis := Vector3(cos(yaw), 0.0, sin(yaw))
    var perpendicular := Vector3(-axis.z, 0.0, axis.x)
    var asymmetry := (float((seed / 1000000) % 1000) / 999.0 - 0.5) * 0.30
    var side_offset := radius * 0.52
    var front_offset := radius * asymmetry

    target.append(_transform(
        origin + perpendicular * front_offset + Vector3(0.0, height * 0.11, 0.0),
        yaw + 0.11,
        Vector3(radius * 0.66, height * 0.31, radius * 0.72)
    ))
    target.append(_transform(
        origin + axis * side_offset + perpendicular * (front_offset + radius * 0.12) + Vector3(0.0, height * 0.01, 0.0),
        yaw + 0.41,
        Vector3(radius * 0.61, height * 0.34, radius * 0.68)
    ))
    target.append(_transform(
        origin - axis * side_offset + perpendicular * (front_offset - radius * 0.10) + Vector3(0.0, -height * 0.07, 0.0),
        yaw - 0.33,
        Vector3(radius * 0.68, height * 0.32, radius * 0.59)
    ))


func _build_refinement() -> void:
    _make_materials()
    var source := _load_document()
    var features = source.get("features", [])
    if not (features is Array) or features.is_empty():
        push_warning("LaekenTreeCanopyRefinement: official tree source unavailable")
        return
    var terrain = get_parent().get_node_or_null("LaekenTerrain")
    var official = get_parent().get_node_or_null("OfficialTrees")
    if terrain == null or official == null or not bool(terrain.get("terrain_loaded")):
        push_warning("LaekenTreeCanopyRefinement: terrain/base tree pass unavailable")
        return

    var broadleaf: Array[Transform3D] = []
    var conifer: Array[Transform3D] = []
    var columnar: Array[Transform3D] = []

    for feature in features:
        if not (feature is Dictionary):
            continue
        var geometry = feature.get("geometry", {})
        if not (geometry is Dictionary) or str(geometry.get("type", "")) != "Point":
            continue
        var coords = geometry.get("coordinates", [])
        if not (coords is Array) or coords.size() < 2:
            continue
        var x := float(coords[0])
        var z := float(coords[1])
        if not bool(terrain.call("contains_game_point", x, z)):
            continue
        var y := float(terrain.call("sample_height", x, z))
        var props = feature.get("properties", {})
        if not (props is Dictionary):
            props = {}
        var species := str(props.get("species", ""))
        var tree_class := _tree_class(species)
        var seed := _seed_for(feature, species)
        var dims := _dimensions(tree_class, seed)
        var tree_height := float(dims["height"])
        var trunk_height := float(dims["trunk_height"])
        var radius := float(dims["crown_radius"])
        var crown_height := float(dims["crown_height"])
        var yaw := deg_to_rad(float(seed % 360))
        var crown_base := maxf(trunk_height * 0.72, tree_height - crown_height)
        var crown_origin := Vector3(x, y + crown_base + crown_height * 0.5, z)

        match tree_class:
            "conifer":
                conifer.append(_transform(
                    crown_origin + Vector3(0.0, -crown_height * 0.17, 0.0),
                    yaw + 0.2,
                    Vector3(radius * 0.78, crown_height * 0.32, radius * 0.78)
                ))
                conifer_tier_instances += 1
            "columnar":
                columnar.append(_transform(
                    crown_origin + Vector3(0.0, crown_height * 0.20, 0.0),
                    yaw,
                    Vector3(radius * 0.70, crown_height * 0.28, radius * 0.68)
                ))
                columnar_lobe_instances += 1
            _:
                _append_broadleaf_lobes(broadleaf, crown_origin, yaw, radius, crown_height, seed)
                broadleaf_lobe_instances += 3
        refined_tree_count += 1

    _make_multimesh(_sphere_mesh(_broadleaf_material, 7), broadleaf, "BroadleafReplacementLobes")
    _make_multimesh(_cone_mesh(_conifer_material), conifer, "ConiferLowerTiers")
    _make_multimesh(_sphere_mesh(_columnar_material, 6), columnar, "ColumnarUpperLobes")

    # Broadleaf replacement lobes are generated for every official broadleaf
    # source record, including the 17 Atomium benchmark trees. Hide both primary
    # broadleaf buckets so those trees are represented exactly once by this pass.
    var primary_broadleaf := get_parent().get_node_or_null("OfficialTrees/OfficialBroadleafCrowns") as MultiMeshInstance3D
    if primary_broadleaf != null:
        primary_broadleaf.visible = false
        primary_broadleaf_replaced = true
    var hero_primary_broadleaf := get_parent().get_node_or_null("OfficialTrees/AtomiumHeroBroadleafCrowns") as MultiMeshInstance3D
    if hero_primary_broadleaf != null:
        hero_primary_broadleaf.visible = false
        hero_primary_broadleaf_replaced = true

    refinement_ready = refined_tree_count > 0 and primary_broadleaf_replaced
    print("LAEKEN_TREE_CANOPY_REFINED: trees=%d broadleaf_lobes=%d conifer_tiers=%d columnar_lobes=%d primary_broadleaf_replaced=%s hero_primary_broadleaf_replaced=%s" % [
        refined_tree_count,
        broadleaf_lobe_instances,
        conifer_tier_instances,
        columnar_lobe_instances,
        primary_broadleaf_replaced,
        hero_primary_broadleaf_replaced,
    ])
