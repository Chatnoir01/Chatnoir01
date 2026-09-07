import hashlib
import importlib.util
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools/city_machine/build_road_destination_index.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("build_road_destination_index", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def _semantic_sha256(value):
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _raw_fixture():
    return {"osm3s": {"timestamp_osm_base": "2026-08-30T23:58:06Z"}, "elements": []}


def _artifact(tmp_path: Path, duplicate=False, receipt_semantic_sha256=None, receipt_raw_sha256=None, game_bounds=None):
    municipality = {"niscode": "21002", "id": "auderghem", "name": "Auderghem / Oudergem", "osm_relation_id": 58263}
    source = {"provider": "OpenStreetMap contributors via Overpass API", "license": "ODbL-1.0", "endpoint": "https://overpass-api.de/api/interpreter", "query_scope": "administrative_relation", "highway_classes": ["residential"]}
    downstream = {"source_registration_authorized": False, "road_cell_mapping_authorized": False, "render_authorized": False, "collision_authorized": False, "runtime_mount_authorized": False, "safe_spawn_authorized": False, "jouable_authorized": False}
    manifest = {"schema": "grand-bruxelles-municipality-road-source-acquisition-v1", "municipality": municipality, "source": source, "game_frame": {"origin_lat": 50.8419, "origin_lon": 4.348, "axes": "X=east, Y=up, Z=south", "units": "metres"}, "authorization": {"source_acquisition_authorized": True, **downstream}}
    raw = _raw_fixture()
    raw_semantic_sha = _semantic_sha256(raw)
    game = {"format": "grand-bruxelles-osm-v1", "municipality": municipality, "license": "ODbL-1.0", "origin": {"lat": 50.8419, "lon": 4.348}, "bounds_m": game_bounds if game_bounds is not None else [0.0, 0.0, 4.0, 4.0], "authorization": downstream, "roads": [{"osm_id": 20, "class": "residential", "name": "B", "points": [[2.0, 2.0], [4.0, 4.0]]}, {"osm_id": 20 if duplicate else 10, "class": "residential", "name": "A", "points": [[0.0, 0.0], [1.0, 1.0]]}]}
    semantic_sha = _semantic_sha256(game)
    receipt = {"schema": "grand-bruxelles-municipality-road-source-receipt-v1", "municipality": municipality, "source": source, "authorization": downstream, "road_count": 2, "point_count": 4, "osm_base_timestamp": "2026-08-30T23:58:06Z", "raw_snapshot_sha256": receipt_raw_sha256 or raw_semantic_sha, "normalized_game_source_sha256": receipt_semantic_sha256 or semantic_sha}
    tmp_path.mkdir(parents=True, exist_ok=True)
    path = tmp_path / "locked.zip"
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr("auderghem.manifest.json", json.dumps(manifest))
        zf.writestr("auderghem_road_source.raw.json", json.dumps(raw))
        zf.writestr("auderghem_road_source.game.json", json.dumps(game))
        zf.writestr("auderghem_road_source.receipt.json", json.dumps(receipt))
    return path, hashlib.sha256(path.read_bytes()).hexdigest(), semantic_sha


def _evidence_lock(tmp_path: Path, archive_sha256: str, semantic_sha256: str, **overrides):
    downstream = {"source_registration_authorized": False, "road_cell_mapping_authorized": False, "render_authorized": False, "collision_authorized": False, "runtime_mount_authorized": False, "safe_spawn_authorized": False, "jouable_authorized": False}
    locked = {
        "niscode": "21002",
        "id": "auderghem",
        "name": "Auderghem / Oudergem",
        "osm_relation_id": 58263,
        "status": "ACQUIRED_ARTIFACT_LOCKED",
        "artifact": {"id": 9741187457, "name": "road-source-21002-auderghem", "archive_sha256": archive_sha256},
        "osm_base_timestamp": "2026-08-30T23:58:06Z",
        "road_count": 2,
        "point_count": 4,
        "bounds_m": [0.0, 0.0, 4.0, 4.0],
        "raw_snapshot_semantic_sha256": _semantic_sha256(_raw_fixture()),
        "normalized_game_source_semantic_sha256": semantic_sha256,
        "authorization": downstream,
    }
    for key, value in overrides.items():
        locked[key] = value
    evidence = {"format": "grand-bruxelles-missing-road-source-acquisition-evidence-v1", "successful_acquisitions": [locked], "unresolved_acquisitions": []}
    tmp_path.mkdir(parents=True, exist_ok=True)
    path = tmp_path / "evidence.lock.json"
    path.write_text(json.dumps(evidence), encoding="utf-8")
    return path


def test_build_index_is_deterministic_and_fail_closed(tmp_path):
    module = _load_module()
    artifact, sha, semantic_sha = _artifact(tmp_path)
    first = module.build_index(artifact, sha, 9741187457, "road-source-21002-auderghem")
    second = module.build_index(artifact, sha, 9741187457, "road-source-21002-auderghem")
    assert first == second
    assert first["source"]["raw_snapshot_sha256"] == _semantic_sha256(_raw_fixture())
    assert first["source"]["normalized_game_source_sha256"] == semantic_sha
    assert first["source"]["bounds_m"] == [0.0, 0.0, 4.0, 4.0]
    assert first["source"]["members"]["raw_snapshot"] == "auderghem_road_source.raw.json"
    assert [row["road_id"] for row in first["roads"]] == ["road-10", "road-20"]
    assert first["accounting"]["road_identity_materialized"] == 2
    assert first["accounting"]["cell_assignment_materialized"] == 0
    for row in first["roads"]:
        assert row["state"] == "DISCOVERED"
        assert row["spatial_cell"] is None
        assert row["registration_authorized"] is False
        assert row["render_authorized"] is False
        assert row["collision_authorized"] is False
        assert row["runtime_ready"] is False
        assert row["jouable"] is False


def test_build_index_rejects_hash_and_duplicate_road_identity(tmp_path):
    module = _load_module()
    artifact, sha, _ = _artifact(tmp_path)
    try:
        module.build_index(artifact, "0" * 64, 9741187457, "road-source-21002-auderghem")
    except ValueError as exc:
        assert "archive sha256 mismatch" in str(exc)
    else:
        raise AssertionError("bad archive hash must fail closed")

    duplicate, duplicate_sha, _ = _artifact(tmp_path / "duplicate", duplicate=True)
    try:
        module.build_index(duplicate, duplicate_sha, 9741187457, "road-source-21002-auderghem")
    except ValueError as exc:
        assert "duplicate OSM road id" in str(exc)
    else:
        raise AssertionError("duplicate road id must fail closed")


def test_build_index_rejects_stale_receipt_raw_snapshot_hash(tmp_path):
    module = _load_module()
    artifact, sha, _ = _artifact(tmp_path, receipt_raw_sha256="0" * 64)
    try:
        module.build_index(artifact, sha, 9741187457, "road-source-21002-auderghem")
    except ValueError as exc:
        assert "raw snapshot semantic sha256 mismatch" in str(exc)
    else:
        raise AssertionError("raw snapshot payload must be bound to the receipt semantic hash")


def test_build_index_rejects_stale_receipt_semantic_hash(tmp_path):
    module = _load_module()
    artifact, sha, _ = _artifact(tmp_path, receipt_semantic_sha256="0" * 64)
    try:
        module.build_index(artifact, sha, 9741187457, "road-source-21002-auderghem")
    except ValueError as exc:
        assert "normalized game semantic sha256 mismatch" in str(exc)
    else:
        raise AssertionError("game payload must be bound to the receipt semantic hash")


def test_build_index_rejects_payload_bounds_drift_from_materialized_geometry(tmp_path):
    module = _load_module()
    artifact, sha, _ = _artifact(tmp_path, game_bounds=[0.0, 0.0, 5.0, 5.0])
    try:
        module.build_index(artifact, sha, 9741187457, "road-source-21002-auderghem")
    except ValueError as exc:
        assert "bounds_m does not match materialized road geometry" in str(exc)
    else:
        raise AssertionError("payload bounds must be derived from materialized road geometry")


def test_evidence_lock_is_authoritative_for_artifact_selection(tmp_path):
    module = _load_module()
    artifact, sha, semantic_sha = _artifact(tmp_path)
    evidence = _evidence_lock(tmp_path, sha, semantic_sha)
    index = module.build_index_from_evidence_lock(artifact, evidence, "21002")
    assert index["source"]["artifact_id"] == 9741187457
    assert index["source"]["artifact_name"] == "road-source-21002-auderghem"
    assert index["source"]["archive_sha256"] == sha
    assert index["source"]["raw_snapshot_sha256"] == _semantic_sha256(_raw_fixture())
    assert index["source"]["normalized_game_source_sha256"] == semantic_sha
    assert index["source"]["bounds_m"] == [0.0, 0.0, 4.0, 4.0]
    assert index["municipality"]["osm_relation_id"] == 58263


def test_evidence_lock_rejects_raw_snapshot_hash_drift(tmp_path):
    module = _load_module()
    artifact, sha, semantic_sha = _artifact(tmp_path)
    evidence = _evidence_lock(tmp_path, sha, semantic_sha, raw_snapshot_semantic_sha256="0" * 64)
    try:
        module.build_index_from_evidence_lock(artifact, evidence, "21002")
    except ValueError as exc:
        assert "raw snapshot semantic sha256 does not match evidence lock" in str(exc)
    else:
        raise AssertionError("raw snapshot semantic digest must match immutable evidence")


def test_evidence_lock_rejects_semantic_hash_drift(tmp_path):
    module = _load_module()
    artifact, sha, _ = _artifact(tmp_path)
    evidence = _evidence_lock(tmp_path, sha, "0" * 64)
    try:
        module.build_index_from_evidence_lock(artifact, evidence, "21002")
    except ValueError as exc:
        assert "semantic sha256 does not match evidence lock" in str(exc)
    else:
        raise AssertionError("artifact semantic digest must match immutable evidence")


def test_evidence_lock_rejects_bounds_drift(tmp_path):
    module = _load_module()
    artifact, sha, semantic_sha = _artifact(tmp_path)
    evidence = _evidence_lock(tmp_path, sha, semantic_sha, bounds_m=[0.0, 0.0, 5.0, 5.0])
    try:
        module.build_index_from_evidence_lock(artifact, evidence, "21002")
    except ValueError as exc:
        assert "bounds_m does not match evidence lock" in str(exc)
    else:
        raise AssertionError("artifact geometry bounds must match immutable evidence")


def test_evidence_lock_rejects_unlocked_or_self_declared_provenance(tmp_path):
    module = _load_module()
    artifact, sha, semantic_sha = _artifact(tmp_path)
    wrong_hash = _evidence_lock(tmp_path / "wrong-hash", "0" * 64, semantic_sha)
    try:
        module.build_index_from_evidence_lock(artifact, wrong_hash, "21002")
    except ValueError as exc:
        assert "archive sha256 mismatch" in str(exc)
    else:
        raise AssertionError("artifact must be bound to the immutable evidence hash")

    wrong_relation = _evidence_lock(tmp_path / "wrong-relation", sha, semantic_sha, osm_relation_id=999999)
    try:
        module.build_index_from_evidence_lock(artifact, wrong_relation, "21002")
    except ValueError as exc:
        assert "OSM relation does not match evidence lock" in str(exc)
    else:
        raise AssertionError("artifact municipality identity must match the evidence lock")

    unresolved = tmp_path / "unresolved.lock.json"
    unresolved.write_text(json.dumps({"format": "grand-bruxelles-missing-road-source-acquisition-evidence-v1", "successful_acquisitions": [], "unresolved_acquisitions": [{"niscode": "21002", "status": "REMOTE_ACQUISITION_UNRESOLVED"}]}), encoding="utf-8")
    try:
        module.build_index_from_evidence_lock(artifact, unresolved, "21002")
    except ValueError as exc:
        assert "not exactly one locked acquisition" in str(exc)
    else:
        raise AssertionError("unresolved acquisition must never materialize a destination index")
