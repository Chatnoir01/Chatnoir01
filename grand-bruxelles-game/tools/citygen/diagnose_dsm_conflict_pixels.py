#!/usr/bin/env python3
"""Read-only pixel autopsy for CityGen DSM-vs-UrbIS3D height conflicts.

This diagnostic never decides which source is correct. It measures how the
validated DSM-DTM raster values are distributed inside the authoritative
building footprint, including edge/interior zones and connected components.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
from collections import deque
from pathlib import Path
from typing import Any

SCHEMA = "grand-bruxelles-citygen-dsm-conflict-pixel-autopsy-v1"
VALIDATION_FORMAT = "grand-bruxelles-citygen-secondary-height-validation-v1"
CRS = "EPSG:31370"

_HERE = Path(__file__).resolve().parent
_POLICY_PATH = _HERE / "build_semantic_dsm_height_comparison.py"
_DERIVE_PATH = _HERE / "derive_cell_building_height_candidates.py"


def _load_module(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load policy module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _finite(value: Any) -> float | None:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return None
    return out if math.isfinite(out) else None


def _fraction(part: int, whole: int) -> float:
    return float(part / whole) if whole else 0.0


def _percentile(values: Any, q: float) -> float | None:
    try:
        import numpy as np  # type: ignore
    except ImportError as exc:
        raise RuntimeError("numpy is required for DSM conflict diagnostics") from exc
    arr = np.asarray(values, dtype="float64")
    arr = arr[np.isfinite(arr)]
    if arr.size == 0:
        return None
    return round(float(np.percentile(arr, q)), 6)


def _erode(mask: Any, iterations: int) -> Any:
    try:
        import numpy as np  # type: ignore
    except ImportError as exc:
        raise RuntimeError("numpy is required for DSM conflict diagnostics") from exc
    out = np.asarray(mask, dtype=bool).copy()
    iterations = max(0, int(iterations))
    for _ in range(iterations):
        if not np.any(out):
            break
        padded = np.pad(out, 1, mode="constant", constant_values=False)
        eroded = np.ones(out.shape, dtype=bool)
        for dy in range(3):
            for dx in range(3):
                eroded &= padded[dy:dy + out.shape[0], dx:dx + out.shape[1]]
        out = eroded
    return out


def _component_stats(mask: Any, valid_count: int) -> dict[str, Any]:
    try:
        import numpy as np  # type: ignore
    except ImportError as exc:
        raise RuntimeError("numpy is required for DSM conflict diagnostics") from exc
    src = np.asarray(mask, dtype=bool)
    height, width = src.shape
    seen = np.zeros(src.shape, dtype=bool)
    sizes: list[int] = []
    for y in range(height):
        for x in range(width):
            if not src[y, x] or seen[y, x]:
                continue
            seen[y, x] = True
            queue: deque[tuple[int, int]] = deque([(y, x)])
            size = 0
            while queue:
                cy, cx = queue.popleft()
                size += 1
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if dx == 0 and dy == 0:
                            continue
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < height and 0 <= nx < width and src[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            queue.append((ny, nx))
            sizes.append(size)
    band_count = int(np.count_nonzero(src))
    largest = max(sizes, default=0)
    return {
        "component_count": len(sizes),
        "largest_component_pixels": largest,
        "largest_component_fraction_of_valid": _fraction(largest, valid_count),
        "largest_component_fraction_of_band": _fraction(largest, band_count),
    }


def _band_summary(mask: Any, valid_count: int) -> dict[str, Any]:
    try:
        import numpy as np  # type: ignore
    except ImportError as exc:
        raise RuntimeError("numpy is required for DSM conflict diagnostics") from exc
    pixel_count = int(np.count_nonzero(mask))
    return {
        "pixel_count": pixel_count,
        "fraction_of_valid": _fraction(pixel_count, valid_count),
        **_component_stats(mask, valid_count),
    }


def _zone_summary(zone: Any, primary: Any, semantic: Any, other: Any, overlap: Any) -> dict[str, Any]:
    try:
        import numpy as np  # type: ignore
    except ImportError as exc:
        raise RuntimeError("numpy is required for DSM conflict diagnostics") from exc
    zone = np.asarray(zone, dtype=bool)
    count = int(np.count_nonzero(zone))
    primary_count = int(np.count_nonzero(zone & primary))
    semantic_count = int(np.count_nonzero(zone & semantic))
    other_count = int(np.count_nonzero(zone & other))
    overlap_count = int(np.count_nonzero(zone & overlap))
    return {
        "pixel_count": count,
        "primary_band_pixels": primary_count,
        "semantic_band_pixels": semantic_count,
        "other_band_pixels": other_count,
        "overlap_band_pixels": overlap_count,
        "primary_band_fraction": _fraction(primary_count, count),
        "semantic_band_fraction": _fraction(semantic_count, count),
        "other_band_fraction": _fraction(other_count, count),
        "overlap_band_fraction": _fraction(overlap_count, count),
    }


def analyze_grid(
    inside: Any,
    deltas: Any,
    *,
    primary_height_m: float,
    semantic_height_m: float,
    strong_delta_m: float,
    erosion_pixels: int = 2,
) -> dict[str, Any]:
    """Measure raster support for two conflicting height hypotheses.

    The result is descriptive only. It deliberately contains no winning-source
    or inferred-cause field.
    """
    try:
        import numpy as np  # type: ignore
    except ImportError as exc:
        raise RuntimeError("numpy is required for DSM conflict diagnostics") from exc

    inside_arr = np.asarray(inside, dtype=bool)
    delta_arr = np.asarray(deltas, dtype="float64")
    if inside_arr.shape != delta_arr.shape or inside_arr.ndim != 2:
        raise ValueError("inside/delta grids must be same-shape 2D arrays")
    primary_height = _finite(primary_height_m)
    semantic_height = _finite(semantic_height_m)
    strong_delta = _finite(strong_delta_m)
    if primary_height is None or semantic_height is None or strong_delta is None or strong_delta <= 0.0:
        raise ValueError("height hypotheses and strong delta must be finite; strong delta must be positive")

    valid = inside_arr & np.isfinite(delta_arr)
    valid_count = int(np.count_nonzero(valid))
    primary = valid & (np.abs(delta_arr - primary_height) <= strong_delta)
    semantic = valid & (np.abs(delta_arr - semantic_height) <= strong_delta)
    overlap = primary & semantic
    other = valid & ~primary & ~semantic

    interior = _erode(valid, erosion_pixels)
    edge = valid & ~interior

    finite_values = delta_arr[valid]
    distribution = {
        "min": _percentile(finite_values, 0),
        "p10": _percentile(finite_values, 10),
        "p25": _percentile(finite_values, 25),
        "p50": _percentile(finite_values, 50),
        "p75": _percentile(finite_values, 75),
        "p90": _percentile(finite_values, 90),
        "p95": _percentile(finite_values, 95),
        "max": _percentile(finite_values, 100),
        "mean": round(float(np.mean(finite_values)), 6) if finite_values.size else None,
    }
    return {
        "valid_pixel_count": valid_count,
        "strong_delta_m": strong_delta,
        "erosion_pixels": int(erosion_pixels),
        "distribution_m": distribution,
        "bands": {
            "primary": _band_summary(primary, valid_count),
            "semantic": _band_summary(semantic, valid_count),
            "overlap": _band_summary(overlap, valid_count),
            "other": _band_summary(other, valid_count),
        },
        "zones": {
            "edge": _zone_summary(edge, primary, semantic, other, overlap),
            "interior": _zone_summary(interior, primary, semantic, other, overlap),
        },
        "policy": {
            "read_only": True,
            "cause_inference_allowed": False,
            "automatic_resolution_allowed": False,
            "runtime_approved": False,
            "thresholds_changed": False,
        },
    }


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _feature_map(buildings: dict[str, Any]) -> dict[str, dict[str, Any]]:
    derive = _load_module(_DERIVE_PATH, "citygen_height_derivation_for_conflict_autopsy")
    rows: dict[str, dict[str, Any]] = {}
    features = buildings.get("features") or []
    if not isinstance(features, list):
        raise ValueError("buildings GeoJSON features must be a list")
    for feature in features:
        if not isinstance(feature, dict):
            continue
        building_id = str(derive._stable_building_id(feature))
        if building_id in rows:
            raise ValueError(f"duplicate building footprint identity: {building_id}")
        rows[building_id] = feature
    return rows


def _sample_conflict(feature: dict[str, Any], dsm_path: Path, dtm_path: Path) -> tuple[Any, Any, float]:
    try:
        import numpy as np  # type: ignore
        import rasterio  # type: ignore
        from rasterio.errors import WindowError  # type: ignore
        from rasterio.features import geometry_mask, geometry_window  # type: ignore
    except ImportError as exc:
        raise RuntimeError("numpy and rasterio are required for DSM conflict diagnostics") from exc

    geometry = feature.get("geometry")
    if not isinstance(geometry, dict) or geometry.get("type") not in ("Polygon", "MultiPolygon"):
        raise ValueError("conflict building geometry must be Polygon or MultiPolygon")

    with rasterio.open(dsm_path) as dsm_src, rasterio.open(dtm_path) as dtm_src:
        if (
            dsm_src.transform != dtm_src.transform
            or dsm_src.width != dtm_src.width
            or dsm_src.height != dtm_src.height
        ):
            raise ValueError("DSM/DTM alignment changed before conflict autopsy")
        if not math.isclose(abs(float(dsm_src.res[0])), abs(float(dtm_src.res[0])), abs_tol=1e-12):
            raise ValueError("DSM/DTM x resolution mismatch")
        try:
            window = geometry_window(dsm_src, [geometry], pad_x=0, pad_y=0)
        except WindowError as exc:
            raise ValueError("conflict footprint does not intersect validated raster") from exc
        if window.width <= 0 or window.height <= 0:
            raise ValueError("conflict footprint produced empty raster window")
        dsm_arr = dsm_src.read(1, window=window, masked=True).astype("float64")
        dtm_arr = dtm_src.read(1, window=window, masked=True).astype("float64")
        if dsm_arr.shape != dtm_arr.shape:
            raise ValueError("paired DSM/DTM windows differ")
        transform = rasterio.windows.transform(window, dsm_src.transform)
        inside = geometry_mask(
            [geometry],
            out_shape=dsm_arr.shape,
            transform=transform,
            invert=True,
            all_touched=False,
        )
        dsm_plain = np.asarray(dsm_arr.filled(np.nan), dtype="float64")
        dtm_plain = np.asarray(dtm_arr.filled(np.nan), dtype="float64")
        valid_source = (
            (~np.ma.getmaskarray(dsm_arr))
            & (~np.ma.getmaskarray(dtm_arr))
            & np.isfinite(dsm_plain)
            & np.isfinite(dtm_plain)
            & (dsm_plain > -1.0e20)
            & (dtm_plain > -1.0e20)
        )
        inside_valid = inside & valid_source
        deltas = np.full(dsm_plain.shape, np.nan, dtype="float64")
        deltas[inside_valid] = dsm_plain[inside_valid] - dtm_plain[inside_valid]
        return inside_valid, deltas, abs(float(dsm_src.res[0]))


def build_report(
    buildings: dict[str, Any],
    validation: dict[str, Any],
    dsm_path: Path,
    dtm_path: Path,
) -> dict[str, Any]:
    if validation.get("format") != VALIDATION_FORMAT or validation.get("crs") != CRS:
        raise ValueError("unsupported secondary-height validation evidence")
    if validation.get("runtime_promotion_allowed") is not False:
        raise ValueError("secondary-height validation must forbid runtime promotion")
    if int(validation.get("runtime_approved_count", -1)) != 0:
        raise ValueError("secondary-height validation unexpectedly has runtime-approved candidates")

    policy = _load_module(_POLICY_PATH, "citygen_semantic_height_policy_for_conflict_autopsy")
    strong_delta_m = float(policy.STRONG_DELTA_M)
    if not math.isclose(strong_delta_m, 2.0, abs_tol=1e-12):
        raise ValueError(f"existing strong height threshold changed unexpectedly: {strong_delta_m}")

    features = _feature_map(buildings)
    candidates = validation.get("candidates") or []
    if not isinstance(candidates, list):
        raise ValueError("validation candidates must be a list")
    conflicts = [
        row for row in candidates
        if isinstance(row, dict) and row.get("secondary_status") == "blocked_conflict"
    ]
    if not conflicts:
        raise ValueError("no blocked height conflicts found")
    if any(row.get("runtime_approved") is not False for row in conflicts):
        raise ValueError("blocked conflict unexpectedly has runtime approval")

    records: list[dict[str, Any]] = []
    for row in sorted(conflicts, key=lambda item: str(item.get("building_id") or "")):
        building_id = str(row.get("building_id") or "")
        primary_height = _finite(row.get("candidate_height_m"))
        semantic_height = _finite(row.get("semantic_height_m"))
        if not building_id or primary_height is None or semantic_height is None:
            raise ValueError("blocked conflict missing finite source heights")
        feature = features.get(building_id)
        if feature is None:
            raise ValueError(f"blocked conflict footprint missing: {building_id}")

        inside, deltas, pixel_size_m = _sample_conflict(feature, dsm_path, dtm_path)
        grid = analyze_grid(
            inside,
            deltas,
            primary_height_m=primary_height,
            semantic_height_m=semantic_height,
            strong_delta_m=strong_delta_m,
            erosion_pixels=2,
        )
        if grid["valid_pixel_count"] <= 0:
            raise ValueError(f"blocked conflict has no valid DSM-DTM pixels: {building_id}")
        records.append({
            "building_id": building_id,
            "primary_height_m": primary_height,
            "primary_confidence": str(row.get("confidence") or ""),
            "semantic_height_m": semantic_height,
            "secondary_abs_delta_m": _finite(row.get("abs_delta_m")),
            "semantic_match_score": _finite(row.get("semantic_match_score")),
            "semantic_match_margin": _finite(row.get("semantic_match_margin")),
            "raster_pixel_size_m": pixel_size_m,
            "edge_erosion_pixels": 2,
            "edge_erosion_nominal_m": round(pixel_size_m * 2.0, 6),
            "grid": grid,
            "interpretation": "descriptive_pixel_distribution_only",
            "cause_inference_allowed": False,
            "automatic_resolution_allowed": False,
            "runtime_approved": False,
        })

    measured = sum(1 for row in records if row["grid"]["valid_pixel_count"] > 0)
    return {
        "schema": SCHEMA,
        "cell_id": str(validation.get("cell_id") or ""),
        "crs": CRS,
        "source_validation_digest": validation.get("validation_digest"),
        "strong_delta_m": strong_delta_m,
        "counts": {
            "conflict_candidates": len(conflicts),
            "measured_conflicts": measured,
        },
        "records": records,
        "policy": {
            "read_only": True,
            "cause_inference_allowed": False,
            "automatic_resolution_allowed": False,
            "runtime_promotion_allowed": False,
            "runtime_approval": False,
            "thresholds_changed": False,
            "edge_erosion_pixels": 2,
            "note": "pixel pattern is diagnostic evidence only and must not be converted into a causal label or source winner automatically",
        },
        "runtime_approved_count": 0,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--buildings", required=True, type=Path)
    parser.add_argument("--validation", required=True, type=Path)
    parser.add_argument("--dsm", required=True, type=Path)
    parser.add_argument("--dtm", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    buildings = _read_json(args.buildings)
    if buildings.get("type") != "FeatureCollection":
        raise ValueError("buildings input must be a GeoJSON FeatureCollection")
    validation = _read_json(args.validation)
    report = build_report(buildings, validation, args.dsm, args.dtm)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(
        "DSM_CONFLICT_PIXEL_AUTOPSY_OK",
        report["cell_id"],
        f"conflicts={report['counts']['conflict_candidates']}",
        f"measured={report['counts']['measured_conflicts']}",
        "automatic_resolution=false",
        "runtime_promotion=false",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
