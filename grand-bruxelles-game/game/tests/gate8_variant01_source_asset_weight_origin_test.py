#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import sys
import zipfile
from pathlib import Path

ASSET_ZIP_SHA256 = "6b1d673e4c1fd169372d3a74fe174d9c185069c1f55ff6bf6b224f6655e4b67a"
SPORTSUIT_ROOT = "clothes/female_sportsuit01/"
MHCLO_PATH = SPORTSUIT_ROOT + "female_sportsuit01.mhclo"
OBJ_PATH = SPORTSUIT_ROOT + "female_sportsuit01.obj"
MHW_PATH = SPORTSUIT_ROOT + "female_sportsuit01.mhw"
MHCLO_SHA256 = "6df057d3116db93afbbbb6d692f92cce84aa16db699f47dd14e825d07c6fd42f"
OBJ_SHA256 = "fd529bb8dd6a994c1e9a3fb2fd8b236f52c0cc7cebb1f6fd9328953d9df6d6ff"
ENDPOINTS = (486, 601)
EXPECTED_PROXY_ROWS = {
    486: {
        "body_vertices": [15673, 15666, 15667],
        "barycentric": [1.07592, -0.01267, -0.06324],
        "offset": [0.10407, -0.08036, 0.01272],
    },
    601: {
        "body_vertices": [15947, 15583, 15871],
        "barycentric": [0.22473, 0.62788, 0.14739],
        "offset": [-0.27069, -0.08918, -0.03483],
    },
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_path(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_proxy_rows(text: str) -> list[dict[str, object]]:
    lines = text.splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if line.strip() == "verts 0") + 1
    except StopIteration as exc:
        raise RuntimeError("sportsuit mhclo has no 'verts 0' proxy table") from exc

    rows: list[dict[str, object]] = []
    for raw in lines[start:]:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 9:
            break
        try:
            body_vertices = [int(parts[i]) for i in range(3)]
            barycentric = [float(parts[i]) for i in range(3, 6)]
            offset = [float(parts[i]) for i in range(6, 9)]
        except ValueError:
            break
        rows.append(
            {
                "body_vertices": body_vertices,
                "barycentric": barycentric,
                "offset": offset,
            }
        )
    return rows


def close_vec(actual: list[float], expected: list[float], tol: float = 1e-5) -> bool:
    return len(actual) == len(expected) and all(abs(a - b) <= tol for a, b in zip(actual, expected))


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: gate8_variant01_source_asset_weight_origin_test.py <asset_zip> <result_json>", file=sys.stderr)
        return 2

    asset_zip = Path(sys.argv[1]).resolve()
    result_path = Path(sys.argv[2]).resolve()
    if not asset_zip.is_file():
        raise RuntimeError(f"asset zip missing: {asset_zip}")
    if sha256_path(asset_zip) != ASSET_ZIP_SHA256:
        raise RuntimeError("pinned Gate-8 CC0 asset pack SHA-256 drifted")

    with zipfile.ZipFile(asset_zip) as zf:
        names = set(zf.namelist())
        required = {MHCLO_PATH, OBJ_PATH}
        missing = required - names
        if missing:
            raise RuntimeError(f"sportsuit source bundle incomplete: {sorted(missing)}")
        mhclo = zf.read(MHCLO_PATH)
        obj = zf.read(OBJ_PATH)
        if sha256_bytes(mhclo) != MHCLO_SHA256:
            raise RuntimeError("female_sportsuit01.mhclo content drifted")
        if sha256_bytes(obj) != OBJ_SHA256:
            raise RuntimeError("female_sportsuit01.obj content drifted")
        explicit_mhw_present = MHW_PATH in names

    text = mhclo.decode("utf-8")
    license_markers = [
        "explicitly released as CC0",
        "Copyright (C) 2020 Data Collection AB",
        "Copyright (C) 2020 Joel Palmius",
        "Copyright (C) 2020 Jonas Hauquier",
        "uuid e38d3a5b-718f-41d5-8404-299def30b43f",
        "basemesh hm08",
        "name female_sportsuit01",
    ]
    missing_markers = [marker for marker in license_markers if marker not in text]
    if missing_markers:
        raise RuntimeError(f"sportsuit provenance/license markers drifted: {missing_markers}")

    rows = parse_proxy_rows(text)
    if len(rows) != 1797:
        raise RuntimeError(f"expected 1797 sportsuit proxy rows, got {len(rows)}")

    endpoint_rows: dict[str, object] = {}
    for endpoint in ENDPOINTS:
        row = rows[endpoint]
        expected = EXPECTED_PROXY_ROWS[endpoint]
        if row["body_vertices"] != expected["body_vertices"]:
            raise RuntimeError(f"proxy body-vertex mapping drifted at sportsuit vertex {endpoint}: {row}")
        if not close_vec(row["barycentric"], expected["barycentric"]):
            raise RuntimeError(f"proxy interpolation coefficients drifted at sportsuit vertex {endpoint}: {row}")
        if not close_vec(row["offset"], expected["offset"]):
            raise RuntimeError(f"proxy offset drifted at sportsuit vertex {endpoint}: {row}")
        coefficient_sum = sum(row["barycentric"])
        if abs(coefficient_sum - 1.0) > 2e-5:
            raise RuntimeError(f"proxy coefficient sum invalid at sportsuit vertex {endpoint}: {coefficient_sum}")
        endpoint_rows[str(endpoint)] = {
            **row,
            "barycentric_sum": coefficient_sum,
        }

    if explicit_mhw_present:
        diagnostic_state = "SPORTSUIT_EXPLICIT_WEIGHT_FILE_PRESENT"
        next_safe_axis = "TRACE_EXPLICIT_SPORTSUIT_WEIGHT_FILE"
    else:
        diagnostic_state = "SPORTSUIT_HAS_PROXY_MAPPING_BUT_NO_EXPLICIT_MHW"
        next_safe_axis = "TRACE_PROXY_WEIGHT_INTERPOLATION_IMPLEMENTATION"

    result = {
        "format": "grand-bruxelles-gate8-variant01-source-asset-weight-origin-v1",
        "diagnostic_state": diagnostic_state,
        "next_safe_axis": next_safe_axis,
        "asset_zip_sha256": ASSET_ZIP_SHA256,
        "sportsuit_mhclo_sha256": MHCLO_SHA256,
        "sportsuit_obj_sha256": OBJ_SHA256,
        "sportsuit_uuid": "e38d3a5b-718f-41d5-8404-299def30b43f",
        "sportsuit_basemesh": "hm08",
        "sportsuit_proxy_vertex_count": len(rows),
        "explicit_mhw_present": explicit_mhw_present,
        "source_edge": list(ENDPOINTS),
        "endpoint_proxy_rows": endpoint_rows,
        "license": "CC0",
        "canonical_asset_mutation": False,
        "canonical_generator_mutation": False,
        "runtime_npc_mutation": False,
        "production_activation_allowed": False,
        "visual_approval_allowed": False,
    }
    result_path.parent.mkdir(parents=True, exist_ok=True)
    result_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
