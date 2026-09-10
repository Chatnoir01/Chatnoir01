from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.city_machine.validate_registered_cell_manifest_index_identity import validate_registered_cell_manifest_index_identity

LOCK_PATH = ROOT / "data/source_plans/brussels_spatial_crosswalk_geometric_overlap_relations.lock.json"
SOURCE_PATH = ROOT / "data/osm/vertical_slice_01.game.json"
RUNTIME_PATH = ROOT / "data/runtime/road_destination_runtime_index.json"
CELLS_PATH = ROOT / "data/provenance/brussels_registered_cell_manifest_index.json"
PAYLOAD_LOCK_PATH = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_artifact_payload.lock.json"

EXPECTED_RELATION_SHA256 = "dea982dde7b4e13ffb615e5c4decc665201536658d38d7e6f138179a6259c327"
EXPECTED_SOURCE_SHA256 = "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
EXPECTED_RUNTIME_CATALOG_SHA256 = "7290b8272623e0cd5905224c8696d74a3015b1db9aab00ef19d1cf7676dea59f"
EXPECTED_ROAD_IDS_SHA256 = "b450d7f97bea6fe31d8fc66a3789a77bf37a775dc25de21d0c4bd745143b03a0"
EXPECTED_CELL_INDEX_SHA256 = "8dd6b8994160b7a22b83f8be4ce63cfa4b579f724d51b3896c0426782b259187"
EXPECTED_MEMBER_SHA256 = "95310885fcf030530dddae5b85eacdec79b7f407d3e9f2f0934c2b1e1e7e2ee6"
EXPECTED_SCOPE_NOTE = (
    "Deterministic geometric road-to-registered-cell intersection evidence derived from the locked OSM source, "
    "runtime road identity set, registered cell bboxes and #1562 artifact. Relations are evidence only and do not "
    "authorize semantic crosswalk, runtime cell assignment, rendering, collision, spawn safety or JOUABLE promotion."
)
AUTH_KEYS = {
    "crosswalk_authorized", "road_cell_mapping_authorized", "runtime_mount_authorized",
    "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized",
    "jouable_promotion_authorized",
}
LOCK_KEYS = {
    "schema", "evidence_state", "artifact", "frame", "road_source", "runtime_identity_set",
    "registered_cell_index", "accounting", "relation_semantic_sha256", "relations", "authorization", "scope_note",
}


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _reject_nonstandard_constant(value: str) -> Any:
    raise ValueError(f"non-standard JSON constant: {value}")


def _parse_finite_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError(f"non-finite JSON number: {value}")
    return parsed


def _load(raw: bytes, label: str) -> Any:
    try:
        return json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=_reject_duplicate_pairs,
            parse_constant=_reject_nonstandard_constant,
            parse_float=_parse_finite_float,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} is not strict UTF-8 JSON") from exc


def _segment_intersects_rect(p0: tuple[float, float], p1: tuple[float, float], rect: tuple[float, float, float, float]) -> bool:
    x0, y0 = p0
    x1, y1 = p1
    xmin, ymin, xmax, ymax = rect
    dx = x1 - x0
    dy = y1 - y0
    p = (-dx, dx, -dy, dy)
    q = (x0 - xmin, xmax - x0, y0 - ymin, ymax - y0)
    u0 = 0.0
    u1 = 1.0
    for pi, qi in zip(p, q, strict=True):
        if pi == 0.0:
            if qi < 0.0:
                return False
            continue
        t = qi / pi
        if pi < 0.0:
            if t > u1:
                return False
            u0 = max(u0, t)
        else:
            if t < u0:
                return False
            u1 = min(u1, t)
    return True


def _road_intersects_cell(points: list[list[float]], origin_e: float, origin_n: float, rect: tuple[float, float, float, float]) -> bool:
    projected = [(origin_e + float(x), origin_n - float(z)) for x, z in points]
    xmin, ymin, xmax, ymax = rect
    if any(xmin <= e <= xmax and ymin <= n <= ymax for e, n in projected):
        return True
    return any(_segment_intersects_rect(p0, p1, rect) for p0, p1 in zip(projected, projected[1:]))


def _relation_digest(relations: list[dict[str, Any]]) -> str:
    canonical = "".join(f"{entry['osm_id']}\t{entry['cell_id']}\n" for entry in relations).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def validate_overlap_relation_lock(lock_raw: bytes, source_raw: bytes, runtime_raw: bytes, cells_raw: bytes, payload_lock_raw: bytes) -> None:
    validate_registered_cell_manifest_index_identity(cells_raw)

    lock = _load(lock_raw, "geometric overlap relation lock")
    source = _load(source_raw, "locked OSM source")
    runtime = _load(runtime_raw, "runtime road identity set")
    cells = _load(cells_raw, "registered cell index")
    payload = _load(payload_lock_raw, "origin artifact payload lock")

    if not isinstance(lock, dict) or set(lock) != LOCK_KEYS:
        raise ValueError("geometric overlap relation lock schema drift")
    if lock["schema"] != "grand-bruxelles-spatial-crosswalk-geometric-overlap-relations-v1":
        raise ValueError("geometric overlap relation lock schema identity drift")
    if lock["evidence_state"] != "DISCOVERED_GEOMETRIC_INTERSECTION_EVIDENCE_ONLY":
        raise ValueError("geometric overlap relation evidence state drift")
    if lock["scope_note"] != EXPECTED_SCOPE_NOTE:
        raise ValueError("geometric overlap relation scope semantics drift")

    auth = lock["authorization"]
    if not isinstance(auth, dict) or set(auth) != AUTH_KEYS or any(type(value) is not bool or value is not False for value in auth.values()):
        raise ValueError("geometric overlap relation authorization must remain fully closed")

    artifact = lock["artifact"]
    expected_artifact = {
        "workflow_run_id": 34248313500,
        "workflow_head_sha": "9fdbf01073deb311097bcc70e2e8b627a004a8b1",
        "artifact_id": 10065069360,
        "member": "road_registered_cell_overlap_v2.json",
        "member_sha256": EXPECTED_MEMBER_SHA256,
    }
    if artifact != expected_artifact:
        raise ValueError("geometric overlap relation artifact identity drift")
    members = payload.get("members") if isinstance(payload, dict) else None
    if (
        payload.get("workflow_run_id") != artifact["workflow_run_id"]
        or payload.get("workflow_head_sha") != artifact["workflow_head_sha"]
        or payload.get("artifact_id") != artifact["artifact_id"]
        or not isinstance(members, list)
        or len(members) != 1
        or members[0].get("name") != artifact["member"]
        or members[0].get("sha256") != artifact["member_sha256"]
    ):
        raise ValueError("geometric overlap relation lock is not bound to the locked artifact payload")

    expected_frame = {
        "crs": "EPSG:31370",
        "origin_easting_m": 147868.29422791934,
        "origin_northing_m": 169538.62414926197,
        "formula": "E=origin_easting_m+x;N=origin_northing_m-z",
    }
    if lock["frame"] != expected_frame:
        raise ValueError("geometric overlap relation frame drift")

    source_contract = lock["road_source"]
    if source_contract != {
        "path": "data/osm/vertical_slice_01.game.json",
        "sha256": EXPECTED_SOURCE_SHA256,
        "provider": "OpenStreetMap contributors via Overpass API",
        "license": "ODbL-1.0",
    }:
        raise ValueError("geometric overlap relation source contract drift")
    if hashlib.sha256(source_raw).hexdigest() != EXPECTED_SOURCE_SHA256:
        raise ValueError("geometric overlap relation source bytes drift")
    if source.get("source") != source_contract["provider"] or source.get("license") != source_contract["license"]:
        raise ValueError("geometric overlap relation source provenance drift")

    runtime_contract = lock["runtime_identity_set"]
    if runtime_contract != {
        "path": "data/runtime/road_destination_runtime_index.json",
        "catalog_sha256": EXPECTED_RUNTIME_CATALOG_SHA256,
        "ordered_road_ids_sha256": EXPECTED_ROAD_IDS_SHA256,
        "road_count": 139,
    }:
        raise ValueError("geometric overlap relation runtime identity contract drift")
    if runtime.get("catalog_sha256") != EXPECTED_RUNTIME_CATALOG_SHA256 or runtime.get("source_lookup_only") is not True:
        raise ValueError("geometric overlap relation runtime catalog drift")
    documents = runtime.get("documents")
    if not isinstance(documents, list) or len(documents) != 1:
        raise ValueError("geometric overlap relation runtime document accounting drift")
    road_ids = documents[0].get("road_ids")
    if not isinstance(road_ids, list) or road_ids != sorted(set(road_ids)) or len(road_ids) != 139:
        raise ValueError("geometric overlap relation runtime road identity drift")
    road_id_digest = hashlib.sha256("".join(f"{road_id}\n" for road_id in road_ids).encode("ascii")).hexdigest()
    if road_id_digest != EXPECTED_ROAD_IDS_SHA256:
        raise ValueError("geometric overlap relation runtime road identity digest drift")

    cells_contract = lock["registered_cell_index"]
    if cells_contract != {
        "path": "data/provenance/brussels_registered_cell_manifest_index.json",
        "semantic_sha256": EXPECTED_CELL_INDEX_SHA256,
        "registered_cell_count": 5,
    }:
        raise ValueError("geometric overlap relation registered-cell contract drift")
    if cells.get("semantic_sha256") != EXPECTED_CELL_INDEX_SHA256 or cells.get("registered_cell_count") != 5:
        raise ValueError("geometric overlap relation registered-cell index drift")
    cell_entries = cells.get("entries")
    if not isinstance(cell_entries, list) or len(cell_entries) != 5:
        raise ValueError("geometric overlap relation registered-cell entry accounting drift")
    cell_rects: dict[str, tuple[float, float, float, float]] = {}
    for entry in cell_entries:
        if not isinstance(entry, dict) or entry.get("crs") != "EPSG:31370":
            raise ValueError("geometric overlap relation registered-cell CRS drift")
        cell_id = entry.get("cell_id")
        bbox = entry.get("bbox")
        if not isinstance(cell_id, str) or not isinstance(bbox, list) or len(bbox) != 4:
            raise ValueError("geometric overlap relation registered-cell geometry drift")
        cell_rects[cell_id] = tuple(float(value) for value in bbox)
    if len(cell_rects) != 5:
        raise ValueError("geometric overlap relation duplicate registered-cell identity")

    roads = source.get("roads")
    if not isinstance(roads, list) or len(roads) != 140:
        raise ValueError("geometric overlap relation source road accounting drift")
    roads_by_id = {road.get("osm_id"): road for road in roads if isinstance(road, dict)}
    if len(roads_by_id) != 140 or not set(road_ids).issubset(roads_by_id):
        raise ValueError("geometric overlap relation source road identity drift")

    recomputed: list[dict[str, Any]] = []
    origin_e = expected_frame["origin_easting_m"]
    origin_n = expected_frame["origin_northing_m"]
    for road_id in road_ids:
        points = roads_by_id[road_id].get("points")
        if not isinstance(points, list) or len(points) < 2:
            raise ValueError(f"geometric overlap relation road {road_id} has invalid points")
        for cell_id in sorted(cell_rects):
            if _road_intersects_cell(points, origin_e, origin_n, cell_rects[cell_id]):
                recomputed.append({"osm_id": road_id, "cell_id": cell_id})

    relations = lock["relations"]
    if not isinstance(relations, list):
        raise ValueError("geometric overlap relation list drift")
    if any(
        not isinstance(entry, dict)
        or set(entry) != {"osm_id", "cell_id"}
        or type(entry["osm_id"]) is not int
        or not isinstance(entry["cell_id"], str)
        for entry in relations
    ):
        raise ValueError("geometric overlap relation entry schema drift")
    ordered = sorted(relations, key=lambda entry: (entry["osm_id"], entry["cell_id"]))
    if relations != ordered or len({(entry["osm_id"], entry["cell_id"]) for entry in relations}) != len(relations):
        raise ValueError("geometric overlap relations must remain unique and sorted")
    if relations != recomputed:
        raise ValueError("geometric overlap relation identity differs from repository geometry")

    digest = _relation_digest(relations)
    if digest != lock["relation_semantic_sha256"] or digest != EXPECTED_RELATION_SHA256:
        raise ValueError("geometric overlap relation semantic digest drift")

    per_cell: dict[str, int] = {}
    for relation in relations:
        per_cell[relation["cell_id"]] = per_cell.get(relation["cell_id"], 0) + 1
    accounting = lock["accounting"]
    expected_accounting = {
        "overlapping_road_count": len({entry["osm_id"] for entry in relations}),
        "road_cell_relation_count": len(relations),
        "distinct_cells_with_overlap": len(per_cell),
        "relations_per_cell": dict(sorted(per_cell.items())),
    }
    if accounting != expected_accounting:
        raise ValueError("geometric overlap relation accounting drift")
    if accounting != {
        "overlapping_road_count": 64,
        "road_cell_relation_count": 66,
        "distinct_cells_with_overlap": 3,
        "relations_per_cell": {
            "bxl-e147500-n169500-s500": 53,
            "bxl-e147500-n170000-s500": 11,
            "bxl-e148000-n170000-s500": 2,
        },
    }:
        raise ValueError("geometric overlap relation locked accounting identity drift")


def main() -> int:
    validate_overlap_relation_lock(
        LOCK_PATH.read_bytes(), SOURCE_PATH.read_bytes(), RUNTIME_PATH.read_bytes(), CELLS_PATH.read_bytes(), PAYLOAD_LOCK_PATH.read_bytes()
    )
    print("spatial crosswalk geometric overlap relations: OK (64 roads / 66 exact relations / authorization CLOSED)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
