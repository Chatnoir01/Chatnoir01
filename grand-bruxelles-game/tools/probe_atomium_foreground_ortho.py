#!/usr/bin/env python3
"""Fetch a tight official UrbIS orthophoto crop for Atomium foreground QA.

This probe deliberately does not infer fountain geometry. It freezes a lawful,
source-coordinate crop around the source-published ground camera and the existing
Atomium anchor so a human/next deterministic extraction step can inspect the
actual basin/open-space pixels before any runtime mesh is authored.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from PIL import Image, ImageDraw

SERVICE = "https://geoservices-grid.irisnet.be/geoserver/urbisgrid/ows"
LAYER = "Ortho"
CRS = "EPSG:31370"
# Tight crop covering the source camera -> Atomium axis plus lateral context.
BBOX = [147860.0, 176290.0, 148160.0, 176670.0]
WIDTH = 1500
HEIGHT = 1900
CAMERA = [147928.4114, 176347.3521]
# Existing project Atomium anchor projected into EPSG:31370 from the canonical
# Laeken/Jette local-coordinate contract. This is an audit marker, not a new
# survey claim.
ATOMIUM = [148093.2204, 176602.9369]
OUT_DIR = Path("artifacts/qa/atomium_foreground_ortho")


def pixel_for(e: float, n: float) -> tuple[int, int]:
    min_e, min_n, max_e, max_n = BBOX
    x = round((e - min_e) / (max_e - min_e) * (WIDTH - 1))
    y = round((max_n - n) / (max_n - min_n) * (HEIGHT - 1))
    return x, y


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    query = urlencode(
        {
            "Service": "WMS",
            "Version": "1.3.0",
            "Request": "GetMap",
            "Layers": LAYER,
            "Styles": "",
            "CRS": CRS,
            "BBOX": ",".join(str(v) for v in BBOX),
            "Width": WIDTH,
            "Height": HEIGHT,
            "Format": "image/jpeg",
            "Transparent": "false",
        }
    )
    url = f"{SERVICE}?{query}"
    req = Request(url, headers={"User-Agent": "Grand-Bruxelles-Game-QA/1.0"})
    with urlopen(req, timeout=90) as response:
        body = response.read()
        content_type = response.headers.get("Content-Type", "")
    if "image" not in content_type.lower() or len(body) < 50_000:
        raise RuntimeError(f"unexpected WMS response: type={content_type!r} bytes={len(body)}")

    crop_path = OUT_DIR / "ortho_crop.jpg"
    crop_path.write_bytes(body)
    digest = hashlib.sha256(body).hexdigest()
    image = Image.open(crop_path).convert("RGB")
    if image.size != (WIDTH, HEIGHT):
        raise RuntimeError(f"unexpected raster dimensions: {image.size}")

    annotated = image.copy()
    draw = ImageDraw.Draw(annotated)
    camera_px = pixel_for(*CAMERA)
    atomium_px = pixel_for(*ATOMIUM)
    draw.line([camera_px, atomium_px], fill=(255, 0, 255), width=5)
    for point, fill in ((camera_px, (255, 255, 0)), (atomium_px, (0, 255, 255))):
        x, y = point
        draw.ellipse((x - 12, y - 12, x + 12, y + 12), outline=fill, width=6)
    annotated_path = OUT_DIR / "annotated.png"
    annotated.save(annotated_path)

    report = {
        "schema": 1,
        "purpose": "inspection-only official orthophoto crop; no fountain geometry inferred",
        "source": "Paradigm / Brussels-Capital Region UrbIS raster WMS",
        "layer": LAYER,
        "crs": CRS,
        "bbox_epsg31370": BBOX,
        "raster_size_px": [WIDTH, HEIGHT],
        "ground_resolution_m_per_px": [
            (BBOX[2] - BBOX[0]) / WIDTH,
            (BBOX[3] - BBOX[1]) / HEIGHT,
        ],
        "camera_epsg31370": CAMERA,
        "atomium_audit_marker_epsg31370": ATOMIUM,
        "camera_pixel": list(camera_px),
        "atomium_pixel": list(atomium_px),
        "wms_response_sha256": digest,
        "wms_response_bytes": len(body),
        "reuse_status": "official WMS source; existing project provenance records CC0/public access",
        "hard_limits": [
            "Do not digitize a fountain or paving polygon from intuition alone.",
            "This crop is visual evidence, not a classified vector dataset.",
            "Any candidate footprint must be recorded separately with pixel/coordinate witnesses and uncertainty.",
        ],
    }
    (OUT_DIR / "probe.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "ATOMIUM_FOREGROUND_ORTHO_PROBE_OK: "
        f"sha256={digest} bytes={len(body)} camera_px={camera_px} atomium_px={atomium_px} "
        f"resolution_m_px={report['ground_resolution_m_per_px'][0]:.3f}x{report['ground_resolution_m_per_px'][1]:.3f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
