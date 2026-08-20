extends SceneTree

const BACKEND_SCRIPT := preload("res://game/scripts/brussels_c01_external_cell_backend.gd")
const CELL_ID := "E141000_N167500"
const CELL_PATH := "cells/E141000_N167500/world.ndjson"
const PUBLIC_BASE := "https://chatnoir01.github.io/Chatnoir01/region-lod2/C01"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("BRUSSELS_C01_EXTERNAL_BACKEND_FAIL: %s" % message)
    quit(1)


func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true


func _run() -> void:
    var backend := BACKEND_SCRIPT.new() as BrusselsC01ExternalCellBackend
    root.add_child(backend)
    await process_frame

    if not _expect(not backend.configure_public_base_url("http://insecure.invalid/C01"), "HTTP base URL must be rejected"):
        return
    if not _expect(backend.configure_public_base_url(PUBLIC_BASE + "/"), "canonical HTTPS base URL should normalize"):
        return
    if not _expect(backend.get_public_base_url() == PUBLIC_BASE, "public base URL normalization drift"):
        return

    var digest := "0".repeat(64)
    if not _expect(not backend.register_external_cell(CELL_ID, {"relative_path": "../escape.ndjson", "sha256": digest}), "path traversal must be rejected"):
        return
    if not _expect(not backend.register_external_cell(CELL_ID, {"relative_path": CELL_PATH, "sha256": "bad"}), "invalid digest must be rejected"):
        return
    if not _expect(backend.register_external_cell(CELL_ID, {"relative_path": CELL_PATH, "sha256": digest, "bytes": 123}), "valid external binding should register"):
        return
    if not _expect(backend.build_cell_url(CELL_ID) == PUBLIC_BASE + "/" + CELL_PATH, "cell URL mapping drift"):
        return

    if not _expect(backend.sha256_hex("abc".to_utf8_buffer()) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 helper drift"):
        return

    var simple_face := JSON.stringify({
        "building_id": "test-simple",
        "solid_id": "solid-simple",
        "face_id": "face-simple",
        "face_type": "ROOFSURFACE",
        "parts": [{
            "part_type": 4,
            "vertices": [
                [0.0, 10.0, 0.0],
                [4.0, 10.0, 0.0],
                [4.0, 10.0, 4.0],
                [0.0, 10.0, 4.0],
                [0.0, 10.0, 0.0],
            ],
        }],
    })
    var holed_face := JSON.stringify({
        "building_id": "test-hole",
        "solid_id": "solid-hole",
        "face_id": "face-hole",
        "face_type": "ROOFSURFACE",
        "parts": [
            {
                "part_type": 2,
                "vertices": [
                    [10.0, 10.0, 0.0],
                    [16.0, 10.0, 0.0],
                    [16.0, 10.0, 6.0],
                    [10.0, 10.0, 6.0],
                    [10.0, 10.0, 0.0],
                ],
            },
            {
                "part_type": 3,
                "vertices": [
                    [12.0, 10.0, 2.0],
                    [14.0, 10.0, 2.0],
                    [14.0, 10.0, 4.0],
                    [12.0, 10.0, 4.0],
                    [12.0, 10.0, 2.0],
                ],
            },
        ],
    })
    var parsed := backend.parse_ndjson_text(simple_face + "\n" + holed_face + "\n")
    if not _expect(bool(parsed.get("ok", false)), "synthetic NDJSON should parse"):
        return
    if not _expect(int(parsed.get("face_count", -1)) == 2, "face accounting drift"):
        return
    if not _expect(int(parsed.get("part_count", -1)) == 3, "part accounting drift"):
        return
    if not _expect(int(parsed.get("skipped_hole_faces", -1)) == 1, "inner-ring face must fail closed instead of being filled"):
        return
    var triangles: PackedVector3Array = parsed.get("triangle_vertices", PackedVector3Array())
    if not _expect(triangles.size() == 6, "simple quad should triangulate to two triangles"):
        return

    var instance := backend.build_mesh_instance(parsed, CELL_ID)
    if not _expect(instance != null and instance.mesh != null, "parsed C01 geometry should build a render mesh"):
        return
    if not _expect(bool(instance.get_meta("c01_external_candidate", false)), "candidate metadata missing"):
        return
    if not _expect(not bool(instance.get_meta("collision_authorized", true)), "candidate must not authorize collision"):
        return
    var aabb := instance.mesh.get_aabb()
    if not _expect(aabb.size.x > 0.0 and aabb.size.z > 0.0, "render mesh AABB is degenerate"):
        return
    instance.queue_free()

    var invalid_part := backend.parse_ndjson_text(JSON.stringify({
        "building_id": "bad",
        "solid_id": "bad",
        "face_id": "bad",
        "face_type": "OTHER",
        "parts": [{"part_type": 99, "vertices": [[0,0,0],[1,0,0],[0,0,1],[0,0,0]]}],
    }))
    if not _expect(not bool(invalid_part.get("ok", true)), "unknown part types must be rejected"):
        return

    var metrics := backend.get_metrics()
    if not _expect(bool(metrics.get("candidate_only", false)), "backend must remain candidate-only"):
        return
    for key in ["runtime_mount_authorized", "collision_authorized", "jouable_promotion_authorized"]:
        if not _expect(not bool(metrics.get(key, true)), "%s must remain false" % key):
            return

    print("BRUSSELS_C01_EXTERNAL_BACKEND_OK: https mapping, sha256, NDJSON triangulation, inner-ring fail-closed and authorization rails passed")
    backend.queue_free()
    quit(0)
