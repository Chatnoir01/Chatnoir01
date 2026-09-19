import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).parents[1]
INDEX = ROOT / "data" / "runtime" / "road_destination_runtime_index.json"


def _repo_path(raw_path: str) -> Path:
    assert isinstance(raw_path, str)
    assert raw_path == raw_path.strip()
    assert "\\" not in raw_path
    relative = raw_path.removeprefix("res://")
    assert relative and not relative.startswith("/")
    parts = Path(relative).parts
    assert parts and all(part not in ("", ".", "..") for part in parts)
    return ROOT / relative


def test_runtime_index_descriptors_match_live_source_bytes_and_unique_roads() -> None:
    index = json.loads(INDEX.read_text(encoding="utf-8"))
    assert index["format"] == "grand-bruxelles-road-runtime-index-v1"
    assert index["source_lookup_only"] is True
    documents = index.get("documents")
    assert isinstance(documents, list) and documents

    seen_paths: set[str] = set()
    seen_roads: set[int] = set()
    for descriptor in documents:
        assert isinstance(descriptor, dict)
        raw_path = descriptor.get("path")
        source = _repo_path(raw_path)
        assert raw_path not in seen_paths
        seen_paths.add(raw_path)
        assert source.is_file(), raw_path

        declared = descriptor.get("sha256")
        assert isinstance(declared, str) and len(declared) == 64
        assert declared == declared.lower()
        int(declared, 16)
        actual = hashlib.sha256(source.read_bytes()).hexdigest()
        assert actual == declared, f"runtime index digest drift for {raw_path}"

        road_ids = descriptor.get("road_ids")
        assert isinstance(road_ids, list) and road_ids
        for road_id in road_ids:
            assert type(road_id) is int and road_id > 0
            assert road_id not in seen_roads, f"duplicate OSM road id {road_id}"
            seen_roads.add(road_id)

    assert seen_roads
