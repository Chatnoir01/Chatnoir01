from pathlib import Path
import importlib.util


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "build_road_source_geometry_index.py"


def _load_tool():
    spec = importlib.util.spec_from_file_location("road_source_geometry_index", TOOL)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_geometry_index_is_lookup_only_and_cannot_self_promote():
    module = _load_tool()
    assert module.AUTHORIZATION == {
        "source_lookup_only": True,
        "render_authorized": False,
        "collision_authorized": False,
        "runtime_mount_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_authorized": False,
    }


def test_geometry_index_payload_preserves_closed_authorization_rails():
    module = _load_tool()
    payload = module.build_index(ROOT / "data" / "osm")
    assert payload["format"] == module.FORMAT
    assert payload["entry_count"] == len(payload["entries"])
    assert payload["authorization"] == module.AUTHORIZATION
    assert payload["authorization"] is not module.AUTHORIZATION
    assert payload["entry_count"] > 0
