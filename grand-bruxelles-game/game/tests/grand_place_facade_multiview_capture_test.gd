extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const GATE_PATH := "res://data/qa/grand_place_facade_visual_gate.json"
const SOURCE_DIR := "res://data/urbis/grand_place_lod2"
const CONTOUR_NAME := "GrandPlaceCompleteContourRuntime"
const FACADE_NAME := "GrandPlaceFacadePresentationRuntime"
const REFINEMENT_V4_NAME := "GrandPlaceFacadePresentationRefinementV4"
const CAMERA_EPSILON := 0.001

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_FACADE_CAPTURE_FAIL: " + message)
    quit(1)

func _json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _v3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]),float(raw[1]),float(raw[2]))

func _point(raw: Variant) -> Vector3:
    return _v3(raw)

func _walk(node: Node, out: Array[Node]) -> void:
    out.append(node)
    for child: Node in node.get_children():
        _walk(child,out)

func _freeze_world(main: Node) -> void:
    var nodes: Array[Node] = []
    _walk(root,nodes)
    for node: Node in nodes:
        if node is CanvasLayer:
            (node as CanvasLayer).visible = false
        elif node is CanvasItem:
            (node as CanvasItem).visible = false
        if node.is_in_group("vehicle") or node.is_in_group("npc") or node.is_in_group("ambient_pedestrian") or node.is_in_group("ambient_traffic") or node.is_in_group("ambient") or node.is_in_group("traffic"):
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false
    for path: String in ["Player","PrototypeCar","PhysicalCar","PhysicalCarB","TrafficManager","NpcPopulationDirector","NpcRuntimeIntegration","MidiUrbanLife"]:
        var target := main.get_node_or_null(path)
        if target != null:
            target.process_mode = Node.PROCESS_MODE_DISABLED
            if target is Node3D:
                (target as Node3D).visible = false
    for autoload_name: String in ["LivingCityShowcaseRuntime","VisibleCityRuntime","MidiAmbientNpcVisualRuntime","MidiProfiledNpcGaitRuntime","GtaScaleCameraRuntime"]:
        var runtime := root.get_node_or_null(autoload_name)
        if runtime != null:
            runtime.process_mode = Node.PROCESS_MODE_DISABLED
            if runtime is Node3D:
                (runtime as Node3D).visible = false

func _source_cluster_target(raw_owner_ids: Variant) -> Vector3:
    if typeof(raw_owner_ids) != TYPE_ARRAY or raw_owner_ids.is_empty():
        return Vector3.INF
    var initialized := false
    var lo := Vector3.ZERO
    var hi := Vector3.ZERO
    for raw_owner: Variant in raw_owner_ids:
        var owner_id := str(raw_owner)
        var data := _json(SOURCE_DIR.path_join("%s.game.json" % owner_id))
        if data.is_empty():
            return Vector3.INF
        for raw_face: Variant in data.get("faces",[]):
            if typeof(raw_face) != TYPE_DICTIONARY:
                continue
            for raw_tri: Variant in raw_face.get("triangles",[]):
                if typeof(raw_tri) != TYPE_ARRAY:
                    continue
                for raw_p: Variant in raw_tri:
                    var p := _point(raw_p)
                    if not p.is_finite():
                        continue
                    if not initialized:
                        lo = p; hi = p; initialized = true
                    else:
                        lo.x = minf(lo.x,p.x); lo.y = minf(lo.y,p.y); lo.z = minf(lo.z,p.z)
                        hi.x = maxf(hi.x,p.x); hi.y = maxf(hi.y,p.y); hi.z = maxf(hi.z,p.z)
    if not initialized:
        return Vector3.INF
    return Vector3((lo.x+hi.x)*0.5, lo.y+(hi.y-lo.y)*0.46, (lo.z+hi.z)*0.5)

func _view_target(view: Dictionary) -> Vector3:
    var method := str(view.get("target_method",""))
    if method == "fixed_existing_witness":
        return _v3(view.get("target",[]))
    if method == "source_bbox_cluster_center":
        return _source_cluster_target(view.get("target_owner_ids",[]))
    return Vector3.INF

func _frozen_camera_is_authoritative(camera: Camera3D, expected_position: Vector3, expected_fov: float) -> bool:
    if not is_instance_valid(camera):
        return false
    if root.get_viewport().get_camera_3d() != camera or not camera.current:
        return false
    if camera.global_position.distance_to(expected_position) > CAMERA_EPSILON:
        return false
    return absf(camera.fov - expected_fov) <= CAMERA_EPSILON

func _capture(path: String, main: Node, camera: Camera3D, expected_position: Vector3, expected_fov: float) -> bool:
    for _frame: int in range(10):
        _freeze_world(main)
        if not _frozen_camera_is_authoritative(camera,expected_position,expected_fov):
            return false
        RenderingServer.force_draw()
        await process_frame
    if not _frozen_camera_is_authoritative(camera,expected_position,expected_fov):
        return false
    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return false
    if image.get_width() != 1280 or image.get_height() != 720:
        image.resize(1280,720,Image.INTERPOLATE_LANCZOS)
    return image.save_png(path) == OK

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 2:
        _fail("usage: <output_dir> <before|after>")
        return
    var output_dir := str(args[0])
    var state := str(args[1])
    if state not in ["before","after"]:
        _fail("invalid state")
        return
    DirAccess.make_dir_recursive_absolute(output_dir)
    var gate := _json(GATE_PATH)
    if str(gate.get("schema","")) != "grand-bruxelles-grand-place-facade-visual-gate-v2":
        _fail("visual gate schema drifted")
        return
    var camera_position := _v3(gate.get("camera_position",[]))
    var fov := float(gate.get("fov_deg",0.0))
    if not camera_position.is_finite() or absf(fov-62.0)>0.001:
        _fail("camera position/FOV drifted")
        return
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var contour := root.get_node_or_null(CONTOUR_NAME)
    var facade := root.get_node_or_null(FACADE_NAME)
    var refinement_v4 := root.get_node_or_null(REFINEMENT_V4_NAME)
    for _frame: int in range(1200):
        if contour != null and bool(contour.get("geometry_loaded")):
            if state == "before" or (facade != null and bool(facade.get("built")) and refinement_v4 != null and bool(refinement_v4.get("built"))):
                break
        await process_frame
        contour = root.get_node_or_null(CONTOUR_NAME)
        facade = root.get_node_or_null(FACADE_NAME)
        refinement_v4 = root.get_node_or_null(REFINEMENT_V4_NAME)
    if contour == null or not bool(contour.get("geometry_loaded")):
        _fail("complete contour not ready")
        return
    if state == "after" and (facade == null or not bool(facade.get("built"))):
        _fail("facade runtime not ready on AFTER")
        return
    if state == "after" and (refinement_v4 == null or bool(refinement_v4.get("failed")) or not bool(refinement_v4.get("built"))):
        _fail("V4 refinement runtime not ready on AFTER")
        return
    if facade != null and bool(facade.get("built")):
        facade.call("set_presentation_visible",state == "after")
    _freeze_world(main)
    var current_camera := root.get_viewport().get_camera_3d()
    if current_camera != null:
        current_camera.current = false
    var camera := Camera3D.new()
    camera.name = "GrandPlaceFacadeFrozenPlayerWitness"
    camera.position = camera_position
    camera.fov = fov
    main.add_child(camera)
    camera.current = true
    var views: Array = gate.get("views",[])
    if views.size() != int(gate.get("required_views",-1)):
        _fail("required view count drifted")
        return
    for raw_view: Variant in views:
        if typeof(raw_view) != TYPE_DICTIONARY:
            _fail("malformed view")
            return
        var view: Dictionary = raw_view
        var target := _view_target(view)
        if not target.is_finite():
            _fail("view target unresolved: %s" % str(view.get("id","")))
            return
        camera.look_at(target,Vector3.UP)
        for _frame: int in range(8):
            _freeze_world(main)
            await process_frame
        if not _frozen_camera_is_authoritative(camera,camera_position,fov):
            _fail("frozen witness camera lost authority: %s" % str(view.get("id","")))
            return
        var path := output_dir.path_join("%s_%s.png" % [str(view.get("id","view")),state])
        if not await _capture(path,main,camera,camera_position,fov):
            _fail("capture failed or frozen camera drifted: %s" % path)
            return
        print("GRAND_PLACE_FACADE_CAPTURE_VIEW: id=%s state=%s target=[%.3f,%.3f,%.3f]" % [str(view.get("id","")),state,target.x,target.y,target.z])
    print("GRAND_PLACE_FACADE_CAPTURE_OK: state=%s views=%d camera_fixed=true camera_authority_frozen=true gta_scale_camera_frozen=true fov_fixed=true v4_required_on_after=true" % [state,views.size()])
    quit(0)
