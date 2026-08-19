extends Node3D

const SOURCE_DIR := "res://data/urbis/grand_place_lod2"
const CONTRACT_PATH := "res://data/qa/grand_place_facade_presentation.contract.json"
const IDENTITY_PATH := "res://data/qa/grand_place_facade_owner_identity.lock.json"
const CONTOUR_NAME := "GrandPlaceCompleteContourRuntime"
const PACKAGE_SHA256 := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
const CANONICAL_CAMERA := Vector3(319.01, 1.72, -535.20)
const RELIEF_DEPTH := 0.10
const EXPECTED_STYLED_IDS := ["1608847", "1608851", "1635485", "1639974", "1646728", "1654360"]
const EXPECTED_HOLD_IDS := ["1601883","1601884","1611166","1613517","1635455","1637695","1637729","1639985","1643344","1645578","1645580","1647834","1647943","1649069","1653185","1661439","1781508"]

var built := false
var failed := false
var presentation_visible := true
var feature_count := 0
var styled_owner_ids: Array[String] = []
var hold_owner_ids: Array[String] = []

var _detail_root: Node3D
var _contour: Node
var _wall_meshes: Dictionary = {}
var _roof_meshes: Dictionary = {}
var _original_wall_materials: Dictionary = {}
var _original_roof_materials: Dictionary = {}
var _styled_wall_materials: Dictionary = {}
var _styled_roof_materials: Dictionary = {}
var _owner_feature_counts: Dictionary = {}

func _ready() -> void:
    call_deferred("_build_when_ready")

func _fail(message: String) -> void:
    failed = true
    push_error("Grand-Place facade presentation: %s" % message)

func _build_when_ready() -> void:
    _contour = get_tree().root.get_node_or_null(CONTOUR_NAME)
    for _frame: int in range(600):
        if _contour != null and bool(_contour.get("geometry_loaded")):
            break
        await get_tree().process_frame
        _contour = get_tree().root.get_node_or_null(CONTOUR_NAME)
    if _contour == null or not bool(_contour.get("geometry_loaded")):
        _fail("complete contour runtime not ready")
        return
    var contract := _read_json(CONTRACT_PATH)
    var identity := _read_json(IDENTITY_PATH)
    if contract.is_empty() or identity.is_empty():
        return
    if not _validate_contract(contract, identity):
        return
    _detail_root = Node3D.new()
    _detail_root.name = "GrandPlaceFacadePresentationDetails"
    add_child(_detail_root)
    var owners: Dictionary = contract.get("owners", {})
    for owner_id: String in EXPECTED_STYLED_IDS:
        var owner_contract: Dictionary = owners.get(owner_id, {})
        if owner_contract.is_empty():
            _fail("resolved owner missing contract: %s" % owner_id)
            return
        if not _build_owner(owner_id, owner_contract):
            return
    hold_owner_ids.assign(EXPECTED_HOLD_IDS)
    styled_owner_ids.sort()
    if styled_owner_ids != EXPECTED_STYLED_IDS:
        _fail("styled owner set drifted")
        return
    if feature_count < 80:
        _fail("facade feature budget too small: %d" % feature_count)
        return
    built = true
    set_meta("identity_resolved_count", 6)
    set_meta("hold_count", 17)
    set_meta("source_geometry_changed", false)
    set_meta("source_collision_changed", false)
    set_meta("survey_dimensions_claimed", false)
    set_meta("exact_material_rgb_claimed", false)
    set_meta("statuary_authored", false)
    set_meta("finished_perfect", false)
    set_meta("human_multiview_pass_required", true)
    print("GRAND_PLACE_FACADE_PRESENTATION_READY: styled=6 hold=17 features=%d geometry_changed=false collision_changed=false finished_perfect=false" % feature_count)

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        _fail("missing JSON: %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("invalid JSON: %s" % path)
        return {}
    return parsed as Dictionary

func _validate_contract(contract: Dictionary, identity: Dictionary) -> bool:
    if str(contract.get("schema", "")) != "grand-bruxelles-grand-place-facade-presentation-v1":
        _fail("presentation contract schema drifted")
        return false
    if str(identity.get("schema", "")) != "grand-bruxelles-grand-place-facade-owner-identity-lock-v1":
        _fail("identity lock schema drifted")
        return false
    if str(contract.get("source_geometry_package_sha256", "")) != PACKAGE_SHA256:
        _fail("source package drifted")
        return false
    var resolved: Array = identity.get("resolved", [])
    var resolved_ids: Array[String] = []
    for raw: Variant in resolved:
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        resolved_ids.append(str(raw.get("building_id", "")))
    resolved_ids.sort()
    if resolved_ids != EXPECTED_STYLED_IDS:
        _fail("identity resolved owner set drifted")
        return false
    var holds: Array[String] = []
    for raw: Variant in identity.get("hold_owner_ids", []):
        holds.append(str(raw))
    holds.sort()
    var expected_holds := EXPECTED_HOLD_IDS.duplicate()
    expected_holds.sort()
    if holds != expected_holds:
        _fail("identity HOLD owner set drifted")
        return false
    return true

func _point(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _triangle(raw: Variant) -> Array[Vector3]:
    var out: Array[Vector3] = []
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return out
    for raw_point: Variant in raw:
        var p := _point(raw_point)
        if not p.is_finite():
            return []
        out.append(p)
    return out

func _triangle_area(points: Array[Vector3]) -> float:
    if points.size() != 3:
        return 0.0
    return 0.5 * (points[1] - points[0]).cross(points[2] - points[0]).length()

func _horizontal_normal(points: Array[Vector3], toward: Vector3) -> Vector3:
    if points.size() != 3:
        return Vector3.ZERO
    var normal := (points[1] - points[0]).cross(points[2] - points[0])
    normal.y = 0.0
    if normal.length_squared() < 0.0001:
        return Vector3.ZERO
    normal = normal.normalized()
    var center := (points[0] + points[1] + points[2]) / 3.0
    var direction := Vector3(toward.x - center.x, 0.0, toward.z - center.z)
    if direction.length_squared() > 0.0001 and normal.dot(direction.normalized()) < 0.0:
        normal = -normal
    return normal

func _read_owner_geometry(owner_id: String) -> Dictionary:
    var path := SOURCE_DIR.path_join("%s.game.json" % owner_id)
    var data := _read_json(path)
    if data.is_empty():
        return {}
    var source: Dictionary = data.get("source", {})
    if str(source.get("building_2d_id", "")) != "https://databrussels.be/id/building/%s" % owner_id:
        _fail("owner source identity drifted: %s" % owner_id)
        return {}
    if str(source.get("package_sha256", "")) != PACKAGE_SHA256:
        _fail("owner source package drifted: %s" % owner_id)
        return {}
    return data

func _resolve_facade(data: Dictionary) -> Dictionary:
    var faces: Array = data.get("faces", [])
    var best_score := 0.0
    var best_points: Array[Vector3] = []
    var best_normal := Vector3.ZERO
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY or str(raw_face.get("type", "")) != "WALLSURFACE":
            continue
        for raw_tri: Variant in raw_face.get("triangles", []):
            var points := _triangle(raw_tri)
            if points.size() != 3:
                continue
            var normal := _horizontal_normal(points, CANONICAL_CAMERA)
            if normal.length_squared() < 0.5:
                continue
            var center := (points[0] + points[1] + points[2]) / 3.0
            var to_camera := Vector3(CANONICAL_CAMERA.x - center.x, 0.0, CANONICAL_CAMERA.z - center.z)
            if to_camera.length_squared() < 0.01:
                continue
            var facing := maxf(0.0, normal.dot(to_camera.normalized()))
            var score := _triangle_area(points) * facing * facing
            if facing > 0.55 and score > best_score:
                best_score = score
                best_points = points
                best_normal = normal
    if best_points.size() != 3:
        return {}
    var tangent := Vector3(-best_normal.z, 0.0, best_normal.x).normalized()
    var plane_point := (best_points[0] + best_points[1] + best_points[2]) / 3.0
    var initialized := false
    var min_u := 0.0
    var max_u := 0.0
    var min_y := 0.0
    var max_y := 0.0
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY or str(raw_face.get("type", "")) != "WALLSURFACE":
            continue
        for raw_tri: Variant in raw_face.get("triangles", []):
            var points := _triangle(raw_tri)
            if points.size() != 3:
                continue
            var normal := _horizontal_normal(points, CANONICAL_CAMERA)
            if normal.length_squared() < 0.5 or normal.dot(best_normal) < 0.88:
                continue
            var center := (points[0] + points[1] + points[2]) / 3.0
            if absf((center - plane_point).dot(best_normal)) > 2.0:
                continue
            for p: Vector3 in points:
                var u := p.dot(tangent)
                if not initialized:
                    min_u = u
                    max_u = u
                    min_y = p.y
                    max_y = p.y
                    initialized = true
                else:
                    min_u = minf(min_u, u)
                    max_u = maxf(max_u, u)
                    min_y = minf(min_y, p.y)
                    max_y = maxf(max_y, p.y)
    if not initialized or max_u - min_u < 3.0 or max_y - min_y < 8.0:
        return {}
    return {"normal":best_normal,"tangent":tangent,"plane_point":plane_point,"min_u":min_u,"max_u":max_u,"min_y":min_y,"max_y":max_y,"width":max_u-min_u,"height":max_y-min_y}

func _standard_material(color: Color, roughness: float, label: String) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = roughness
    mat.cull_mode = BaseMaterial3D.CULL_BACK
    mat.set_meta("source_label", label)
    mat.set_meta("authored_presentation_only", true)
    mat.set_meta("exact_rgb_is_photometric_measurement", false)
    mat.set_meta("masonry_courses_authored", false)
    return mat

func _white_stone(label: String) -> Material:
    return BrusselsWhiteStoneMaterial.create(Color(0.69,0.67,0.62,1.0),Color(0.87,0.83,0.74,1.0),0.82,label)

func _wall_material(_owner_id: String, profile: String) -> Material:
    match profile:
        "cornet": return _white_stone("Urban 31123: Gobertange/Euville restoration; exact RGB authored")
        "renard": return _white_stone("Urban 31124: white stone with blue-stone restoration; exact RGB authored")
        "brasseurs": return _white_stone("Urban 31127: Euville/Gobertange plus blue stone; exact RGB authored")
        "mont_thabor": return _standard_material(Color(0.74,0.70,0.61,1.0),0.90,"Urban 30907: cemented facade with Gobertange/Euville/Savonniere details; exact RGB authored")
        "maison_du_roi": return _standard_material(Color(0.52,0.42,0.34,1.0),0.88,"Urban 31143: brick, blue stone and Gobertange; exact RGB authored")
        "rose": return _standard_material(Color(0.72,0.65,0.54,1.0),0.88,"Urban 31128: Baroque facade; exact RGB authored, material identity not claimed")
    return _standard_material(Color(0.58,0.56,0.52,1.0),0.88,"unreachable fallback")

func _roof_material(profile: String) -> Material:
    if profile in ["brasseurs","maison_du_roi"]:
        return _standard_material(Color(0.13,0.16,0.18,1.0),0.92,"Urban heritage inventory: slate roof; exact RGB authored")
    if profile in ["rose","mont_thabor"]:
        return _standard_material(Color(0.30,0.20,0.16,1.0),0.91,"Urban heritage inventory: S-tile roof; exact RGB authored")
    return null

func _dark_window_material() -> Material:
    return _standard_material(Color(0.055,0.075,0.085,1.0),0.62,"authored glazing presentation; no photometric claim")

func _blue_stone_material() -> Material:
    return _standard_material(Color(0.20,0.23,0.25,1.0),0.92,"Urban heritage inventory: blue stone; exact RGB authored")

func _gold_material() -> StandardMaterial3D:
    var mat := _standard_material(Color(0.62,0.45,0.12,1.0),0.44,"Urban heritage inventory: gilded ornament; exact RGB authored")
    mat.metallic = 0.28
    return mat

func _world(frame: Dictionary, u: float, y: float, depth: float = RELIEF_DEPTH) -> Vector3:
    var tangent: Vector3 = frame["tangent"]
    var normal: Vector3 = frame["normal"]
    var point: Vector3 = frame["plane_point"]
    return point + tangent*(u-point.dot(tangent)) + Vector3.UP*(y-point.y) + normal*depth

func _add_box(owner_root: Node3D, frame: Dictionary, name_value: String, u: float, y: float, width: float, height: float, depth: float, mat: Material) -> void:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(maxf(width,0.02),maxf(height,0.02),maxf(depth,0.02))
    var node := MeshInstance3D.new()
    node.name = name_value
    node.mesh = mesh
    node.material_override = mat
    node.position = _world(frame,u,y,RELIEF_DEPTH+depth*0.5)
    node.basis = Basis(frame["tangent"],Vector3.UP,frame["normal"])
    node.set_meta("source_geometry",false)
    node.set_meta("presentation_dimension_surveyed",false)
    owner_root.add_child(node)
    feature_count += 1

func _add_pointed_panel(owner_root: Node3D, frame: Dictionary, name_value: String, center_u: float, bottom_y: float, width: float, height: float, mat: Material) -> void:
    var half := width*0.5
    var shoulder_y := bottom_y+height*0.76
    var points: Array[Vector3] = [_world(frame,center_u-half,bottom_y),_world(frame,center_u+half,bottom_y),_world(frame,center_u+half,shoulder_y),_world(frame,center_u,bottom_y+height),_world(frame,center_u-half,shoulder_y)]
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(mat)
    for index: int in [0,1,2,0,2,3,0,3,4]:
        tool.set_normal(frame["normal"])
        tool.add_vertex(points[index])
    var node := MeshInstance3D.new()
    node.name = name_value
    node.mesh = tool.commit()
    node.set_meta("source_geometry",false)
    node.set_meta("presentation_dimension_surveyed",false)
    owner_root.add_child(node)
    feature_count += 1

func _find_contour_mesh(owner_id: String, face_type: String) -> MeshInstance3D:
    var node := _contour.get_node_or_null("GrandPlaceContour_%s_%s" % [owner_id,face_type])
    return node as MeshInstance3D if node is MeshInstance3D else null

func _build_owner(owner_id: String, owner_contract: Dictionary) -> bool:
    var data := _read_owner_geometry(owner_id)
    if data.is_empty(): return false
    var frame := _resolve_facade(data)
    if frame.is_empty():
        _fail("square-facing facade plane unresolved: %s" % owner_id)
        return false
    var wall := _find_contour_mesh(owner_id,"WALLSURFACE")
    if wall == null:
        _fail("contour wall mesh missing: %s" % owner_id)
        return false
    var profile := str(owner_contract.get("render_profile",""))
    var wall_mat := _wall_material(owner_id,profile)
    _wall_meshes[owner_id] = wall
    _original_wall_materials[owner_id] = wall.material_override
    _styled_wall_materials[owner_id] = wall_mat
    wall.material_override = wall_mat
    wall.set_meta("presentation_identity",str(owner_contract.get("official_name","")))
    wall.set_meta("grand_place_number",str(owner_contract.get("grand_place_number","")))
    wall.set_meta("urban_record_id",str(owner_contract.get("urban_record_id","")))
    wall.set_meta("source_geometry_unchanged",true)
    wall.set_meta("presentation_dimensions_surveyed",false)
    var roof_mat := _roof_material(profile)
    if roof_mat != null:
        var roof := _find_contour_mesh(owner_id,"ROOFSURFACE")
        if roof != null:
            _roof_meshes[owner_id] = roof
            _original_roof_materials[owner_id] = roof.material_override
            _styled_roof_materials[owner_id] = roof_mat
            roof.material_override = roof_mat
            roof.set_meta("presentation_identity",str(owner_contract.get("official_name","")))
            roof.set_meta("source_geometry_unchanged",true)
    var owner_root := Node3D.new()
    owner_root.name = "Facade_%s_%s" % [owner_id,str(owner_contract.get("official_name","")).replace(" ","_")]
    owner_root.set_meta("urbis_owner_id",owner_id)
    owner_root.set_meta("source_record","Urban Brussels %s" % str(owner_contract.get("urban_record_id","")))
    owner_root.set_meta("source_geometry_changed",false)
    owner_root.set_meta("source_collision_changed",false)
    owner_root.set_meta("survey_dimensions_claimed",false)
    _detail_root.add_child(owner_root)
    var before := feature_count
    match profile:
        "cornet": _build_cornet(owner_root,frame)
        "renard": _build_renard(owner_root,frame)
        "rose": _build_rose(owner_root,frame)
        "brasseurs": _build_brasseurs(owner_root,frame)
        "mont_thabor": _build_mont_thabor(owner_root,frame)
        "maison_du_roi": _build_maison_du_roi(owner_root,frame)
        _:
            _fail("unsupported render profile: %s" % profile)
            return false
    _owner_feature_counts[owner_id] = feature_count-before
    styled_owner_ids.append(owner_id)
    return true

func _body_bounds(frame: Dictionary) -> Dictionary:
    var width := float(frame["width"])
    var height := float(frame["height"])
    return {"left":float(frame["min_u"])+width*0.07,"right":float(frame["max_u"])-width*0.07,"bottom":float(frame["min_y"])+height*0.08,"top":float(frame["min_y"])+height*0.72}

func _add_regular_windows(owner_root: Node3D, frame: Dictionary, bays: int, levels: int, cross_windows: bool = false) -> void:
    var body := _body_bounds(frame)
    var left := float(body["left"]); var right := float(body["right"]); var bottom := float(body["bottom"]); var top := float(body["top"])
    var bay_w := (right-left)/float(bays); var level_h := (top-bottom)/float(levels)
    var dark := _dark_window_material(); var blue := _blue_stone_material()
    for level: int in range(levels):
        var center_y := bottom+level_h*(float(level)+0.52)
        for bay: int in range(bays):
            var center_u := left+bay_w*(float(bay)+0.5); var window_w := bay_w*0.54; var window_h := level_h*0.56
            _add_box(owner_root,frame,"Window_%d_%d"%[level,bay],center_u,center_y,window_w,window_h,0.055,dark)
            if cross_windows:
                _add_box(owner_root,frame,"CrossV_%d_%d"%[level,bay],center_u,center_y,maxf(0.07,window_w*0.07),window_h*1.02,0.07,blue)
                _add_box(owner_root,frame,"CrossH_%d_%d"%[level,bay],center_u,center_y,window_w*1.02,maxf(0.07,window_h*0.055),0.07,blue)

func _add_pilaster_rhythm(owner_root: Node3D, frame: Dictionary, bays: int, material: Material, width_ratio: float = 0.022) -> void:
    var body := _body_bounds(frame); var left := float(body["left"]); var right := float(body["right"]); var bottom := float(body["bottom"]); var top := float(body["top"])
    var bay_w := (right-left)/float(bays); var strip_w := maxf(float(frame["width"])*width_ratio,0.12)
    for i: int in range(bays+1):
        _add_box(owner_root,frame,"Pilaster_%d"%i,left+bay_w*float(i),(bottom+top)*0.5,strip_w,top-bottom,0.075,material)

func _add_register_bands(owner_root: Node3D, frame: Dictionary, levels: int, material: Material) -> void:
    var body := _body_bounds(frame); var left := float(body["left"]); var right := float(body["right"]); var bottom := float(body["bottom"]); var top := float(body["top"])
    var level_h := (top-bottom)/float(levels)
    for i: int in range(1,levels):
        _add_box(owner_root,frame,"Register_%d"%i,(left+right)*0.5,bottom+level_h*float(i),right-left,0.16,0.075,material)

func _add_entresol(owner_root: Node3D, frame: Dictionary, bays: int) -> void:
    var body := _body_bounds(frame); var left := float(body["left"]); var right := float(body["right"]); var y := float(frame["min_y"])+float(frame["height"])*0.105
    var bay_w := (right-left)/float(bays); var dark := _dark_window_material()
    for bay: int in range(bays):
        _add_box(owner_root,frame,"Entresol_%d"%bay,left+bay_w*(float(bay)+0.5),y,bay_w*0.42,maxf(0.42,float(frame["height"])*0.025),0.05,dark)

func _build_cornet(owner_root: Node3D, frame: Dictionary) -> void:
    var stone := _white_stone("Urban 31123: Gobertange/Euville restoration"); var gold := _gold_material(); var dark := _dark_window_material()
    _add_regular_windows(owner_root,frame,3,3,false); _add_entresol(owner_root,frame,3); _add_pilaster_rhythm(owner_root,frame,3,stone); _add_register_bands(owner_root,frame,3,stone)
    var left := float(frame["min_u"])+float(frame["width"])*0.17; var right := float(frame["max_u"])-float(frame["width"])*0.17; var oculus_y := float(frame["min_y"])+float(frame["height"])*0.675; var bay_w := (right-left)/3.0
    for i: int in range(3): _add_box(owner_root,frame,"OculusCue_%d"%i,left+bay_w*(float(i)+0.5),oculus_y,bay_w*0.28,maxf(0.34,float(frame["height"])*0.022),0.06,dark)
    for i: int in range(2): _add_box(owner_root,frame,"GildedMaritimeCue_%d"%i,left+bay_w*float(i+1),oculus_y-float(frame["height"])*0.04,maxf(0.10,bay_w*0.10),maxf(0.32,float(frame["height"])*0.025),0.08,gold)
    var center := (float(frame["min_u"])+float(frame["max_u"]))*0.5
    _add_box(owner_root,frame,"ShipSternLower",center,float(frame["min_y"])+float(frame["height"])*0.775,float(frame["width"])*0.64,0.18,0.08,stone)
    _add_box(owner_root,frame,"ShipSternUpper",center,float(frame["min_y"])+float(frame["height"])*0.855,float(frame["width"])*0.44,0.18,0.08,stone)

func _build_renard(owner_root: Node3D, frame: Dictionary) -> void:
    var stone := _white_stone("Urban 31124: white stone facade"); var blue := _blue_stone_material()
    _add_regular_windows(owner_root,frame,4,3,false); _add_entresol(owner_root,frame,4); _add_pilaster_rhythm(owner_root,frame,4,stone); _add_register_bands(owner_root,frame,3,stone)
    var body := _body_bounds(frame)
    _add_box(owner_root,frame,"BlueStoneBase",(float(body["left"])+float(body["right"]))*0.5,float(body["bottom"])-0.12,float(body["right"])-float(body["left"]),0.24,0.08,blue)
    _add_box(owner_root,frame,"ContinuousBalconyCue",(float(body["left"])+float(body["right"]))*0.5,float(body["bottom"])+(float(body["top"])-float(body["bottom"]))*0.36,float(body["right"])-float(body["left"]),0.18,0.12,stone)

func _build_rose(owner_root: Node3D, frame: Dictionary) -> void:
    var stone := _white_stone("Urban 31128: three superposed orders; broad stone presentation only"); var blue := _blue_stone_material(); var gold := _gold_material()
    _add_regular_windows(owner_root,frame,3,3,false); _add_pilaster_rhythm(owner_root,frame,3,stone); _add_register_bands(owner_root,frame,3,stone)
    var body := _body_bounds(frame)
    _add_box(owner_root,frame,"DoricBlueStoneBase",(float(body["left"])+float(body["right"]))*0.5,float(body["bottom"])-0.13,float(body["right"])-float(body["left"]),0.26,0.09,blue)
    var span := float(body["right"])-float(body["left"])
    for i: int in range(3): _add_box(owner_root,frame,"GildedLambrequinCue_%d"%i,float(body["left"])+span*(float(i)+0.5)/3.0,float(body["top"])-float(frame["height"])*0.035,span*0.11,maxf(0.14,float(frame["height"])*0.012),0.07,gold)

func _build_brasseurs(owner_root: Node3D, frame: Dictionary) -> void:
    var stone := _white_stone("Urban 31127: Euville/Gobertange"); var blue := _blue_stone_material()
    _add_regular_windows(owner_root,frame,3,3,true); _add_register_bands(owner_root,frame,3,stone)
    var body := _body_bounds(frame); var left := float(body["left"]); var right := float(body["right"]); var bottom := float(body["bottom"]); var top := float(body["top"]); var bay_w := (right-left)/3.0
    for i: int in range(4): _add_box(owner_root,frame,"ColossalOrder_%d"%i,left+bay_w*float(i),bottom+(top-bottom)*0.57,maxf(0.18,float(frame["width"])*0.025),(top-bottom)*0.86,0.11,stone)
    _add_box(owner_root,frame,"PowerfulEntablature",(left+right)*0.5,bottom+(top-bottom)*0.34,right-left,0.22,0.10,stone)
    var center := (left+right)*0.5
    _add_box(owner_root,frame,"AxialBayLeft",center-bay_w*0.42,bottom+(top-bottom)*0.52,0.18,(top-bottom)*0.90,0.12,stone)
    _add_box(owner_root,frame,"AxialBayRight",center+bay_w*0.42,bottom+(top-bottom)*0.52,0.18,(top-bottom)*0.90,0.12,stone)
    _add_box(owner_root,frame,"BlueStonePlinth",center,bottom-0.14,right-left,0.28,0.10,blue)

func _build_mont_thabor(owner_root: Node3D, frame: Dictionary) -> void:
    var plaster := _standard_material(Color(0.79,0.75,0.66,1.0),0.91,"Urban 30907: cemented facade; exact RGB authored"); var blue := _blue_stone_material()
    _add_regular_windows(owner_root,frame,3,3,true); _add_pilaster_rhythm(owner_root,frame,3,plaster,0.018); _add_register_bands(owner_root,frame,3,plaster)
    var body := _body_bounds(frame)
    _add_box(owner_root,frame,"BlueStoneGroundFloor",(float(body["left"])+float(body["right"]))*0.5,float(body["bottom"])-0.18,float(body["right"])-float(body["left"]),0.36,0.09,blue)

func _weighted_lower_bays(left: float, right: float) -> Array[Dictionary]:
    var weights: Array[float] = []
    for i: int in range(9): weights.append(1.35 if i==4 else 1.0)
    var total := 0.0
    for weight: float in weights: total += weight
    var unit := (right-left)/total; var cursor := left; var out: Array[Dictionary] = []
    for i: int in range(9):
        var width := unit*weights[i]
        out.append({"center":cursor+width*0.5,"width":width,"axial":i==4}); cursor += width
    return out

func _build_maison_du_roi(owner_root: Node3D, frame: Dictionary) -> void:
    var stone := _white_stone("Urban 31143: Gobertange stone component"); var blue := _blue_stone_material(); var dark := _dark_window_material()
    var left := float(frame["min_u"])+float(frame["width"])*0.055; var right := float(frame["max_u"])-float(frame["width"])*0.055; var base_y := float(frame["min_y"])+maxf(0.65,float(frame["height"])*0.035); var usable_top := minf(float(frame["max_y"])-0.8,base_y+float(frame["height"])*0.78); var register_h := (usable_top-base_y)/3.0; var lower := _weighted_lower_bays(left,right)
    for register: int in range(2):
        var bottom := base_y+float(register)*register_h+register_h*0.13; var panel_h := register_h*0.68
        for i: int in range(lower.size()):
            var bay: Dictionary = lower[i]; var center := float(bay["center"]); var bay_w := float(bay["width"]); var lancets := 4 if register==0 else 2; var inner_w := bay_w*(0.72 if bool(bay["axial"]) else 0.66); var gap := inner_w*0.055; var lancet_w := (inner_w-gap*float(lancets-1))/float(lancets); var start := center-inner_w*0.5+lancet_w*0.5
            for l: int in range(lancets): _add_pointed_panel(owner_root,frame,"Lancet_%d_%d_%d"%[register,i,l],start+float(l)*(lancet_w+gap),bottom,lancet_w,panel_h,dark)
        var rail_y := base_y+float(register+1)*register_h-register_h*0.03
        _add_box(owner_root,frame,"GalleryRail_%d"%register,(left+right)*0.5,rail_y,right-left,0.22,0.16,stone)
        for bay: Dictionary in lower: _add_box(owner_root,frame,"GalleryPier_%d_%d"%[register,feature_count],float(bay["center"]),rail_y-register_h*0.18,0.20,register_h*0.34,0.16,stone)
    var upper_bottom := base_y+register_h*2.0+register_h*0.11; var upper_panel_h := register_h*0.70; var upper_unit := (right-left)/17.0
    for i: int in range(17):
        var center := left+upper_unit*(float(i)+0.5); var inner := upper_unit*(0.78 if i==8 else 0.64); var gap := inner*0.08; var lancet_w := (inner-gap)*0.5
        _add_pointed_panel(owner_root,frame,"UpperLancet_%d_a"%i,center-(lancet_w+gap)*0.5,upper_bottom,lancet_w,upper_panel_h,dark)
        _add_pointed_panel(owner_root,frame,"UpperLancet_%d_b"%i,center+(lancet_w+gap)*0.5,upper_bottom,lancet_w,upper_panel_h,dark)
    _add_box(owner_root,frame,"BlueStonePlinth",(left+right)*0.5,base_y-0.16,right-left,0.32,0.18,blue)

func set_presentation_visible(enabled: bool) -> void:
    presentation_visible = enabled
    if _detail_root != null and is_instance_valid(_detail_root): _detail_root.visible = enabled
    for owner_id: String in styled_owner_ids:
        var wall: MeshInstance3D = _wall_meshes.get(owner_id)
        if wall != null and is_instance_valid(wall):
            wall.material_override = _styled_wall_materials.get(owner_id) if enabled else _original_wall_materials.get(owner_id)
            wall.set_meta("presentation_identity",_owner_name(owner_id) if enabled else "neutral_unregistered")
        if _roof_meshes.has(owner_id):
            var roof: MeshInstance3D = _roof_meshes.get(owner_id)
            if roof != null and is_instance_valid(roof): roof.material_override = _styled_roof_materials.get(owner_id) if enabled else _original_roof_materials.get(owner_id)

func _owner_name(owner_id: String) -> String:
    var contract := _read_json(CONTRACT_PATH); var owners: Dictionary = contract.get("owners",{}); var owner: Dictionary = owners.get(owner_id,{})
    return str(owner.get("official_name",""))

func get_styled_owner_ids() -> Array[String]: return styled_owner_ids.duplicate()
func get_hold_owner_ids() -> Array[String]: return hold_owner_ids.duplicate()
func get_owner_feature_counts() -> Dictionary: return _owner_feature_counts.duplicate(true)

func collision_object_count() -> int:
    if _detail_root == null: return 0
    var count := 0; var stack: Array[Node] = [_detail_root]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is CollisionObject3D: count += 1
        for child: Node in node.get_children(): stack.append(child)
    return count
