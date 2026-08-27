import copy
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools/qa/build_corrected_frame_destination_production_pair.py"
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
    out_cw, out_rd = builder.build_pair(contract(), cw, rd, {"rows": []}, {"destinations": [], "authorization": {}})
    assert len(out_cw["rows"]) == 2
    assert len(out_rd["destinations"]) == 2
    assert out_rd["destinations"][0]["destination_id"] == "road-1"
    assert out_cw["mapped_cell_count"] == 2


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


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS {name}")
