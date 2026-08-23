#!/usr/bin/env python3
import argparse
import base64
import json
import lzma
import math
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OSM_PATH = ROOT / "data/osm/vertical_slice_01.game.json"
GEOMETRY_MANIFEST_PATH = ROOT / "data/provenance/brussels_mobility_sidewalk_corridor_geometry_manifest.json"
GEOMETRY_DIR = ROOT / "data/provenance/brussels_mobility_sidewalk_corridor_geometry"
GEOREF_PATH = ROOT / "data/provenance/brussels_sidewalk_overlap_georef.json"

MIDI_ANCHOR = (-668.5, 627.84)
BOURSE_ANCHOR = (81.54, -664.58)
MIDI_DETAIL_RADIUS_M = 300.0
BOURSE_DETAIL_RADIUS_M = 180.0
MAX_ROAD_SEGMENTS = 850
TARGET_SAMPLE_SPACING_M = 0.25
SPATIAL_BIN_M = 50.0
EXPECTED_GENERIC_SIDEWALKS = 430
EXPECTED_OFFICIAL_FEATURES = 3158


def _load(path: Path):
    if not path.exists():
        raise AssertionError(f"required overlap input missing: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def _distance(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def _road_width(road):
    width = float(road.get("width", 4.5))
    road_class = str(road.get("class", ""))
    if road_class == "primary":
        return max(width, 10.5)
    if road_class == "secondary":
        return max(width, 8.5)
    if road_class == "tertiary":
        return max(width, 7.2)
    return width


def _in_detail_zone(point):
    return (
        _distance(point, MIDI_ANCHOR) <= MIDI_DETAIL_RADIUS_M
        or _distance(point, BOURSE_ANCHOR) <= BOURSE_DETAIL_RADIUS_M
    )


def _generic_sidewalks(osm):
    assert osm.get("format") == "grand-bruxelles-osm-v1"
    assert osm.get("source") == "OpenStreetMap contributors via Overpass API"
    assert osm.get("license") == "ODbL-1.0"
    surfaces = []
    segment_count = 0
    for road in osm.get("roads", []):
        if segment_count >= MAX_ROAD_SEGMENTS:
            break
        points = road.get("points", [])
        width = _road_width(road)
        road_class = str(road.get("class", ""))
        for index in range(len(points) - 1):
            if segment_count >= MAX_ROAD_SEGMENTS:
                break
            start = (float(points[index][0]), float(points[index][1]))
            finish = (float(points[index + 1][0]), float(points[index + 1][1]))
            dx, dz = finish[0] - start[0], finish[1] - start[1]
            length = math.hypot(dx, dz)
            if length < 0.75:
                continue
            midpoint = ((start[0] + finish[0]) * 0.5, (start[1] + finish[1]) * 0.5)
            if _in_detail_zone(midpoint) and bool(road.get("drivable", False)) and length >= 1.0:
                direction = (dx / length, dz / length)
                perpendicular = (-direction[1], direction[0])
                sidewalk_width = 2.55 if road_class in ("primary", "secondary") else 1.85
                offset = width * 0.5 + sidewalk_width * 0.5 + 0.10
                for side in (-1.0, 1.0):
                    center = (
                        midpoint[0] + perpendicular[0] * offset * side,
                        midpoint[1] + perpendicular[1] * offset * side,
                    )
                    surfaces.append({
                        "osm_id": int(road.get("osm_id", 0)),
                        "segment_index": index,
                        "side": int(side),
                        "center": center,
                        "direction": direction,
                        "perpendicular": perpendicular,
                        "length_m": length,
                        "width_m": sidewalk_width,
                        "road_class": road_class,
                    })
            segment_count += 1
    assert len(surfaces) == EXPECTED_GENERIC_SIDEWALKS, (
        f"generic sidewalk reconstruction drifted: {len(surfaces)} != {EXPECTED_GENERIC_SIDEWALKS}"
    )
    return surfaces


def _load_official_features(manifest):
    assert manifest["source_snapshot"]["feature_count"] == EXPECTED_OFFICIAL_FEATURES
    assert manifest["source"]["layer"] == "bm_urbis:urbadm_ssw"
    assert manifest["source"]["license"] == "CC0-1.0"
    assert manifest["source"]["crs"] == "EPSG:31370"
    features = []
    for chunk in manifest["chunks"]:
        encoded = (GEOMETRY_DIR / chunk["file"]).read_bytes()
        canonical = lzma.decompress(base64.b64decode(encoded, validate=False), format=lzma.FORMAT_XZ)
        payload = json.loads(canonical)
        features.extend(payload["features"])
    assert len(features) == EXPECTED_OFFICIAL_FEATURES
    return features


def _transformer(georef):
    assert georef["schema"] == "grand-bruxelles-sidewalk-overlap-georef-v1"
    assert georef["horizontal_only"] is True
    assert georef["policy"]["overlap_qa_authorized"] is True
    assert georef["policy"]["runtime_use_authorized"] is False
    assert georef["curb_height_authorized"] is False
    assert georef["vertical_profile_authorized"] is False
    x = georef["method"]["affine"]["x_from_E_N"]
    z = georef["method"]["affine"]["z_from_E_N"]
    def transform(point):
        e, n = float(point[0]), float(point[1])
        return (x[0] * e + x[1] * n + x[2], z[0] * e + z[1] * n + z[2])
    return transform


def _point_in_ring(point, ring):
    x, y = point
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if ((yi > y) != (yj > y)):
            cross_x = (xj - xi) * (y - yi) / ((yj - yi) or 1e-30) + xi
            if x < cross_x:
                inside = not inside
        j = i
    return inside


def _point_in_polygon(point, polygon):
    if not polygon or not _point_in_ring(point, polygon[0]):
        return False
    for hole in polygon[1:]:
        if _point_in_ring(point, hole):
            return False
    return True


def _prepare_official(features, transform):
    prepared = []
    bins = defaultdict(list)
    for feature in features:
        polygons = []
        min_x = min_z = float("inf")
        max_x = max_z = float("-inf")
        for polygon in feature["geometry"]["coordinates"]:
            transformed_polygon = []
            for ring in polygon:
                transformed_ring = [transform(point) for point in ring]
                transformed_polygon.append(transformed_ring)
                for x, z in transformed_ring:
                    min_x, min_z = min(min_x, x), min(min_z, z)
                    max_x, max_z = max(max_x, x), max(max_z, z)
            polygons.append(transformed_polygon)
        index = len(prepared)
        prepared.append({"feature_id": feature["feature_id"], "bbox": (min_x, min_z, max_x, max_z), "polygons": polygons})
        bx0, bz0 = math.floor(min_x / SPATIAL_BIN_M), math.floor(min_z / SPATIAL_BIN_M)
        bx1, bz1 = math.floor(max_x / SPATIAL_BIN_M), math.floor(max_z / SPATIAL_BIN_M)
        for bx in range(bx0, bx1 + 1):
            for bz in range(bz0, bz1 + 1):
                bins[(bx, bz)].append(index)
    return prepared, bins


def _official_contains(point, prepared, bins):
    key = (math.floor(point[0] / SPATIAL_BIN_M), math.floor(point[1] / SPATIAL_BIN_M))
    for index in bins.get(key, ()):
        feature = prepared[index]
        min_x, min_z, max_x, max_z = feature["bbox"]
        if not (min_x <= point[0] <= max_x and min_z <= point[1] <= max_z):
            continue
        for polygon in feature["polygons"]:
            if _point_in_polygon(point, polygon):
                return True
    return False


def _surface_samples(surface):
    n_length = max(1, math.ceil(surface["length_m"] / TARGET_SAMPLE_SPACING_M))
    n_width = max(1, math.ceil(surface["width_m"] / TARGET_SAMPLE_SPACING_M))
    center = surface["center"]
    direction = surface["direction"]
    perpendicular = surface["perpendicular"]
    for along_i in range(n_length):
        along = ((along_i + 0.5) / n_length - 0.5) * surface["length_m"]
        for across_i in range(n_width):
            across = ((across_i + 0.5) / n_width - 0.5) * surface["width_m"]
            yield (
                center[0] + direction[0] * along + perpendicular[0] * across,
                center[1] + direction[1] * along + perpendicular[1] * across,
            )


def measure():
    osm = _load(OSM_PATH)
    manifest = _load(GEOMETRY_MANIFEST_PATH)
    georef = _load(GEOREF_PATH)
    surfaces = _generic_sidewalks(osm)
    official = _load_official_features(manifest)
    transform = _transformer(georef)
    prepared, bins = _prepare_official(official, transform)

    total_area = 0.0
    covered_area = 0.0
    total_samples = 0
    surface_ratios = []
    covered_surfaces = 0
    half_covered_surfaces = 0
    fully_covered_surfaces = 0

    for surface in surfaces:
        samples = list(_surface_samples(surface))
        hits = sum(1 for point in samples if _official_contains(point, prepared, bins))
        ratio = hits / len(samples)
        area = surface["length_m"] * surface["width_m"]
        total_area += area
        covered_area += area * ratio
        total_samples += len(samples)
        surface_ratios.append(ratio)
        if hits > 0:
            covered_surfaces += 1
        if ratio >= 0.5:
            half_covered_surfaces += 1
        if ratio >= 0.99:
            fully_covered_surfaces += 1

    ordered = sorted(surface_ratios)
    median = (ordered[(len(ordered) - 1) // 2] + ordered[len(ordered) // 2]) * 0.5
    result = {
        "schema": "grand-bruxelles-official-generic-sidewalk-horizontal-overlap-v1",
        "measurement_kind": "deterministic_instance_weighted_area_sampling",
        "horizontal_only": True,
        "source": {
            "generic": {"dataset": "vertical_slice_01.game", "source": osm["source"], "license": osm["license"]},
            "official": manifest["source"],
            "georef_schema": georef["schema"],
            "georef_evidence_sha256": georef["method"]["evidence_sha256"],
        },
        "inputs": {
            "generic_sidewalk_count": len(surfaces),
            "official_feature_count": len(official),
            "official_ring_count": manifest["source_snapshot"]["ring_count"],
            "official_vertex_count": manifest["source_snapshot"]["vertex_count"],
        },
        "algorithm": {
            "target_sample_spacing_m": TARGET_SAMPLE_SPACING_M,
            "surface_sampling": "stratified cell centers in each exact authored sidewalk rectangle",
            "official_membership": "point-in-MultiPolygon with holes after reviewed affine transform",
            "generic_overlap_semantics": "instance-weighted; overlapping generic surface instances are measured independently",
            "area_is_estimate": True,
        },
        "measurement": {
            "sample_count": total_samples,
            "generic_instance_area_m2": round(total_area, 6),
            "official_covered_instance_area_estimate_m2": round(covered_area, 6),
            "instance_weighted_coverage_fraction": round(covered_area / total_area, 9),
            "surfaces_with_any_official_coverage": covered_surfaces,
            "surfaces_with_at_least_50pct_coverage": half_covered_surfaces,
            "surfaces_with_at_least_99pct_coverage": fully_covered_surfaces,
            "median_surface_coverage_fraction": round(median, 9),
        },
        "policy": {
            "curb_height_authorized": False,
            "vertical_profile_authorized": False,
            "runtime_geometry_authorized": False,
            "runtime_replacement_authorized": False,
            "jouable_promotion_authorized": False,
            "measurement_alone_authorizes_runtime": False,
        },
    }
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = measure()
    output = Path(args.output)
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("OFFICIAL_SIDEWALK_HORIZONTAL_OVERLAP_MEASURED " + json.dumps(result["measurement"], sort_keys=True))


if __name__ == "__main__":
    main()
