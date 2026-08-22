#!/usr/bin/env python3
"""Bounded, fail-closed Brussels Mobility sidewalk extractor.

The official `bm_urbis:urbadm_ssw` layer is itself the sidewalk dataset. The
`ssft` attribute is preserved and validated against the publisher's attribute
domain, but it is not used as a local `SW` filter: the live corridor response
contains no `ssft=SW` rows even though `SW` exists in the published domain.

Raw WFS bytes are retained as acquisition evidence. Because GeoServer changes
the top-level FeatureCollection `timeStamp` between otherwise identical
responses, a second canonical content digest is computed from the same response
with only that volatile field removed and features sorted by exact WFS id.

This tool only establishes source-backed horizontal sidewalk geometry plus the
published layer/attribute identities. It never authorizes runtime geometry,
elevations, curb profiles, paving dimensions, or material identity.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request, urlopen

SCHEMA = "grand-bruxelles-official-sidewalk-corridor-extract-v1"
CRS = "EPSG:31370"
LAYER = "bm_urbis:urbadm_ssw"
PUBLISHED_SIDEWALK_DOMAIN_CODE = "SW"
DEFAULT_BBOX = [147650.0, 169300.0, 149100.0, 171050.0]
WFS_ENDPOINT = "https://data.mobility.brussels/geoserver/bm_urbis/wfs"
ATTRIBUTE_DOMAIN_ENDPOINT = "https://data.mobility.brussels/data/attributevalues/?tid=ssft"
ALLOWED_GEOMETRIES = {"Polygon", "MultiPolygon"}
VOLATILE_WFS_METADATA_FIELDS = {"timeStamp"}


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _validate_bbox(query_bbox: list[float]) -> list[float]:
    if len(query_bbox) != 4:
        raise ValueError("query bbox must contain exactly four coordinates")
    bbox = [float(value) for value in query_bbox]
    min_x, min_y, max_x, max_y = bbox
    if not (min_x < max_x and min_y < max_y):
        raise ValueError("query bbox is not ordered")
    if bbox != DEFAULT_BBOX:
        raise ValueError(f"query bbox drifted from reviewed corridor scope: {bbox}")
    return bbox


def build_wfs_url(query_bbox: list[float] | None = None) -> str:
    bbox = _validate_bbox(query_bbox or DEFAULT_BBOX)
    params = {
        "service": "WFS",
        "version": "1.1.0",
        "request": "GetFeature",
        "typeName": LAYER,
        "outputFormat": "json",
        "srsName": CRS,
        "bbox": ",".join(f"{value:.3f}" for value in bbox),
    }
    return f"{WFS_ENDPOINT}?{urlencode(params)}"


def _parse_ssft_domain(raw: bytes) -> dict[str, dict[str, str]]:
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("official ssft attribute domain is not valid UTF-8 JSON") from exc
    if not isinstance(payload, list) or not payload:
        raise ValueError("official ssft attribute domain is empty or malformed")
    domain: dict[str, dict[str, str]] = {}
    for row in payload:
        if not isinstance(row, dict):
            raise ValueError("official ssft attribute domain contains a malformed row")
        value = str(row.get("value", "")).strip()
        label_fr = str(row.get("label_fr", "")).strip()
        label_nl = str(row.get("label_nl", "")).strip()
        if not value or not label_fr or not label_nl:
            raise ValueError("official ssft attribute domain row is incomplete")
        if value in domain:
            raise ValueError(f"duplicate ssft attribute-domain code: {value}")
        domain[value] = {"label_fr": label_fr, "label_nl": label_nl}
    sidewalk_code = domain.get(PUBLISHED_SIDEWALK_DOMAIN_CODE)
    if sidewalk_code != {"label_fr": "Trottoir", "label_nl": "Voetpad"}:
        raise ValueError("official ssft domain no longer maps SW to Trottoir/Voetpad")
    return domain


def _canonical_source_content_sha256(payload: dict[str, Any]) -> str:
    """Digest source content while excluding only known volatile WFS metadata.

    Feature ordering is representation-only, so features are sorted by the exact
    WFS id before JSON canonicalization. All feature properties and geometry are
    retained; any substantive source change changes this digest.
    """
    stable_payload = {key: value for key, value in payload.items() if key not in VOLATILE_WFS_METADATA_FIELDS}
    features = stable_payload.get("features")
    if not isinstance(features, list) or not features:
        raise ValueError("official sidewalk response has no features for canonical digest")
    if any(not isinstance(feature, dict) or not str(feature.get("id", "")).strip() for feature in features):
        raise ValueError("official sidewalk response contains feature without identity")
    stable_payload["features"] = sorted(features, key=lambda feature: str(feature["id"]))
    canonical_bytes = json.dumps(
        stable_payload,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")
    return _sha256(canonical_bytes)


def _canonical_geometry(feature: dict[str, Any]) -> dict[str, Any]:
    geometry = feature.get("geometry")
    if not isinstance(geometry, dict):
        raise ValueError("feature geometry missing")
    geometry_type = geometry.get("type")
    coordinates = geometry.get("coordinates")
    if geometry_type not in ALLOWED_GEOMETRIES:
        raise ValueError(f"unsupported sidewalk geometry type: {geometry_type}")
    if not isinstance(coordinates, list) or not coordinates:
        raise ValueError("sidewalk geometry coordinates missing")
    return {"type": geometry_type, "coordinates": coordinates}


def canonicalize_feature_collection(
    raw: bytes,
    *,
    attribute_domain_raw: bytes,
    query_bbox: list[float] | None = None,
) -> dict[str, Any]:
    bbox = _validate_bbox(query_bbox or DEFAULT_BBOX)
    domain = _parse_ssft_domain(attribute_domain_raw)
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("official sidewalk response is not valid UTF-8 GeoJSON") from exc
    if not isinstance(payload, dict) or payload.get("type") != "FeatureCollection":
        raise ValueError("official sidewalk response is not a FeatureCollection")
    source_features = payload.get("features")
    if not isinstance(source_features, list) or not source_features:
        raise ValueError("official sidewalk response has no features")
    response_timestamp = str(payload.get("timeStamp", "")).strip()
    canonical_source_content_sha256 = _canonical_source_content_sha256(payload)

    features: list[dict[str, Any]] = []
    seen_feature_ids: set[str] = set()
    seen_gids: set[int] = set()
    ssft_counts: Counter[str] = Counter()
    for feature in source_features:
        if not isinstance(feature, dict):
            raise ValueError("malformed sidewalk feature")
        feature_id = str(feature.get("id", "")).strip()
        if not feature_id:
            raise ValueError("sidewalk feature identity missing")
        properties = feature.get("properties")
        if not isinstance(properties, dict):
            raise ValueError(f"sidewalk feature properties missing: {feature_id}")
        try:
            source_gid = int(properties["gid"])
            source_id = int(properties["id"])
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError(f"sidewalk feature source identity missing: {feature_id}") from exc
        if source_gid <= 0 or source_id <= 0:
            raise ValueError(f"sidewalk feature source identity invalid: {feature_id}")
        expected_feature_id = f"urbadm_ssw.{source_gid}"
        if feature_id != expected_feature_id:
            raise ValueError(f"sidewalk WFS identity does not match gid: {feature_id} != {expected_feature_id}")
        if feature_id in seen_feature_ids or source_gid in seen_gids:
            raise ValueError(f"duplicate sidewalk feature identity: {feature_id}")
        seen_feature_ids.add(feature_id)
        seen_gids.add(source_gid)

        ssft = str(properties.get("ssft", "")).strip()
        if not ssft:
            raise ValueError(f"sidewalk feature ssft missing: {feature_id}")
        if ssft not in domain:
            raise ValueError(f"sidewalk feature uses unpublished ssft code {ssft}: {feature_id}")
        ssft_counts[ssft] += 1
        features.append(
            {
                "feature_id": feature_id,
                "source_gid": source_gid,
                "source_id": source_id,
                "ssft": ssft,
                "geometry": _canonical_geometry(feature),
            }
        )

    features.sort(key=lambda item: item["feature_id"])
    ids_bytes = "".join(f"{item['feature_id']}\n" for item in features).encode("utf-8")
    observed_ssft = sorted(ssft_counts)
    return {
        "schema": SCHEMA,
        "source": {
            "publisher": "Paradigm",
            "dataset": "Trottoir",
            "layer": LAYER,
            "license": "CC0-1.0",
            "crs": CRS,
            "sidewalk_semantics_basis": "official_dataset_and_layer_identity",
            "semantic_field": "ssft",
            "ssft_filter_applied": False,
            "published_sidewalk_domain_code": PUBLISHED_SIDEWALK_DOMAIN_CODE,
            "observed_ssft_values": observed_ssft,
            "attribute_domain_url": ATTRIBUTE_DOMAIN_ENDPOINT,
            "attribute_domain_sha256": _sha256(attribute_domain_raw),
            "wfs_endpoint": WFS_ENDPOINT,
            "volatile_wfs_metadata_fields": sorted(VOLATILE_WFS_METADATA_FIELDS),
            "response_timestamp": response_timestamp,
        },
        "crs": CRS,
        "query_bbox": bbox,
        "query_filter": "server_bbox_only_layer_identity_no_local_ssft_filter",
        "input_feature_count": len(source_features),
        "feature_count": len(features),
        "ssft_counts": dict(sorted(ssft_counts.items())),
        "source_sha256": _sha256(raw),
        "canonical_source_content_sha256": canonical_source_content_sha256,
        "feature_id_sha256": _sha256(ids_bytes),
        "features": features,
        "claims": {
            "horizontal_sidewalk_geometry_source_backed": True,
            "sidewalk_semantic_class_source_backed": True,
            "sidewalk_semantics_derived_from_layer_identity": True,
            "ssft_values_source_backed": True,
            "ssft_sw_filter_source_backed": False,
            "curb_height_source_backed": False,
            "surface_elevation_source_backed": False,
            "sidewalk_profile_source_backed": False,
            "paving_unit_dimensions_source_backed": False,
            "material_identity_source_backed": False,
        },
        "policy": {
            "runtime_geometry_authorized": False,
            "jouable_promotion_authorized": False,
            "vertical_extrusion_allowed": False,
            "curb_height_inference_allowed": False,
            "game_world_transform_applied": False,
            "source_geometry_modified": False,
        },
    }


def fetch_official(query_bbox: list[float] | None = None, timeout_seconds: int = 90) -> tuple[bytes, str]:
    url = build_wfs_url(query_bbox)
    request = Request(url, headers={"Accept": "application/json", "User-Agent": "Grand-Bruxelles-Source-Gate/1.0"})
    with urlopen(request, timeout=timeout_seconds) as response:
        content_type = str(response.headers.get("Content-Type", ""))
        raw = response.read()
    if "json" not in content_type.lower() and not raw.lstrip().startswith(b"{"):
        snippet = raw[:500].decode("utf-8", errors="replace").replace("\n", " ")
        raise ValueError(f"official sidewalk WFS returned non-JSON content: {content_type}; {snippet}")
    return raw, url


def fetch_attribute_domain(timeout_seconds: int = 60) -> bytes:
    request = Request(
        ATTRIBUTE_DOMAIN_ENDPOINT,
        headers={"Accept": "application/json", "User-Agent": "Grand-Bruxelles-Source-Gate/1.0"},
    )
    with urlopen(request, timeout=timeout_seconds) as response:
        content_type = str(response.headers.get("Content-Type", ""))
        raw = response.read()
    if "json" not in content_type.lower() and not raw.lstrip().startswith((b"{", b"[")):
        raise ValueError(f"official ssft attribute domain returned non-JSON content: {content_type}")
    _parse_ssft_domain(raw)
    return raw


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, help="Read a captured WFS GeoJSON response instead of the network")
    parser.add_argument("--attribute-domain", type=Path, help="Read the captured official ssft attribute-domain JSON")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--raw-output", type=Path, help="Persist exact source bytes when network acquisition is used")
    parser.add_argument("--bbox", nargs=4, type=float, default=DEFAULT_BBOX)
    args = parser.parse_args()

    bbox = _validate_bbox(list(args.bbox))
    if args.input:
        raw = args.input.read_bytes()
        source_url = "fixture-or-captured-source"
    else:
        raw, source_url = fetch_official(bbox)
        if args.raw_output:
            args.raw_output.parent.mkdir(parents=True, exist_ok=True)
            args.raw_output.write_bytes(raw)

    attribute_domain_raw = args.attribute_domain.read_bytes() if args.attribute_domain else fetch_attribute_domain()
    canonical = canonicalize_feature_collection(raw, attribute_domain_raw=attribute_domain_raw, query_bbox=bbox)
    canonical["source_query_url"] = source_url
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(canonical, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    print(
        "OFFICIAL_SIDEWALK_EXTRACT_OK "
        f"features={canonical['feature_count']} "
        f"input={canonical['input_feature_count']} "
        f"ssft_values={','.join(canonical['source']['observed_ssft_values'])} "
        f"source_sha256={canonical['source_sha256']} "
        f"canonical_source_content_sha256={canonical['canonical_source_content_sha256']} "
        f"feature_id_sha256={canonical['feature_id_sha256']} "
        f"bbox={','.join(str(value) for value in bbox)} "
        f"runtime_authorized={canonical['policy']['runtime_geometry_authorized']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
