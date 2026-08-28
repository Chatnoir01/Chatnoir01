#!/usr/bin/env python3
"""Build deterministic road -> source -> cell -> municipality provenance evidence.

This manifest is evidence only. DISCOVERED/REGISTERED states never authorize render,
collision, runtime mount, safe spawn, or JOUABLE promotion.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-road-destination-provenance-binding-v1"
READINESS_SCHEMA = "grand-bruxelles-road-destination-readiness-catalog-v1"


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_sha256(value: Any) -> bool:
    text = str(value or "").lower()
    return len(text) == 64 and all(ch in "0123456789abcdef" for ch in text)


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: expected object {path}")
    return value


def load_catalog_builder(script_path: Path):
    spec = importlib.util.spec_from_file_location("road_catalog_builder", script_path)
    if spec is None or spec.loader is None:
        raise SystemExit("ROAD_PROVENANCE_BINDING_FAIL: cannot load road catalog builder")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require_closed(mapping: dict[str, Any], keys: tuple[str, ...], label: str) -> None:
    for key in keys:
        if mapping.get(key) is not False:
            raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: {label} opened {key}")


def verify_readiness_semantic(readiness: dict[str, Any]) -> str:
    stored = str(readiness.get("semantic_sha256") or "").lower()
    if not is_sha256(stored):
        raise SystemExit("ROAD_PROVENANCE_BINDING_FAIL: readiness semantic sha invalid")
    unsigned = dict(readiness)
    unsigned.pop("semantic_sha256", None)
    expected = sha256_json(unsigned)
    if stored != expected:
        raise SystemExit(
            f"ROAD_PROVENANCE_BINDING_FAIL: readiness semantic drift stored={stored} expected={expected}"
        )
    return stored


def normalize_municipalities(raw: Any, road_id: int) -> list[dict[str, Any]]:
    if not isinstance(raw, list) or not raw:
        raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: missing municipality provenance {road_id}")
    result: list[dict[str, Any]] = []
    for item in raw:
        if not isinstance(item, dict):
            raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: malformed municipality provenance {road_id}")
        nis = str(item.get("niscode") or "")
        inspire = str(item.get("inspire_id") or "")
        try:
            ratio = float(item.get("coverage_ratio"))
        except (TypeError, ValueError) as exc:
            raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: invalid municipality ratio {road_id}") from exc
        if not nis or not inspire or not (0.0 < ratio <= 1.0):
            raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: invalid municipality identity {road_id}")
        result.append({"niscode": nis, "inspire_id": inspire, "coverage_ratio": ratio})
    result.sort(key=lambda row: (row["niscode"], row["inspire_id"]))
    if abs(sum(row["coverage_ratio"] for row in result) - 1.0) > 1e-9:
        raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: municipality coverage drift {road_id}")
    return result


def municipalities_from_manifest_provenance(provenance: Any, road_id: int) -> list[dict[str, Any]]:
    """Normalize both canonical cell municipality provenance shapes without inference.

    Boundary cells carry the explicit municipality_intersections list. Cells wholly
    inside one municipality carry the canonical singular municipality fields. Both
    are authoritative fields already present in the locked cell manifest; no spatial
    or semantic value is guessed here.
    """
    if not isinstance(provenance, dict):
        raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: missing cell manifest provenance {road_id}")
    intersections = provenance.get("municipality_intersections")
    if intersections is not None:
        return normalize_municipalities(intersections, road_id)

    nis = str(provenance.get("municipality_niscode") or "")
    inspire = str(provenance.get("municipality_id") or "")
    try:
        ratio = float(provenance.get("municipality_coverage_ratio"))
    except (TypeError, ValueError) as exc:
        raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: invalid singular municipality provenance {road_id}") from exc
    if not nis or not inspire or abs(ratio - 1.0) > 1e-9:
        raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: invalid singular municipality provenance {road_id}")
    return normalize_municipalities(
        [{"niscode": nis, "inspire_id": inspire, "coverage_ratio": ratio}], road_id
    )


def verify_cell_manifest(project_root: Path, destination: dict[str, Any], road_id: int) -> list[dict[str, Any]]:
    cell_id = str(destination.get("cell_id") or "")
    grid_cell_id = str(destination.get("grid_cell_id") or "")
    cell_manifest_path = str(destination.get("cell_manifest_path") or "")
    cell_manifest_sha = str(destination.get("cell_manifest_sha256") or "").lower()
    if not cell_id or not grid_cell_id or not cell_manifest_path.startswith("data/cell_manifests/") or not is_sha256(cell_manifest_sha):
        raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: cell provenance drift {road_id}")
    manifest_path = project_root / cell_manifest_path
    if not manifest_path.is_file():
        raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: missing cell manifest {road_id}")
    actual_sha = sha256_file(manifest_path)
    if actual_sha != cell_manifest_sha:
        raise SystemExit(
            f"ROAD_PROVENANCE_BINDING_FAIL: cell manifest sha drift {road_id} stored={cell_manifest_sha} actual={actual_sha}"
        )
    manifest = load_json(manifest_path)
    if manifest.get("cell_id") != cell_id:
        raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: cell manifest identity drift {road_id}")
    if manifest.get("crs") != destination.get("cell_crs"):
        raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: cell manifest CRS drift {road_id}")
    if manifest.get("bbox") != destination.get("cell_bbox"):
        raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: cell manifest bbox drift {road_id}")
    manifest_municipalities = municipalities_from_manifest_provenance(manifest.get("provenance"), road_id)
    destination_municipalities = normalize_municipalities(destination.get("municipalities"), road_id)
    if manifest_municipalities != destination_municipalities:
        raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: cell municipality provenance drift {road_id}")
    return destination_municipalities


def build_binding(source_root: Path, readiness_path: Path, catalog_builder_path: Path) -> dict[str, Any]:
    builder = load_catalog_builder(catalog_builder_path)
    catalog = builder.build_catalog(source_root)
    builder.validate_contract(catalog)
    builder.validate_source_binding(catalog, source_root)
    project_root = source_root.parent.parent

    readiness = load_json(readiness_path)
    if readiness.get("schema") != READINESS_SCHEMA:
        raise SystemExit("ROAD_PROVENANCE_BINDING_FAIL: readiness schema drift")
    if readiness.get("status") != "SOURCE_BACKED_REGISTERED_NOT_RENDERED":
        raise SystemExit("ROAD_PROVENANCE_BINDING_FAIL: readiness status drift")
    readiness_sha = verify_readiness_semantic(readiness)
    require_closed(
        readiness.get("authorization") or {},
        (
            "road_cell_mapping_authorized",
            "runtime_directory_scan_authorized",
            "runtime_mount_authorized",
            "render_authorized",
            "collision_authorized",
            "safe_spawn_authorized",
            "jouable_authorized",
        ),
        "readiness catalog",
    )

    destinations = readiness.get("destinations")
    if not isinstance(destinations, list) or int(readiness.get("destination_count", -1)) != len(destinations):
        raise SystemExit("ROAD_PROVENANCE_BINDING_FAIL: readiness destination accounting drift")

    registered: dict[int, dict[str, Any]] = {}
    for destination in destinations:
        if not isinstance(destination, dict):
            raise SystemExit("ROAD_PROVENANCE_BINDING_FAIL: malformed destination")
        road_id = int(destination.get("road_osm_id", 0))
        if road_id <= 0 or road_id in registered:
            raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: invalid/duplicate road {road_id}")
        source_entry = catalog["entries"].get(str(road_id))
        if source_entry is None:
            raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: registered road absent from source catalog {road_id}")
        source_path = str(destination.get("source_path") or "")
        source_sha = str(destination.get("source_sha256") or "").lower()
        if source_path not in source_entry.get("source_paths", []):
            raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: source path drift {road_id}")
        if catalog["source_document_sha256"].get(source_path) != source_sha:
            raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: source document sha drift {road_id}")
        if destination.get("source_points_sha256") != source_entry.get("geometry_sha256"):
            raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: source geometry sha drift {road_id}")
        if destination.get("readiness") != "REGISTERED_NOT_RENDERED":
            raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: readiness drift {road_id}")
        if destination.get("cell_crs") != "EPSG:31370":
            raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: cell CRS drift {road_id}")
        require_closed(
            destination,
            ("render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"),
            f"destination {road_id}",
        )
        municipalities = verify_cell_manifest(project_root, destination, road_id)
        if destination.get("municipality_niscodes") != [row["niscode"] for row in municipalities]:
            raise SystemExit(f"ROAD_PROVENANCE_BINDING_FAIL: municipality NIS accounting drift {road_id}")
        cell_id = str(destination.get("cell_id") or "")
        grid_cell_id = str(destination.get("grid_cell_id") or "")
        cell_manifest_path = str(destination.get("cell_manifest_path") or "")
        cell_manifest_sha = str(destination.get("cell_manifest_sha256") or "").lower()
        registered[road_id] = {
            "state": "REGISTERED_NOT_RENDERED",
            "cell_id": cell_id,
            "grid_cell_id": grid_cell_id,
            "cell_crs": "EPSG:31370",
            "cell_bbox": destination.get("cell_bbox"),
            "cell_manifest_path": cell_manifest_path,
            "cell_manifest_sha256": cell_manifest_sha,
            "municipalities": municipalities,
        }

    entries: dict[str, Any] = {}
    for raw_id, source_entry in catalog["entries"].items():
        road_id = int(raw_id)
        item = {
            "road_osm_id": road_id,
            "name": source_entry["name"],
            "source_paths": source_entry["source_paths"],
            "source_geometry_sha256": source_entry["geometry_sha256"],
            "state": "DISCOVERED",
            "render_authorized": False,
            "collision_authorized": False,
            "runtime_mount_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_authorized": False,
        }
        if road_id in registered:
            item.update(registered[road_id])
        entries[raw_id] = item

    registered_count = len(registered)
    discovered_only_count = len(entries) - registered_count
    payload: dict[str, Any] = {
        "format": FORMAT,
        "source_catalog_sha256": catalog["catalog_sha256"],
        "readiness_catalog_semantic_sha256": readiness_sha,
        "source_document_sha256": catalog["source_document_sha256"],
        "entry_count": len(entries),
        "registered_not_rendered_count": registered_count,
        "discovered_only_count": discovered_only_count,
        "mapped_cell_count": len({row["cell_id"] for row in registered.values()}),
        "municipality_niscodes": sorted({m["niscode"] for row in registered.values() for m in row["municipalities"]}),
        "entries": entries,
        "authorization": {
            "evidence_only": True,
            "render_authorized": False,
            "collision_authorized": False,
            "runtime_mount_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_authorized": False,
        },
    }
    payload["binding_sha256"] = sha256_json(payload)
    return payload


def validate_binding(binding: dict[str, Any]) -> None:
    if binding.get("format") != FORMAT:
        raise SystemExit("ROAD_PROVENANCE_BINDING_FAIL: format drift")
    if not is_sha256(binding.get("source_catalog_sha256")) or not is_sha256(binding.get("readiness_catalog_semantic_sha256")):
        raise SystemExit("ROAD_PROVENANCE_BINDING_FAIL: upstream semantic identity missing")
    entries = binding.get("entries")
    if not isinstance(entries, dict) or int(binding.get("entry_count", -1)) != len(entries):
        raise SystemExit("ROAD_PROVENANCE_BINDING_FAIL: entry accounting drift")
    registered = sum(1 for row in entries.values() if row.get("state") == "REGISTERED_NOT_RENDERED")
    discovered = sum(1 for row in entries.values() if row.get("state") == "DISCOVERED")
    if registered != int(binding.get("registered_not_rendered_count", -1)) or discovered != int(binding.get("discovered_only_count", -1)) or registered + discovered != len(entries):
        raise SystemExit("ROAD_PROVENANCE_BINDING_FAIL: state accounting drift")
    auth = binding.get("authorization") or {}
    if auth.get("evidence_only") is not True:
        raise SystemExit("ROAD_PROVENANCE_BINDING_FAIL: evidence-only rail missing")
    require_closed(auth, ("render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"), "binding")
    stored = str(binding.get("binding_sha256") or "").lower()
    unsigned = dict(binding)
    unsigned.pop("binding_sha256", None)
    if not is_sha256(stored) or stored != sha256_json(unsigned):
        raise SystemExit("ROAD_PROVENANCE_BINDING_FAIL: binding sha drift")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=Path("data/osm"))
    parser.add_argument("--readiness", type=Path, default=Path("data/provenance/brussels_road_destination_readiness_catalog.json"))
    parser.add_argument("--catalog-builder", type=Path, default=Path("tools/build_road_destination_catalog.py"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    binding = build_binding(args.source_root, args.readiness, args.catalog_builder)
    validate_binding(binding)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(binding, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "ROAD_PROVENANCE_BINDING_OK: "
        f"entries={binding['entry_count']} registered={binding['registered_not_rendered_count']} "
        f"discovered_only={binding['discovered_only_count']} cells={binding['mapped_cell_count']} "
        f"municipalities={len(binding['municipality_niscodes'])} sha256={binding['binding_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())