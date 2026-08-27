import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools/qa/build_corrected_frame_destination_production_pair.py"
CONTRACT_PATH = ROOT / "data/qa/corrected_frame_destination_production_apply.contract.json"
spec = importlib.util.spec_from_file_location("builder", MODULE_PATH)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


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


def must_fail(cw_mut=None, rd_mut=None):
    cw, rd = candidates()
    if cw_mut: cw_mut(cw)
    if rd_mut: rd_mut(rd)
    try:
        builder.build_pair(contract(), cw, rd, {"rows": []}, {"destinations": [], "authorization": {}})
    except AssertionError:
        return
    raise AssertionError("expected fail-closed rejection")


def test_valid_pair():
    cw, rd = candidates()
    out_cw, out_rd = builder.build_pair(
        contract(),
        cw,
        rd,
        {"rows": [], "mapped_cell_count": 1},
        {"destinations": [], "mapped_cell_count": 1, "authorization": {}},
    )
    assert len(out_cw["rows"]) == 2
    assert len(out_rd["destinations"]) == 2
    assert out_rd["destinations"][0]["destination_id"] == "road-1"
    assert out_cw["mapped_cell_count"] == 2
    assert out_rd["mapped_cell_count"] == 2


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


def test_corrected_staged_lock_is_exact_and_never_authorizes_production_write():
    d = json.loads(CONTRACT_PATH.read_text())
    assert d["status"] == "LOCKED_STAGED_PAIR_EVIDENCE_ONLY"
    assert d["policy"]["write_production_files_authorized"] is False
    assert d["policy"]["runtime_probe_authorized"] is False
    assert d["policy"]["jouable_promotion_authorized"] is False
    assert d["policy"]["readiness_mapped_cell_count_must_equal_crosswalk"] is True
    assert d["policy"]["red_first_artifact_must_upload_before_lock"] is True

    superseded = d["superseded_staged_evidence"]
    assert superseded["reason"] == "readiness_mapped_cell_count_inherited_stale_wrapper_3_expected_4"
    assert superseded["artifact_id"] == 9664489630
    assert superseded["generated_readiness_sha256"] == "2c98aa4315d446628ce260254082d76b29bd8fb097b73f76d0b5bfa03483f6b3"
    assert superseded["observed_readiness_mapped_cell_count"] == 3
    assert superseded["actual_destination_cell_count"] == 4

    locked = d["locked_staged_evidence"]
    assert locked["run_id"] == 33117227791
    assert locked["head_sha"] == "e19da871855b9bdc8a83acce5d1dfe4aa08e7af2"
    assert locked["artifact_id"] == 9664991653
    expected_hashes = {
        "artifact_sha256": "fbe7a847bdfbd8e3e2d736e06fe63c4e6324233b30c78d49c8ca578e1a386d63",
        "generated_crosswalk_sha256": "a838c4e19386771491472825b5dc2c742ae18510570cc05070b387bb09e01039",
        "generated_readiness_sha256": "95430fb61fb3205fb4f3bd4c59b9720b0feb475ce04f5ede2c7b74d22ec6f040",
    }
    for key, expected in expected_hashes.items():
        assert locked[key] == expected
        assert len(locked[key]) == 64
        int(locked[key], 16)
    assert locked["mapping_count"] == 96
    assert locked["destination_count"] == 96
    assert locked["mapped_cell_count"] == 4
    assert locked["readiness_mapped_cell_count"] == 4
    assert locked["multicell_hold_ids"] == [256158619, 397461693]


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS {name}")
