from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
RUNTIME_INDEX = ROOT / "data/runtime/road_destination_runtime_index.json"
ROAD_SOURCE = ROOT / "data/osm/vertical_slice_01.game.json"

EXPECTED_FORMAT = "grand-bruxelles-road-runtime-index-v1"
EXPECTED_SOURCE_PATH = "data/osm/vertical_slice_01.game.json"
EXPECTED_SOURCE_SHA256 = "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
EXPECTED_ROAD_COUNT = 139
EXPECTED_ROAD_IDS_SHA256 = "b450d7f97bea6fe31d8fc66a3789a77bf37a775dc25de21d0c4bd745143b03a0"


def _load(raw: bytes, label: str) -> Any:
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} is not valid UTF-8 JSON") from exc


def road_ids_semantic_sha256(road_ids: list[int]) -> str:
    canonical = "".join(f"{road_id}\n" for road_id in road_ids).encode("ascii")
    return hashlib.sha256(canonical).hexdigest()


def validate_runtime_identity_set(runtime_raw: bytes, source_raw: bytes) -> None:
    runtime = _load(runtime_raw, "runtime index")
    source = _load(source_raw, "road source")
    if not isinstance(runtime, dict) or runtime.get("format") != EXPECTED_FORMAT:
        raise ValueError("runtime index format drift")
    if runtime.get("source_lookup_only") is not True:
        raise ValueError("runtime index must remain source-lookup-only")
    documents = runtime.get("documents")
    if not isinstance(documents, list) or len(documents) != 1 or not isinstance(documents[0], dict):
        raise ValueError("runtime index document accounting drift")
    document = documents[0]
    if document.get("path") != EXPECTED_SOURCE_PATH or document.get("sha256") != EXPECTED_SOURCE_SHA256:
        raise ValueError("runtime index source identity drift")
    if hashlib.sha256(source_raw).hexdigest() != EXPECTED_SOURCE_SHA256:
        raise ValueError("locked OSM source bytes drift")
    roads = source.get("roads") if isinstance(source, dict) else None
    if not isinstance(roads, list):
        raise ValueError("locked OSM source roads shape drift")
    source_ids = {road.get("osm_id") for road in roads if isinstance(road, dict)}
    road_ids = document.get("road_ids")
    if not isinstance(road_ids, list) or len(road_ids) != EXPECTED_ROAD_COUNT:
        raise ValueError("runtime road identity accounting drift")
    if any(type(road_id) is not int or road_id <= 0 for road_id in road_ids):
        raise ValueError("runtime road identity invalid")
    if road_ids != sorted(road_ids) or len(set(road_ids)) != len(road_ids):
        raise ValueError("runtime road identities must remain unique and sorted")
    if not set(road_ids).issubset(source_ids):
        raise ValueError("runtime road identity absent from locked OSM source")
    if road_ids_semantic_sha256(road_ids) != EXPECTED_ROAD_IDS_SHA256:
        raise ValueError("runtime road identity set semantic digest drift")


def main() -> int:
    validate_runtime_identity_set(RUNTIME_INDEX.read_bytes(), ROAD_SOURCE.read_bytes())
    print("spatial crosswalk runtime identity set: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
