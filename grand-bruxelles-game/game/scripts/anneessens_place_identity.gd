extends Node3D

const DATA_PATH := "res://data/urbis/anneessens/place_identity.game.json"
var source_loaded := false
var _content := Node3D.new()

func _ready() -> void:
    name = "AnneessensPlaceIdentity"
    set_meta("placement_semantics", "official_surface_centroid_containing_production_anchor")
    set_meta("heritage_record", "Place Anneessens / Urban 10003005")
    set_meta("dimensions_surveyed", false)
    set_meta("geometry_representation", "semantic_proxy")
    add_child(_content)
    _load_and_build()

func set_identity_visible(value: bool) -> void:
    _content.visible = value

func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = roughness
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    return m

func _load_and_build() -> void:
    if not FileAccess.file_exists(DATA_PATH):
        push_warning("Anneessens official source slice missing: %s" % DATA_PATH)
        return
    var f := FileAccess.open(DATA_PATH, FileAccess.READ)
    var data = JSON.parse_string(f.get_as_text())
    if not (data is Dictionary): return
    source_loaded = true
    var feature: Dictionary = data.get("surface", {})
    _build_surface(feature.get("geometry", {}))
    var c = data.get("surface_centroid_game", [])
    if c is Array and c.size() >= 2:
        _build_monument(Vector2(float(c[0]), float(c[1])))
    print("ANNEESSENS_PLACE_IDENTITY_READY: source_loaded=true")

func _outer_rings(g: Dictionary) -> Array:
    var out: Array=[]; var c=g.get("coordinates",[]); var t=String(g.get("type",""))
    if t=="Polygon" and c is Array and not c.is_empty(): out.append(c[0])
    elif t=="MultiPolygon" and c is Array:
        for p in c:
            if p is Array and not p.is_empty(): out.append(p[0])
    return out

func _build_surface(g: Dictionary) -> void:
    var st:=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for ring in _outer_rings(g):
        var pts:=PackedVector2Array()
        for p in ring:
            if p is Array and p.size()>=2: pts.append(Vector2(float(p[0]),float(p[1])))
        if pts.size()>2 and pts[0].distance_to(pts[-1])<0.001: pts.resize(pts.size()-1)
        for idx in Geometry2D.triangulate_polygon(pts):
            var q:=pts[int(idx)]; st.set_normal(Vector3.UP); st.add_vertex(Vector3(q.x,0.035,q.y))
    var mesh=st.commit()
    if mesh:
        mesh.surface_set_material(0,_material(Color(0.36,0.35,0.33,1),0.96))
        var mi:=MeshInstance3D.new(); mi.name="AnneessensOfficialPlaceSurface"; mi.mesh=mesh; _content.add_child(mi)

func _mesh_part(name_: String, mesh: Mesh, pos: Vector3, mat: Material) -> void:
    if mesh is PrimitiveMesh: (mesh as PrimitiveMesh).material=mat
    var mi:=MeshInstance3D.new(); mi.name=name_; mi.mesh=mesh; mi.position=pos; _content.add_child(mi)

func _build_monument(c: Vector2) -> void:
    var blue:=_material(Color(0.20,0.24,0.27,1),0.91)
    var marble:=_material(Color(0.82,0.82,0.77,1),0.86)
    var base:=BoxMesh.new(); base.size=Vector3(3.8,0.55,3.8); _mesh_part("AnneessensBlueStonePlinth",base,Vector3(c.x,0.31,c.y),blue)
    var pedestal:=BoxMesh.new(); pedestal.size=Vector3(2.25,2.45,2.25); _mesh_part("AnneessensBlueStonePedestal",pedestal,Vector3(c.x,1.80,c.y),blue)
    var figure:=CapsuleMesh.new(); figure.radius=0.55; figure.height=2.65; _mesh_part("AnneessensWhiteMarbleFigureProxy",figure,Vector3(c.x,4.35,c.y),marble)
    var head:=SphereMesh.new(); head.radius=0.43; head.height=0.86; _mesh_part("AnneessensWhiteMarbleHeadProxy",head,Vector3(c.x,5.72,c.y),marble)
