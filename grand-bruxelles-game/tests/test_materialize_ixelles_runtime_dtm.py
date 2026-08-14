import importlib.util
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "materialize_ixelles_runtime_dtm.py"


def load_tool():
    spec = importlib.util.spec_from_file_location("materialize_ixelles_runtime_dtm", TOOL)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_selected_cell_contract_rejects_other_cells(tmp_path):
    tool = load_tool()
    grid = np.zeros((251, 251), dtype=np.float64)
    try:
        tool.build_payload("bxl-e149500-n169000-s500", grid, {})
    except ValueError as exc:
        assert "selected Ixelles micro-slice" in str(exc)
    else:
        raise AssertionError("non-selected cell must be rejected")


def test_payload_is_exact_2m_grid_and_keeps_runtime_unapproved():
    tool = load_tool()
    grid = np.arange(251 * 251, dtype=np.float64).reshape(251, 251) / 100.0
    metadata = {
        "archive_sha256": {
            "149168": "f0277df26876c6c7cd3e00050e3d3a44b420b2df4bf4271e680717adeabb09b4",
            "149169": "c8135aa8456a5f2de8efb2e05dbf9c993ae9c97e4aa7f4d56c6c331345bac4f8",
        },
        "grid_sha256": tool.hash_grid(grid),
    }
    payload = tool.build_payload(tool.SELECTED_CELL_ID, grid, metadata)
    assert payload["cell_id"] == tool.SELECTED_CELL_ID
    assert payload["bbox_epsg31370"] == [149000.0, 169000.0, 149500.0, 169500.0]
    assert payload["spacing_m"] == 2.0
    assert payload["shape"] == [251, 251]
    assert payload["sample_count"] == 63001
    assert payload["heights_row_major_m"][0] == 0.0
    assert payload["heights_row_major_m"][-1] == grid[-1, -1]
    assert payload["runtime_approved"] is False
    assert payload["promote_runtime"] is False
    assert payload["source"]["crs"] == "EPSG:31370"


def test_write_payload_is_deterministic(tmp_path):
    tool = load_tool()
    grid = np.full((251, 251), 61.25, dtype=np.float64)
    payload = tool.build_payload(tool.SELECTED_CELL_ID, grid, {"grid_sha256": tool.hash_grid(grid)})
    first = tmp_path / "a.json"
    second = tmp_path / "b.json"
    tool.write_payload(payload, first)
    tool.write_payload(payload, second)
    assert first.read_bytes() == second.read_bytes()
    loaded = json.loads(first.read_text())
    assert loaded["sample_count"] == 63001
