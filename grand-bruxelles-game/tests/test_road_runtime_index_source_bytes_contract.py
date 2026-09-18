import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INDEX = ROOT / "data/runtime/road_destination_runtime_index.json"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_runtime_index_declared_source_hashes_match_current_source_bytes() -> None:
    """Fail closed when a generated road index points at stale source bytes."""
    payload = json.loads(INDEX.read_text(encoding="utf-8"))
    documents = payload.get("documents")
    assert isinstance(documents, list) and documents, "documents must be a non-empty list"

    seen_paths: set[str] = set()
    for descriptor in documents:
        assert isinstance(descriptor, dict), "source document descriptor must be an object"
        assert set(descriptor) == {"path", "sha256", "road_ids"}, (
            "source document descriptor must keep the runtime loader's exact closed schema"
        )
        source_path = descriptor.get("path")
        expected_sha = descriptor.get("sha256")
        road_ids = descriptor.get("road_ids")
        assert isinstance(source_path, str) and source_path.startswith("data/osm/")
        assert source_path.endswith(".game.json")
        assert "\\" not in source_path and "//" not in source_path
        assert source_path not in seen_paths, f"duplicate source document: {source_path}"
        seen_paths.add(source_path)
        assert isinstance(expected_sha, str) and len(expected_sha) == 64
        assert expected_sha == expected_sha.lower()
        int(expected_sha, 16)
        assert isinstance(road_ids, list) and road_ids, "road_ids must be a non-empty list"

        source_file = ROOT / source_path
        assert source_file.is_file(), f"missing runtime-index source document: {source_path}"
        actual_sha = _sha256(source_file)
        assert actual_sha == expected_sha, (
            f"stale runtime-index source digest for {source_path}: "
            f"declared={expected_sha} actual={actual_sha}"
        )
