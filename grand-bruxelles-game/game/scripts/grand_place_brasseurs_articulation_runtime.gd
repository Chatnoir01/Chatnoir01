extends Node3D

const BUILDING_ID := "https://databrussels.be/id/building/1639974"
const SOURCE_WALL_ID := "https://databrussels.be/id/buildingface/10945501"
const WALL_A := Vector3(317.9358, 0.0, -487.4869)
const WALL_B := Vector3(325.8848, 0.0, -483.8319)
const PLAYER_SIDE := Vector3(319.01, 1.72, -535.20)
const SOURCE_FACADE_SPAN_M := 8.7490357183

var articulation_ready := false
var building_id := BUILDING_ID
var source_wall_id := SOURCE_WALL_ID
var source_facade_span_m := SOURCE_FACADE_SPAN_M
var bay_count := 3
var colossal_corinthian_half_columns := true
var curved_pediment := true
var axial_bay_wider_and_projecting := true
var placement_semantics := "official_lod2_wall_plus_heritage_large_form_visualization_convention_not_survey"
var geometry_claimed_surveyed := false
var column_proxy_count := 0
var pediment_segment_count := 0

var _stone: StandardMaterial3D
var _accent_stone: StandardMaterial3D

func _ready() -> void:
    _stone = _make_stone(Color(0.78, 0.75, 0.66, 1.0), 0.72)
    _accent_stone = _make_stone(Color(0.69, 0.65, 0.56, 1.0), 0.78)
    _build_large_form()
    set_meta("building_id", BUILDING_ID)
    set_meta("source_wall_id", SOURCE_WALL_ID)
    set_meta("heritage_source", "urban.brussels/31127")
    set_meta("source_facade_span_m", SOURCE_FACADE_SPAN_M)
    set_meta("source_geometry_changed", false)
    set_meta("column_proxy_count_source", "visualization_convention_not_source")
    set_meta("decorative_dimensions", "visualization_convention_not_survey")
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    articulation_ready = column_proxy_count == 4 and pediment_segment_count == 12
    print("GRAND_PLACE_BRASSEURS_ARTICULATION_READY: building=1639974 wall=10945501 bays=3 columns=%d pediment_segments=%d surveyed=false" % [column_proxy_count, pediment_segment_count])

func _make_stone(color: Color, roughness_value: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness_value
    material.metallic = 0.0
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material

func _wall_frame() -> Dictionary:
    var tangent := (WALL_B - WALL_A)
    tangent.y = 0.0
    tangent = tangent.normalized()
    var normal := Vector3(-tangent.z, 0.0, tangent.x)
    var midpoint := (WALL_A + WALL_B) * 0.5
    if normal.dot(PLAYER_SIDE - midpoint) < 0.0:
        normal = -normal
    return {"tangent": tangent, "normal": normal, "midpoint": midpoint}

func _build_large_form() -> void:
    var frame := _wall_frame()
    var tangent: Vector3 = frame["tangent"]
    var normal: Vector3 = frame["normal"]
    var midpoint: Vector3 = frame["midpoint"]

    # Three documented bays; exact bay widths are a bounded visualization convention.
    # The central bay is intentionally wider (1.25x a side bay) and slightly projected.
    var side_fraction := 1.0 / 3.25
    var boundaries := [0.0, side_fraction, 1.0 - side_fraction, 1.0]
    for i: int in range(boundaries.size()):
        var t: float = float(boundaries[i])
        var center := WALL_A.lerp(WALL_B, t)
        center.y = 9.3
        # Sink the authored full cylinder into the wall plane so it reads as a half-column.
        center -= normal * 0.11
        _add_column_proxy(center, i, normal)

    var central_width := SOURCE_FACADE_SPAN_M * (1.25 / 3.25)
    var central_center := midpoint + normal * 0.105
    central_center.y = 9.15
    _add_oriented_box("AxialBayProjection", central_center, tangent, normal, Vector3(central_width, 15.7, 0.18), _accent_stone)

    # Curved fronton: identity is documented; exact width/rise/profile are authored and
    # kept below the official LoD2 roof envelope rather than presented as surveyed.
    _add_curved_pediment(midpoint + normal * 0.16, tangent, normal, 7.35, 17.75, 2.15, 12)

func _add_column_proxy(center: Vector3, index: int, normal: Vector3) -> void:
    var shaft := MeshInstance3D.new()
    shaft.name = "ColossalHalfColumn_%02d" % (index + 1)
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = 0.245
    cylinder.bottom_radius = 0.29
    cylinder.height = 15.25
    cylinder.radial_segments = 12
    cylinder.rings = 1
    cylinder.material = _stone
    shaft.mesh = cylinder
    shaft.position = center
    add_child(shaft)

    var capital := MeshInstance3D.new()
    capital.name = "CapitalProxy_%02d" % (index + 1)
    var cap_mesh := CylinderMesh.new()
    cap_mesh.top_radius = 0.42
    cap_mesh.bottom_radius = 0.34
    cap_mesh.height = 0.55
    cap_mesh.radial_segments = 12
    cap_mesh.material = _stone
    capital.mesh = cap_mesh
    capital.position = Vector3(center.x, 17.18, center.z) + normal * 0.015
    add_child(capital)

    var abacus := MeshInstance3D.new()
    abacus.name = "AbacusProxy_%02d" % (index + 1)
    var abacus_mesh := BoxMesh.new()
    abacus_mesh.size = Vector3(0.78, 0.22, 0.62)
    abacus_mesh.material = _stone
    abacus.mesh = abacus_mesh
    abacus.position = Vector3(center.x, 17.52, center.z) + normal * 0.03
    add_child(abacus)
    column_proxy_count += 1

func _add_oriented_box(name_value: String, center: Vector3, tangent: Vector3, normal: Vector3, size_value: Vector3, material: Material) -> void:
    var node := MeshInstance3D.new()
    node.name = name_value
    var mesh := BoxMesh.new()
    mesh.size = size_value
    mesh.material = material
    node.mesh = mesh
    node.transform = Transform3D(Basis(tangent, Vector3.UP, normal), center)
    add_child(node)

func _add_curved_pediment(origin: Vector3, tangent: Vector3, normal: Vector3, width: float, base_y: float, rise: float, segments: int) -> void:
    var boundary: Array[Vector3] = []
    var half_w := width * 0.5
    var left_base := origin - tangent * half_w
    left_base.y = base_y
    boundary.append(left_base + normal * 0.02)
    for i: int in range(segments + 1):
        var u := float(i) / float(segments)
        var x := -half_w + width * u
        # Segmental arch profile: 0 at shoulders, rise at axis.
        var normalized := x / half_w
        var y := base_y + rise * sqrt(maxf(0.0, 1.0 - normalized * normalized))
        var p := origin + tangent * x + normal * 0.02
        p.y = y
        boundary.append(p)
    var right_base := origin + tangent * half_w
    right_base.y = base_y
    boundary.append(right_base + normal * 0.02)

    var center := origin + normal * 0.02
    center.y = base_y + rise * 0.42
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(_stone)
    for i: int in range(boundary.size() - 1):
        tool.set_normal(normal)
        tool.add_vertex(center)
        tool.set_normal(normal)
        tool.add_vertex(boundary[i])
        tool.set_normal(normal)
        tool.add_vertex(boundary[i + 1])
    var node := MeshInstance3D.new()
    node.name = "CurvedPedimentProxy"
    node.mesh = tool.commit()
    add_child(node)
    pediment_segment_count = segments

func set_articulation_visible(enabled: bool) -> void:
    visible = enabled

func articulation_visible() -> bool:
    return visible
