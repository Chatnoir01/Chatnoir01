#!/usr/bin/env python3
"""Produce a source-coordinate Atomium foreground orthophoto crop for QA.

Primary source is the official UrbIS WMS. CI may not be able to reach that host,
so the probe has one strictly pinned fallback: the exact official 2024 raster
already frozen in the historical Laeken/Jette evidence workspace. Its SHA-256 is
verified before use. No other imagery or guessed geometry is accepted.
"""

from __future__ import annotations

import hashlib
import io
import json
from pathlib import Path
from urllib.error import URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from PIL import Image, ImageDraw

SERVICE = "https://geoservices-grid.irisnet.be/geoserver/urbisgrid/ows"
LAYER = "Ortho"
CRS = "EPSG:31370"
BBOX = [147860.0, 176290.0, 148160.0, 176670.0]
WMS_SIZE = [1500, 1900]
CAMERA = [147928.4114, 176347.3521]
ATOMIUM = [148093.2204, 176602.9369]
OUT_DIR = Path("artifacts/qa/atomium_foreground_ortho")

# Immutable historical evidence copy of the official phase-1 2024 orthophoto.
PINNED_COMMIT = "5525ad370ff4ddc1d34b02ab82cc3fbba3f56cb7"
PINNED_RAW_URL = (
    "https://raw.githubusercontent.com/Chatnoir01/Chatnoir01/"
    + PINNED_COMMIT
    + "/grand-bruxelles-game/data/orthophoto/laeken_jette/phase1_ortho.jpg"
)
PINNED_SHA256 = "c23ab90490d78acb6accc0d4ce8a1bad5821b8b478b3643744382c4f13f57d95"
PINNED_FULL_BBOX = [147300.0, 173650.0, 149100.0, 176750.0]
PINNED_FULL_SIZE = [2048, 3527]


def _fetch(url: str, timeout: int) -> tuple[bytes, str]:
    req = Request(url, headers={"User-Agent": "Grand-Bruxelles-Game-QA/1.0"})
    with urlopen(req, timeout=timeout) as response:
        return response.read(), response.headers.get("Content-Type", "")


def _wms_url() -> str:
    query = urlencode(
        {
            "Service": "WMS",
            "Version": "1.3.0",
            "Request": "GetMap",
            "Layers": LAYER,
            "Styles": "",
            "CRS": CRS,
            "BBOX": ",".join(str(v) for v in BBOX),
            "Width": WMS_SIZE[0],
            "Height": WMS_SIZE[1],
            "Format": "image/jpeg",
            "Transparent": "false",
        }
    )
    return f"{SERVICE}?{query}"


def _crop_pinned(body: bytes) -> Image.Image:
    digest = hashlib.sha256(body).hexdigest()
    if digest != PINNED_SHA256:
        raise RuntimeError(f"pinned official raster SHA drifted: {digest}")
    image = Image.open(io.BytesIO(body)).convert("RGB")
    if list(image.size) != PINNED_FULL_SIZE:
        raise RuntimeError(f"pinned raster dimensions drifted: {image.size}")
    min_e, min_n, max_e, max_n = PINNED_FULL_BBOX
    left = round((BBOX[0] - min_e) / (max_e - min_e) * image.width)
    right = round((BBOX[2] - min_e) / (max_e - min_e) * image.width)
    top = round((max_n - BBOX[3]) / (max_n - min_n) * image.height)
    bottom = round((max_n - BBOX[1]) / (max_n - min_n) * image.height)
    if left < 0 or top < 0 or right > image.width or bottom > image.height or right <= left or bottom <= top:
        raise RuntimeError("requested crop falls outside pinned raster")
    return image.crop((left, top, right, bottom))


def _pixel_for(e: float, n: float, width: int, height: int) -> tuple[int, int]:
    min_e, min_n, max_e, max_n = BBOX
    x = round((e - min_e) / (max_e - min_e) * (width - 1))
    y = round((max_n - n) / (max_n - min_n) * (height - 1))
    return x, y


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    source_mode = "official_wms_live"
    source_sha = ""
    source_bytes = 0
    try:
        body, content_type = _fetch(_wms_url(), 15)
        if "image" not in content_type.lower() or len(body) < 50_000:
            raise RuntimeError(f"unexpected WMS response: type={content_type!r} bytes={len(body)}")
        image = Image.open(io.BytesIO(body)).convert("RGB")
        if list(image.size) != WMS_SIZE:
            raise RuntimeError(f"unexpected WMS dimensions: {image.size}")
        source_sha = hashlib.sha256(body).hexdigest()
        source_bytes = len(body)
    except (OSError, URLError, RuntimeError, TimeoutError) as exc:
        print(f"ATOMIUM_FOREGROUND_ORTHO_WMS_UNAVAILABLE: {type(exc).__name__}: {exc}")
        source_mode = "pinned_official_phase1_raster"
        body, content_type = _fetch(PINNED_RAW_URL, 30)
        if "image" not in content_type.lower() or len(body) < 500_000:
            raise RuntimeError(f"unexpected pinned raster response: type={content_type!r} bytes={len(body)}")
        image = _crop_pinned(body)
        source_sha = hashlib.sha256(body).hexdigest()
        source_bytes = len(body)

    crop_path = OUT_DIR / "ortho_crop.jpg"
    image.save(crop_path, quality=95)
    width, height = image.size
    camera_px = _pixel_for(*CAMERA, width, height)
    atomium_px = _pixel_for(*ATOMIUM, width, height)

    annotated = image.copy()
    draw = ImageDraw.Draw(annotated)
    marker_width = max(2, round(width / 300))
    radius = max(5, round(width / 80))
    draw.line([camera_px, atomium_px], fill=(255, 0, 255), width=marker_width)
    for point, fill in ((camera_px, (255, 255, 0)), (atomium_px, (0, 255, 255))):
        x, y = point
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), outline=fill, width=marker_width)
    annotated.save(OUT_DIR / "annotated.png")

    resolution = [
        (BBOX[2] - BBOX[0]) / width,
        (BBOX[3] - BBOX[1]) / height,
    ]
    report = {
        "schema": 2,
        "purpose": "inspection-only official orthophoto crop; no fountain geometry inferred",
        "source": "Paradigm / Brussels-Capital Region UrbIS raster orthophoto",
        "source_mode": source_mode,
        "layer": LAYER,
        "crs": CRS,
        "bbox_epsg31370": BBOX,
        "raster_size_px": [width, height],
        "ground_resolution_m_per_px": resolution,
        "camera_epsg31370": CAMERA,
        "atomium_audit_marker_epsg31370": ATOMIUM,
        "camera_pixel": list(camera_px),
        "atomium_pixel": list(atomium_px),
        "source_response_sha256": source_sha,
        "source_response_bytes": source_bytes,
        "pinned_fallback": {
            "commit": PINNED_COMMIT,
            "sha256": PINNED_SHA256,
            "full_bbox_epsg31370": PINNED_FULL_BBOX,
            "full_raster_size_px": PINNED_FULL_SIZE,
        },
        "reuse_status": "official 2024 UrbIS orthophoto; pinned fallback accepted only after exact SHA verification",
        "hard_limits": [
            "Do not digitize a fountain or paving polygon from intuition alone.",
            "This crop is visual evidence, not a classified vector dataset.",
            "Any candidate footprint must be recorded separately with pixel/coordinate witnesses and uncertainty.",
        ],
    }
    (OUT_DIR / "probe.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "ATOMIUM_FOREGROUND_ORTHO_PROBE_OK: "
        f"mode={source_mode} source_sha256={source_sha} source_bytes={source_bytes} "
        f"crop={width}x{height} camera_px={camera_px} atomium_px={atomium_px} "
        f"resolution_m_px={resolution[0]:.3f}x{resolution[1]:.3f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
