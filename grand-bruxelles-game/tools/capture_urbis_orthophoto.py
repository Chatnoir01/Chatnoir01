#!/usr/bin/env python3
"""Capture an official UrbIS orthophoto for one Lambert72 cell.

This tool mirrors the public Paradigm/UrbIS GeoServer preview for
``inspire:Ortho``: workspace-scoped WMS 1.1.0 in EPSG:31370. It can either
print/write request metadata or download the PNG. The PNG is for visual
validation/reference; geometry remains sourced from UrbIS vector products.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import urllib.parse
import urllib.request
from pathlib import Path

DEFAULT_ENDPOINT = "https://geoservices-urbis.irisnet.be/geoserver/inspire/wms"
DEFAULT_LAYER = "inspire:Ortho"
WMS_VERSION = "1.1.0"
CRS = "EPSG:31370"


def parse_bbox(text: str) -> tuple[float, float, float, float]:
    parts = [part.strip() for part in text.split(",")]
    if len(parts) != 4:
        raise ValueError("bbox must contain minE,minN,maxE,maxN")
    values = tuple(float(part) for part in parts)
    min_e, min_n, max_e, max_n = values
    if not (min_e < max_e and min_n < max_n):
        raise ValueError("bbox min values must be lower than max values")
    return values


def build_wms_url(
    bbox: tuple[float, float, float, float],
    *,
    width: int = 1024,
    height: int = 1024,
    endpoint: str = DEFAULT_ENDPOINT,
    layer: str = DEFAULT_LAYER,
) -> str:
    if width <= 0 or height <= 0:
        raise ValueError("width and height must be positive")
    min_e, min_n, max_e, max_n = bbox
    params = {
        "service": "WMS",
        "version": WMS_VERSION,
        "request": "GetMap",
        "layers": layer,
        "styles": "",
        "srs": CRS,
        "bbox": f"{min_e:g},{min_n:g},{max_e:g},{max_n:g}",
        "width": str(width),
        "height": str(height),
        "format": "image/png",
        "transparent": "false",
    }
    return endpoint + "?" + urllib.parse.urlencode(params)


def download(url: str, output: Path, timeout: float = 60.0) -> dict:
    output.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "GrandBruxellesGame/1.0",
            "Accept": "image/png,image/*;q=0.9,*/*;q=0.1",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        content_type = response.headers.get("Content-Type", "")
        payload = response.read()
    if not payload.startswith(b"\x89PNG\r\n\x1a\n"):
        excerpt = payload[:160].decode("utf-8", errors="replace")
        raise RuntimeError(
            f"UrbIS WMS did not return PNG data (content-type={content_type!r}, body={excerpt!r})"
        )
    output.write_bytes(payload)
    return {
        "path": str(output),
        "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "content_type": content_type,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Capture official UrbIS orthophoto for a Lambert72 cell")
    parser.add_argument("--bbox", required=True, help="minE,minN,maxE,maxN in EPSG:31370")
    parser.add_argument("--output", type=Path, help="PNG output path; omit for metadata-only mode")
    parser.add_argument("--metadata", type=Path, help="optional JSON provenance sidecar")
    parser.add_argument("--width", type=int, default=1024)
    parser.add_argument("--height", type=int, default=1024)
    parser.add_argument("--layer", default=DEFAULT_LAYER)
    parser.add_argument("--endpoint", default=DEFAULT_ENDPOINT)
    args = parser.parse_args()

    bbox = parse_bbox(args.bbox)
    url = build_wms_url(
        bbox,
        width=args.width,
        height=args.height,
        endpoint=args.endpoint,
        layer=args.layer,
    )
    result = {
        "format": "grand-bruxelles-orthophoto-reference-v1",
        "provider": "Paradigm / UrbIS",
        "service": f"WMS {WMS_VERSION}",
        "endpoint": args.endpoint,
        "layer": args.layer,
        "crs": CRS,
        "bbox": list(bbox),
        "width": args.width,
        "height": args.height,
        "url": url,
        "purpose": "visual validation/reference only",
    }
    if args.output:
        result["download"] = download(url, args.output)
    if args.metadata:
        args.metadata.parent.mkdir(parents=True, exist_ok=True)
        args.metadata.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
