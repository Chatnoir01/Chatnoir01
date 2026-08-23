#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
from pathlib import Path

CELL_RE = re.compile(r"^bxl-e(?P<e>\d+)-n(?P<n>\d+)-s500$")
AUTH_KEYS = (
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
)


def _canonical_sha(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def _validate_manifest(path: Path, root: Path):
    raw = path.read_bytes()
    doc = json.loads(raw)
    if doc.get("format") != "grand-bruxelles-cell-maturity-v1":
        raise RuntimeError(f"unsupported manifest format: {path}")
    cell_id = doc.get("cell_id")
    match = CELL_RE.fullmatch(str(cell_id))
    if not match:
        raise RuntimeError(f"invalid canonical cell id: {cell_id}")
    if doc.get("crs") != "EPSG:31370":
        raise RuntimeError(f"invalid CRS for {cell_id}")
    e, n = int(match.group("e")), int(match.group("n"))
    expected_bbox = [float(e), float(n), float(e + 500), float(n + 500)]
    if doc.get("bbox") != expected_bbox:
        raise RuntimeError(f"bbox does not match cell id for {cell_id}")
    maturity = doc.get("maturity") or {}
    if maturity.get("state") != "data_ready":
        raise RuntimeError(f"cell is not evidence-only data_ready: {cell_id}")
    gates = maturity.get("gates") or {}
    if not gates:
        raise RuntimeError(f"missing maturity gates: {cell_id}")
    for key, value in gates.items():
        if not isinstance(value, bool) or value is not False:
            raise RuntimeError(f"maturity gate must remain boolean false: {cell_id}:{key}")
    provenance = doc.get("provenance") or {}
    if provenance.get("source_records_present") is not True:
        raise RuntimeError(f"missing source records: {cell_id}")
    geometry = doc.get("geometry") or {}
    if geometry.get("authoritative_geometry_ready") is not True:
        raise RuntimeError(f"authoritative source geometry not ready: {cell_id}")
    rel = path.relative_to(root).as_posix()
    return {
        "cell_id": cell_id,
        "manifest_path": rel,
        "manifest_sha256": hashlib.sha256(raw).hexdigest(),
        "crs": doc["crs"],
        "bbox": doc["bbox"],
        "maturity_state": maturity["state"],
        "evidence_only": True,
        **{key: False for key in AUTH_KEYS},
    }


def build(manifest_dir: Path, repo_root: Path, production_base_sha: str):
    if not re.fullmatch(r"[0-9a-f]{40}", production_base_sha):
        raise RuntimeError("production_base_sha must be a full lowercase SHA-1")
    paths = sorted(manifest_dir.glob("*.json"))
    if not paths:
        raise RuntimeError("no registered cell manifests found")
    entries = [_validate_manifest(path, repo_root) for path in paths]
    ids = [row["cell_id"] for row in entries]
    if len(ids) != len(set(ids)):
        raise RuntimeError("duplicate canonical cell id")
    payload = {
        "schema": "grand-bruxelles-registered-cell-manifest-index-v1",
        "production_base_sha": production_base_sha,
        "destination_readiness": "REGISTERED_CELL_INDEX_EVIDENCE_ONLY",
        "registered_cell_count": len(entries),
        "entries": entries,
        "runtime_directory_scan_authorized": False,
        "road_crosswalk_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    }
    semantic = {k: v for k, v in payload.items() if k != "production_base_sha"}
    payload["semantic_sha256"] = _canonical_sha(semantic)
    return payload


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest-dir", required=True)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--production-base-sha", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    payload = build(Path(args.manifest_dir), Path(args.repo_root), args.production_base_sha)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    print(f"REGISTERED_CELL_MANIFEST_INDEX_OK count={payload['registered_cell_count']} semantic={payload['semantic_sha256']}")


if __name__ == "__main__":
    main()
