import copy
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools/qa/build_corrected_frame_destination_production_pair.py"
CONTRACT_PATH = ROOT / "data/qa/corrected_frame_destination_production_apply.contract.json"
CROSSWALK_PATH = ROOT / "data/provenance/brussels_road_registered_cell_crosswalk.json"
spec = importlib.util.spec_from_file_location("builder", MODULE_PATH)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def canonical_sha(obj):
    basis = copy.deepcopy(obj)
    basis.pop("semantic_sha256", None)
    return hashlib.sha256(
        json.dumps(basis, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def contract():
    return {
        "source": {
            "license": "ODbL-1.0",
            "road_source_sha256": "a" * 64,
            "crosswalk_semantic_sha256": "b" * 64,
            "readiness_semantic_sha256": "c" * 64,
        },
        "expected": {
            "mapping_count": 2,
            "destination_count": 2,
            "mapped_cell_count": 2,
            "multicell_hold_ids": [99, 100],
            "representatives": [
                {"road_osm_id": 1, "cell_id": "bxl-e147500-n169500-s500"},
                {"road_osm_id": 2, "cell_id": "bxl-e148000-n170000-s500"},
            ],
        },
        "policy": {"atomic_pair_required": True, "write_production_files_authorized": False},
    }


def candidates():
    cw = {"rows": [
        {"road_osm_id": 1, "cell_id": "bxl-e147500-n169500-s500"},
        {"road_osm_id": 2, "cell_id": "bxl-e148000-n170000-s500"},
    ]}
    rd = {"destinations": [
        {"road_osm_id": 1, "destination_id": "road-1", "cell_id": "bxl-e147500-n169500-s500", "readiness": "REGISTERED_NOT_RENDERED", "source_sha256": "a" * 64, "source_license": "ODbL-1.0", "render_authorized": False, "collision_authorized": False, "runtime_mount_authorized": False, "safe_spawn_authorized": False, "jouable_authorized": False},
        {"road_osm_id": 2, "destination_id": "road-2", "cell_id": "bxl-e148000-n170000-s500", "readiness": "REGISTERED_NOT_RENDERED", "source_sha256": "a" * 64, "source_license": "ODbL-1.0", "render_authorized": False, "collision_authorized": False, "runtime_mount_authorized": False, "safe_spawn_authorized": False, "jouable_authorized": False},
    ], "authorization": {"render_authorized": False, "collision_authorized": False, "runtime_mount_authorized": False, "safe_spawn_authorized": False, "jouable_authorized": False, "road_cell_mapping_authorized": False, "runtime_directory_scan_authorized": False}}
    return cw, rd


def current_wrappers():
    # Deliberately stale wrapper semantics. A valid build must repair these
    # rather than carrying legacy 56/3 identity into the corrected 96/4 pair.
    cw = {
        "schema": "grand-bruxelles-road-registered-cell-crosswalk-v1",
        "semantic_sha256": "d" * 64,
        "rows": [],
        "mapped_road_count": 0,
        "mapped_cell_count": 1,
        "road_cell_mapping_authorized": False,
        "runtime_directory_scan_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    }
    rd = {
        "schema": "grand-bruxelles-road-destination-readiness-catalog-v1",
        "semantic_sha256": "e" * 64,
        "road_cell_crosswalk_semantic_sha256": "d" * 64,
        "destinations": [],
        "destination_count": 0,
        "mapped_cell_count": 1,
        "authorization": {"render_authorized": False, "collision_authorized": False, "runtime_mount_authorized": False, "safe_spawn_authorized": False, "jouable_authorized": False, "road_cell_mapping_authorized": False, "runtime_directory_scan_authorized": False},
    }
    return cw, rd


def must_fail(cw_mut=None, rd_mut=None):
    cw, rd = candidates()
    if cw_mut: cw_mut(cw)
    if rd_mut: rd_mut(rd)
    try:
        current_cw, current_rd = current_wrappers()
        builder.build_pair(contract(), cw, rd, current_cw, current_rd)
    except AssertionError:
        return
    raise AssertionError("expected fail-closed rejection")


def test_valid_pair_recomputes_wrapper_semantics_and_binding():
    cw, rd = candidates()
    current_cw, current_rd = current_wrappers()
    old_cw_semantic = current_cw["semantic_sha256"]
    old_rd_semantic = current_rd["semantic_sha256"]
    out_cw, out_rd = builder.build_pair(contract(), cw, rd, current_cw, current_rd)
    assert len(out_cw["rows"]) == 2
    assert len(out_rd["destinations"]) == 2
    assert out_rd["destinations"][0]["destination_id"] == "road-1"
    assert out_cw["mapped_cell_count"] == 2
    assert out_rd["mapped_cell_count"] == 2
    assert out_cw["semantic_sha256"] != old_cw_semantic
    assert out_rd["semantic_sha256"] != old_rd_semantic
    assert out_cw["semantic_sha256"] == canonical_sha(out_cw)
    assert out_rd["road_cell_crosswalk_semantic_sha256"] == out_cw["semantic_sha256"]
    assert out_rd["semantic_sha256"] == canonical_sha(out_rd)


def test_destination_identity_mismatch_rejected():
    must_fail(rd_mut=lambda rd: rd["destinations"][0].update(destination_id="road-999"))


def test_duplicate_road_rejected():
    must_fail(cw_mut=lambda cw: cw["rows"].__setitem__(1, copy.deepcopy(cw["rows"][0])))


def test_hold_leakage_rejected():
    must_fail(cw_mut=lambda cw: cw["rows"][0].update(road_osm_id=99))


def test_cell_mismatch_rejected():
    must_fail(rd_mut=lambda rd: rd["destinations"][0].update(cell_id="bxl-e148000-n170000-s500"))


def test_runtime_authorization_rejected():
    must_fail(rd_mut=lambda rd: rd["destinations"][0].update(collision_authorized=True))


def test_real_contract_representatives_match_applied_crosswalk():
    d = json.loads(CONTRACT_PATH.read_text())
    crosswalk = json.loads(CROSSWALK_PATH.read_text())
    rows = {int(row["road_osm_id"]): row["cell_id"] for row in crosswalk["rows"]}
    representatives = {int(rep["road_osm_id"]): rep["cell_id"] for rep in d["expected"]["representatives"]}
    assert representatives == {
        8176386: "bxl-e147500-n169500-s500",
        150205016: "bxl-e147500-n170000-s500",
        13767417: "bxl-e148000-n170000-s500",
        8512036: "bxl-e148500-n170500-s500",
    }
    assert all(rows.get(road_id) == cell_id for road_id, cell_id in representatives.items())


def test_staged_semantic_repair_is_red_first_and_old_lock_is_superseded():
    d = json.loads(CONTRACT_PATH.read_text())
    assert d["status"] in {"MEASUREMENT_PENDING_WRAPPER_SEMANTIC_REPAIR", "LOCKED_STAGED_PAIR_EVIDENCE_ONLY_V2"}
    assert d["policy"]["write_production_files_authorized"] is False
    assert d["policy"]["runtime_probe_authorized"] is False
    assert d["policy"]["jouable_promotion_authorized"] is False
    assert d["policy"]["wrapper_semantic_sha_must_recompute"] is True
    assert d["policy"]["readiness_crosswalk_semantic_must_match_generated_crosswalk"] is True
    superseded = d["superseded_staged_evidence"]
    assert superseded["artifact_id"] == 9664991653
    assert superseded["reason"] == "wrapper_semantic_sha_inherited_from_legacy_56_3_state"
    assert superseded["observed_crosswalk_embedded_semantic_sha256"] == "54f5b91eaff3a010eb22be86f48fc9b9d80d3496658bccc87051e5e532ead6a0"
    assert superseded["recomputed_crosswalk_semantic_sha256"] == "8c95f77f232b283aa067d897e6eca318eee5194a2048a1fd350f60f95fa539f2"
    assert superseded["observed_readiness_embedded_semantic_sha256"] == "0c16d8c14fe6195e40b58e4b11bbcb0b67a5756f4b4fff8132a0122f9ca98f1e"
    if d["status"] == "LOCKED_STAGED_PAIR_EVIDENCE_ONLY_V2":
        lock = d["locked_staged_evidence_v2"]
        assert lock["mapping_count"] == 96
        assert lock["destination_count"] == 96
        assert lock["mapped_cell_count"] == 4
        assert lock["crosswalk_semantic_sha256"] == "8c95f77f232b283aa067d897e6eca318eee5194a2048a1fd350f60f95fa539f2"
        assert lock["readiness_semantic_sha256"] == "6da9a544bc1ae31ee8a58c447eedc5a4da0ad8bd7af4e47303f230cceb61cd59"


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS {name}")
