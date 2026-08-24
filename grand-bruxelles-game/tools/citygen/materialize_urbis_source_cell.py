#!/usr/bin/env python3
"""Materialize one missing regional source cell from official UrbIS WFS layers.

The scheduled CityGen path materializes the complete source-only base-city contract:
Buildings, StreetSurfaces, StreetAxes, TramNetwork and TrainNetwork. Buildings keep
canonical 500 m ownership; the other layers remain official bbox-intersection source
records and are deliberately left unclipped until deterministic runtime compilation.

This module never creates or promotes Godot/runtime geometry.
"""
from __future__ import annotations

import argparse, hashlib, json, math, sys, time, urllib.parse, urllib.request
from pathlib import Path
from typing import Any, Callable

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))
from bootstrap_cell_maturity import build as build_maturity

CRS = "EPSG:31370"
WFS_URL = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
LAYER = "urbisvector:Buildings"
USER_AGENT = "Grand-Bruxelles-Game/1.0 (+https://github.com/Chatnoir01/Chatnoir01)"
CELL_SIZE = 500.0
BASE_CITY_LAYERS: tuple[tuple[str, str, str], ...] = (
    ("buildings", "urbisvector:Buildings", "raw/buildings.geojson"),
    ("street_surfaces", "urbisvector:StreetSurfaces", "raw/street_surfaces.geojson"),
    ("street_axes", "urbisvector:StreetAxes", "raw/street_axes.geojson"),
    ("tram_network", "urbisvector:TramNetwork", "raw/tram_network.geojson"),
    ("train_network", "urbisvector:TrainNetwork", "raw/train_network.geojson"),
)


def digest(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


def _token(value: float) -> str:
    return str(int(round(value))) if math.isclose(value, round(value), abs_tol=1e-8) else f"{value:.3f}".rstrip("0").rstrip(".").replace(".", "p")


def canonical_cell_id(e: float, n: float, size: float = CELL_SIZE) -> str:
    return f"bxl-e{_token(e)}-n{_token(n)}-s{_token(size)}"


def parse_bbox(raw: str) -> tuple[float, float, float, float]:
    parts = tuple(float(v.strip()) for v in raw.split(","))
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("bbox must be minE,minN,maxE,maxN")
    if not (parts[0] < parts[2] and parts[1] < parts[3]):
        raise argparse.ArgumentTypeError("invalid bbox extent")
    return parts


def _validate(cell_id: str, bbox: tuple[float, float, float, float]) -> None:
    min_e, min_n, max_e, max_n = bbox
    if min(bbox) < 10_000:
        raise ValueError("bbox does not look like EPSG:31370 metres")
    if not math.isclose(max_e - min_e, CELL_SIZE, abs_tol=1e-6) or not math.isclose(max_n - min_n, CELL_SIZE, abs_tol=1e-6):
        raise ValueError("source materializer only accepts canonical 500 m cells")
    expected = canonical_cell_id(min_e, min_n, CELL_SIZE)
    if cell_id != expected:
        raise ValueError(f"cell id/bbox mismatch: expected {expected}, got {cell_id}")


def _ring_centroid(ring: Any) -> tuple[float, float, float] | None:
    if not isinstance(ring, list):
        return None
    points = []
    for p in ring:
        if not isinstance(p, list) or len(p) < 2:
            return None
        x, y = float(p[0]), float(p[1])
        if not math.isfinite(x) or not math.isfinite(y):
            return None
        points.append((x, y))
    if len(points) >= 2 and points[0] == points[-1]:
        points.pop()
    if len(points) < 3:
        return None
    twice_area = 0.0
    cx = 0.0
    cy = 0.0
    for i, (x0, y0) in enumerate(points):
        x1, y1 = points[(i + 1) % len(points)]
        cross = x0 * y1 - x1 * y0
        twice_area += cross
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross
    if abs(twice_area) < 1e-9:
        return (sum(x for x, _ in points) / len(points), sum(y for _, y in points) / len(points), 0.0)
    return (cx / (3.0 * twice_area), cy / (3.0 * twice_area), abs(twice_area) / 2.0)


def _polygon_centroid(coords: Any) -> tuple[float, float, float] | None:
    if not isinstance(coords, list) or not coords:
        return None
    return _ring_centroid(coords[0])


def _centroid(feature: dict[str, Any]) -> tuple[float, float] | None:
    geom = feature.get("geometry") or {}
    coords = geom.get("coordinates") or []
    kind = geom.get("type")
    if kind == "Polygon":
        result = _polygon_centroid(coords)
        return None if result is None else (result[0], result[1])
    if kind != "MultiPolygon" or not isinstance(coords, list) or not coords:
        return None
    parts = []
    for polygon in coords:
        result = _polygon_centroid(polygon)
        if result is None:
            return None
        parts.append(result)
    weighted = [part for part in parts if part[2] > 0.0]
    if weighted:
        total = sum(part[2] for part in weighted)
        return (
            sum(part[0] * part[2] for part in weighted) / total,
            sum(part[1] * part[2] for part in weighted) / total,
        )
    return (sum(part[0] for part in parts) / len(parts), sum(part[1] for part in parts) / len(parts))


def owner_cell(feature: dict[str, Any]) -> str | None:
    center = _centroid(feature)
    if center is None:
        return None
    return canonical_cell_id(
        math.floor(center[0] / CELL_SIZE) * CELL_SIZE,
        math.floor(center[1] / CELL_SIZE) * CELL_SIZE,
        CELL_SIZE,
    )


def _feature_key(feature: dict[str, Any]) -> str:
    return str((feature.get("properties") or {}).get("INSPIRE_ID") or feature.get("id") or digest(feature))


def _request_layer_once(layer_name: str, bbox: tuple[float, float, float, float], retries: int) -> dict[str, Any]:
    params = {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetFeature",
        "typeNames": layer_name,
        "outputFormat": "application/json",
        "srsName": CRS,
        "bbox": f"{bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]},{CRS}",
    }
    url = WFS_URL + "?" + urllib.parse.urlencode(params)
    last: Exception | None = None
    attempts = max(1, retries)
    for attempt in range(1, attempts + 1):
        request = urllib.request.Request(
            url,
            headers={
                "User-Agent": USER_AGENT,
                "Accept": "application/geo+json, application/json",
                "Accept-Encoding": "identity",
                "Cache-Control": "no-cache",
                "Connection": "close",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                raw = response.read()
                content_length = response.headers.get("Content-Length") if getattr(response, "headers", None) is not None else None
                if content_length:
                    expected = int(content_length)
                    if len(raw) != expected:
                        raise RuntimeError(f"truncated UrbIS WFS response for {layer_name}: expected={expected} got={len(raw)}")
                payload = json.loads(raw.decode("utf-8"))
            if payload.get("type") != "FeatureCollection" or not isinstance(payload.get("features"), list):
                raise RuntimeError(f"unexpected UrbIS WFS payload for {layer_name}")
            return payload
        except Exception as exc:
            last = exc
            if attempt < attempts:
                time.sleep(min(12, 2**attempt))
    raise RuntimeError(f"failed to fetch official {layer_name} layer: {last}")


def _quarter_bboxes(bbox: tuple[float, float, float, float]) -> tuple[tuple[float, float, float, float], ...]:
    min_e, min_n, max_e, max_n = bbox
    mid_e = (min_e + max_e) / 2.0
    mid_n = (min_n + max_n) / 2.0
    return (
        (min_e, min_n, mid_e, mid_n),
        (mid_e, min_n, max_e, mid_n),
        (min_e, mid_n, mid_e, max_n),
        (mid_e, mid_n, max_e, max_n),
    )


def _merge_feature_collections(documents: list[dict[str, Any]]) -> dict[str, Any]:
    if not documents:
        raise RuntimeError("cannot merge empty UrbIS WFS fallback")
    merged: dict[str, Any] = {k: v for k, v in documents[0].items() if k not in {"features", "numberReturned", "numberMatched"}}
    features_by_key: dict[str, dict[str, Any]] = {}
    for document in documents:
        if document.get("type") != "FeatureCollection" or not isinstance(document.get("features"), list):
            raise RuntimeError("invalid UrbIS WFS quadrant payload")
        for feature in document.get("features") or []:
            if not isinstance(feature, dict):
                raise RuntimeError("invalid UrbIS WFS feature in quadrant payload")
            features_by_key[_feature_key(feature)] = feature
    features = sorted(features_by_key.values(), key=_feature_key)
    merged["type"] = "FeatureCollection"
    merged["features"] = features
    merged["numberReturned"] = len(features)
    merged["numberMatched"] = len(features)
    return merged


def request_layer(layer_name: str, bbox: tuple[float, float, float, float], retries: int = 6) -> dict[str, Any]:
    allowed = {wfs_name for _, wfs_name, _ in BASE_CITY_LAYERS}
    if layer_name not in allowed:
        raise ValueError(f"unsupported UrbIS layer: {layer_name}")
    try:
        return _request_layer_once(layer_name, bbox, retries)
    except RuntimeError as full_bbox_error:
        # Some UrbIS WFS responses are occasionally truncated while still
        # returning HTTP 200. Retry a bounded, deterministic 2x2 subdivision.
        # Every quadrant remains official WFS data; if any quadrant is invalid,
        # the cell stays pending rather than fabricating or partially accepting it.
        documents: list[dict[str, Any]] = []
        quadrant_retries = max(2, min(4, retries // 2))
        try:
            for quadrant in _quarter_bboxes(bbox):
                documents.append(_request_layer_once(layer_name, quadrant, quadrant_retries))
        except RuntimeError as quadrant_error:
            raise RuntimeError(
                f"failed to fetch official {layer_name} layer after full-bbox and quadrant retries: "
                f"full={full_bbox_error}; quadrant={quadrant_error}"
            ) from quadrant_error
        return _merge_feature_collections(documents)


def request_buildings(bbox: tuple[float, float, float, float], retries: int = 6) -> dict[str, Any]:
    return request_layer(LAYER, bbox, retries)


def _write(path: Path, value: dict[str, Any], compact: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(value, ensure_ascii=False, separators=(",", ":")) if compact else json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True)
    path.write_text(text + "\n", encoding="utf-8")


def _source_document(document: dict[str, Any], *, layer_name: str, bbox: tuple[float, float, float, float], cell_id: str, features: list[dict[str, Any]], ownership: str) -> dict[str, Any]:
    source = {k: v for k, v in document.items() if k not in {"features", "numberReturned"}}
    source["type"] = "FeatureCollection"
    source["features"] = features
    source["numberReturned"] = len(features)
    source["grand_bruxelles_source"] = {
        "authority": "Paradigm / Brussels-Capital Region",
        "service": WFS_URL,
        "layer": layer_name,
        "crs": CRS,
        "bbox": list(bbox),
        "cell_id": cell_id,
        "ownership": ownership,
    }
    return source


def _materialize_buildings(cell_id: str, bbox: tuple[float, float, float, float], output_dir: Path, document: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(document, dict) or document.get("type") != "FeatureCollection" or not isinstance(document.get("features"), list):
        raise ValueError("fetcher did not return a FeatureCollection")
    kept: list[dict[str, Any]] = []
    ownership_filtered = 0
    invalid_ownership = 0
    for feature in document.get("features") or []:
        owner = owner_cell(feature)
        if owner is None:
            kept.append(feature)
            invalid_ownership += 1
        elif owner == cell_id:
            kept.append(feature)
        else:
            ownership_filtered += 1
    kept.sort(key=_feature_key)
    source = _source_document(
        document,
        layer_name=LAYER,
        bbox=bbox,
        cell_id=cell_id,
        features=kept,
        ownership="polygon_or_multipolygon_centroid_global_500m_cell",
    )
    _write(output_dir / "raw" / "buildings.geojson", source, True)
    return {
        "wfs_name": LAYER,
        "features": len(kept),
        "ownership_filtered": ownership_filtered,
        "invalid_ownership_features": invalid_ownership,
        "ownership": "canonical_centroid_global_500m_cell",
        "file": "raw/buildings.geojson",
    }


def _materialize_intersection_layer(*, logical_name: str, wfs_name: str, relative_file: str, cell_id: str, bbox: tuple[float, float, float, float], output_dir: Path, document: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(document, dict) or document.get("type") != "FeatureCollection" or not isinstance(document.get("features"), list):
        raise ValueError(f"{logical_name} fetcher did not return a FeatureCollection")
    features = list(document.get("features") or [])
    features.sort(key=_feature_key)
    source = _source_document(
        document,
        layer_name=wfs_name,
        bbox=bbox,
        cell_id=cell_id,
        features=features,
        ownership="bbox_intersection_source_unclipped",
    )
    _write(output_dir / relative_file, source, True)
    return {
        "wfs_name": wfs_name,
        "features": len(features),
        "ownership": "bbox_intersection_source_unclipped",
        "file": relative_file,
    }


def _finalize_manifest(cell_id: str, bbox: tuple[float, float, float, float], output_dir: Path, layers: dict[str, Any]) -> dict[str, Any]:
    manifest: dict[str, Any] = {
        "format": "grand-bruxelles-urbis-source-cell-v1",
        "cell_id": cell_id,
        "crs": CRS,
        "bbox": list(bbox),
        "layers": layers,
        "promotion": "source_only_no_runtime_mutation",
    }
    manifest["source_digest"] = digest(manifest)
    _write(output_dir / "manifest.json", manifest, False)
    maturity = build_maturity(output_dir)
    _write(output_dir / "maturity.json", maturity, False)
    return manifest


def materialize(cell_id: str, bbox: tuple[float, float, float, float], output_dir: Path, fetcher: Callable[[tuple[float, float, float, float]], dict[str, Any]]) -> dict[str, Any]:
    """Backwards-compatible buildings-only source materializer used by focused tests."""
    _validate(cell_id, bbox)
    building_layer = _materialize_buildings(cell_id, bbox, output_dir, fetcher(bbox))
    return _finalize_manifest(cell_id, bbox, output_dir, {"buildings": building_layer})


def materialize_base_city(cell_id: str, bbox: tuple[float, float, float, float], output_dir: Path, layer_fetcher: Callable[[str, tuple[float, float, float, float]], dict[str, Any]]) -> dict[str, Any]:
    """Materialize all official source layers needed by the regional base-city compiler."""
    _validate(cell_id, bbox)
    layers: dict[str, Any] = {}
    for logical_name, wfs_name, relative_file in BASE_CITY_LAYERS:
        document = layer_fetcher(wfs_name, bbox)
        if logical_name == "buildings":
            layers[logical_name] = _materialize_buildings(cell_id, bbox, output_dir, document)
        else:
            layers[logical_name] = _materialize_intersection_layer(
                logical_name=logical_name,
                wfs_name=wfs_name,
                relative_file=relative_file,
                cell_id=cell_id,
                bbox=bbox,
                output_dir=output_dir,
                document=document,
            )
    return _finalize_manifest(cell_id, bbox, output_dir, layers)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cell-id", required=True)
    ap.add_argument("--bbox", type=parse_bbox, required=True)
    ap.add_argument("--output-dir", type=Path, required=True)
    ap.add_argument("--retries", type=int, default=6)
    args = ap.parse_args()
    manifest = materialize_base_city(
        args.cell_id,
        args.bbox,
        args.output_dir,
        lambda layer_name, bbox: request_layer(layer_name, bbox, args.retries),
    )
    counts = ",".join(f"{name}={spec['features']}" for name, spec in manifest["layers"].items())
    print(
        f"MATERIALIZE_URBIS_SOURCE_CELL_OK cell={args.cell_id} layers={len(manifest['layers'])} "
        f"{counts} digest={manifest['source_digest']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
