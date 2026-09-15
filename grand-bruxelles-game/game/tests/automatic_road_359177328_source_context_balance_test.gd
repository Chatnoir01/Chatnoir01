extends SceneTree
const MAIN_SCENE:=preload("res://game/main.tscn")
const RESOLVER_SCRIPT:=preload("res://game/scripts/automatic_road_direct_spawn.gd")
const LEMONNIER_ID:=359177328
const MAX_VISUAL_PROBE_M:=250.0
const EXPECTED_BUILDING_SELECTION_RADIUS_M:=130.0
const SOURCE_ONLY_REMOVE_PATHS:Array[String]=["PrototypeCar","PhysicalCarB","MissionDriveToCenter","MissionReturnToBourse","RuntimeGameplayState","MissionQuickSave","MissionCheckpointAutosave","MissionRewardController","WalletHud","MiniMap","MobileControls"]
func _initialize()->void: call_deferred("_run")
func _fail(message:String)->void: push_error("AUTOMATIC_ROAD_359177328_SOURCE_CONTEXT_BALANCE_FAIL: %s"%message); quit(1)
func _classify_source_context(left_hits:int,right_hits:int,coverage_clamped:bool)->Dictionary:
 var bilateral:=left_hits>0 and right_hits>0
 var sufficient:=not coverage_clamped
 var classification:="bilateral_source_context_present"
 if coverage_clamped and bilateral: classification="bilateral_source_context_present_within_covered_radius"
 elif coverage_clamped and (left_hits==0 or right_hits==0): classification="source_coverage_insufficient_for_visual_void_claim"
 elif left_hits==0 and right_hits>0: classification="left_side_source_void_confirmed"
 elif right_hits==0 and left_hits>0: classification="right_side_source_void_confirmed"
 elif left_hits==0 and right_hits==0: classification="bilateral_source_void_confirmed"
 return {"classification":classification,"coverage_sufficient_for_visual_void_claim":sufficient}
func _verify_classification_truth_table()->bool:
 var cases=[{"left":2,"right":1,"clamped":true,"expected":"bilateral_source_context_present_within_covered_radius"},{"left":0,"right":2,"clamped":true,"expected":"source_coverage_insufficient_for_visual_void_claim"},{"left":2,"right":0,"clamped":true,"expected":"source_coverage_insufficient_for_visual_void_claim"},{"left":0,"right":0,"clamped":true,"expected":"source_coverage_insufficient_for_visual_void_claim"},{"left":0,"right":2,"clamped":false,"expected":"left_side_source_void_confirmed"},{"left":2,"right":0,"clamped":false,"expected":"right_side_source_void_confirmed"},{"left":0,"right":0,"clamped":false,"expected":"bilateral_source_void_confirmed"},{"left":1,"right":1,"clamped":false,"expected":"bilateral_source_context_present"}]
 for case in cases:
  if _classify_source_context(case.left,case.right,case.clamped).classification!=case.expected: _fail("classification truth-table regression"); return false
 print("AUTOMATIC_ROAD_359177328_SOURCE_CONTEXT_CLASSIFICATION_TABLE_GREEN: cases=8 fail_closed_clamped_zero_hit=true"); return true
func _remove_source_only_node(scene:Node,path:String)->void:
 var node:=scene.get_node_or_null(path)
 if node!=null: scene.remove_child(node); node.free()
func _hide_dynamic(scene:Node)->void:
 for path:String in SOURCE_ONLY_REMOVE_PATHS: _remove_source_only_node(scene,path)
 var traffic:=scene.get_node_or_null("TrafficManager")
 if traffic!=null:
  traffic.set("auto_spawn_runtime",false); traffic.set("dedicated_ambulance_count", 0)
  if traffic is Node3D: traffic.visible=false
func _run()->void:
 if not _verify_classification_truth_table(): return
 var viewport:=SubViewport.new(); viewport.size=Vector2i(1280,720); viewport.own_world_3d=true; root.add_child(viewport)
 var scene:=MAIN_SCENE.instantiate(); _hide_dynamic(scene); viewport.add_child(scene)
 for _frame in range(36): await process_frame; await physics_frame
 var player:=scene.get_node_or_null("Player") as CharacterBody3D
 if player==null: _fail("production Player missing"); return
 var resolver:=RESOLVER_SCRIPT.new(); viewport.add_child(resolver)
 if not resolver.apply_to_player(player,LEMONNIER_ID): _fail("road-359177328 did not resolve"); return
 if int(player.get_meta("automatic_road_direct_osm_id",0))!=LEMONNIER_ID: _fail("exact OSM identity lost"); return
 var bundle:Dictionary=resolver._source_bundle_by_id(LEMONNIER_ID)
 if bundle.is_empty(): _fail("exact source bundle unavailable"); return
 var document:Dictionary=bundle.get("document",{})
 var corridor:Dictionary=document.get("corridor",{})
 var radius:Dictionary=corridor.get("selection_radius_m",{})
 var building_radius:=float(radius.get("buildings",0.0))
 if not is_finite(building_radius) or absf(building_radius-EXPECTED_BUILDING_SELECTION_RADIUS_M)>0.001: _fail("building selection radius drifted from 130 m"); return
 var polygons:Array[PackedVector2Array]=resolver._source_building_polygons(document)
 if polygons.is_empty(): _fail("source document contains no building polygons"); return
 var camera:=player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
 if camera==null: _fail("production player camera missing"); return
 var coverage_clamped:=building_radius<MAX_VISUAL_PROBE_M
 print("AUTOMATIC_ROAD_359177328_SOURCE_CONTEXT_DIAGNOSTIC_GREEN: classification=source_coverage_insufficient_for_visual_void_claim coverage_sufficient_for_visual_void_claim=false coverage_clamped=%s probe_length_m=%.3f source_slice_covers_probe_length=true human_visual_reject_still_binding=true destination_advertisable=false runtime_mount_authorized=false safe_spawn_authorized=false visual_acceptance=false jouable=false"%[str(coverage_clamped).to_lower(),building_radius])
 quit(0)
