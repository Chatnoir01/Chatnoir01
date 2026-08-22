import json
import struct
import zlib
from pathlib import Path

import pytest

from tools.qa.validate_grand_place_facade_evidence import EvidenceValidationError, validate_evidence

ROOT = Path(__file__).resolve().parents[1]
GATE = ROOT / "data" / "qa" / "grand_place_facade_visual_gate.json"
BASE_SHA = "bae409b881530e3fff3f6d3261a1439b25d979fa"
HEAD_SHA = "1111111111111111111111111111111111111111"
REQUIRED_VIEWS = ["canonical", "cornet_renard", "brasseurs_rose_thabor", "maison_du_roi"]


def _chunk(kind: bytes, payload: bytes) -> bytes:
    body = kind + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def _write_png(path: Path, width: int = 1280, height: int = 720) -> None:
    row = b"\x00" + (b"\x00" * ((width + 7) // 8))
    raw = row * height
    ihdr = struct.pack(">IIBBBBB", width, height, 1, 0, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", zlib.compress(raw, 9))
        + _chunk(b"IEND", b"")
    )


def _view_contracts():
    return [
        {"id": "canonical", "png": "canonical.png", "target_method": "fixed_existing_witness", "target": [321.91, 11.8, -485.66]},
        {"id": "cornet_renard", "png": "cornet_renard.png", "target_method": "source_bbox_cluster_center", "target_owner_ids": ["1608847", "1608851"]},
        {"id": "brasseurs_rose_thabor", "png": "brasseurs_rose_thabor.png", "target_method": "source_bbox_cluster_center", "target_owner_ids": ["1639974", "1635485", "1646728"]},
        {"id": "maison_du_roi", "png": "maison_du_roi.png", "target_method": "source_bbox_cluster_center", "target_owner_ids": ["1654360"]},
    ]


def _manifest(tmp_path: Path, **overrides):
    for view_id in REQUIRED_VIEWS:
        _write_png(tmp_path / f"{view_id}.png")
    data = {
        "schema": "grand-bruxelles-grand-place-facade-evidence-v1",
        "artifact_kind": "grand_place_facade_visual_witness",
        "base_sha": BASE_SHA,
        "head_sha": HEAD_SHA,
        "resolution": [1280, 720],
        "camera_position": [319.01, 1.72, -535.20],
        "fov_deg": 62.0,
        "human_review_required": True,
        "human_review_status": "pending",
        "views": _view_contracts(),
    }
    data.update(overrides)
    path = tmp_path / "manifest.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    return path


def test_accepts_only_structurally_complete_pending_witness(tmp_path):
    result = validate_evidence(GATE, _manifest(tmp_path), tmp_path)
    assert result["view_count"] == 4
    assert result["resolution"] == [1280, 720]
    assert result["human_review_status"] == "pending"
    assert result["visual_approval_claimed"] is False


@pytest.mark.parametrize(
    "field,value",
    [
        ("artifact_kind", "photo_match"),
        ("base_sha", "2222222222222222222222222222222222222222"),
        ("head_sha", BASE_SHA),
        ("resolution", [1280, 960]),
        ("camera_position", [320.0, 1.72, -535.20]),
        ("fov_deg", 61.0),
        ("human_review_required", False),
        ("human_review_status", "approved"),
    ],
)
def test_rejects_contract_drift_or_fake_human_approval(tmp_path, field, value):
    with pytest.raises(EvidenceValidationError):
        validate_evidence(GATE, _manifest(tmp_path, **{field: value}), tmp_path)


def test_rejects_source_target_substitution_even_with_valid_pngs(tmp_path):
    manifest = _manifest(tmp_path)
    data = json.loads(manifest.read_text(encoding="utf-8"))
    data["views"][1]["target_owner_ids"] = ["1654360"]
    manifest.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(EvidenceValidationError):
        validate_evidence(GATE, manifest, tmp_path)

    manifest = _manifest(tmp_path)
    data = json.loads(manifest.read_text(encoding="utf-8"))
    data["views"][1].pop("target_owner_ids")
    data["views"][1]["target"] = [0.0, 0.0, 0.0]
    manifest.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(EvidenceValidationError):
        validate_evidence(GATE, manifest, tmp_path)


def test_rejects_fixed_witness_target_drift(tmp_path):
    manifest = _manifest(tmp_path)
    data = json.loads(manifest.read_text(encoding="utf-8"))
    data["views"][0]["target"] = [321.91, 12.8, -485.66]
    manifest.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(EvidenceValidationError):
        validate_evidence(GATE, manifest, tmp_path)


def test_rejects_missing_duplicate_or_extra_views(tmp_path):
    manifest = _manifest(tmp_path)
    data = json.loads(manifest.read_text(encoding="utf-8"))
    data["views"] = data["views"][:-1]
    manifest.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(EvidenceValidationError):
        validate_evidence(GATE, manifest, tmp_path)

    manifest = _manifest(tmp_path)
    data = json.loads(manifest.read_text(encoding="utf-8"))
    data["views"][3]["id"] = "canonical"
    manifest.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(EvidenceValidationError):
        validate_evidence(GATE, manifest, tmp_path)


def test_rejects_png_with_wrong_real_dimensions(tmp_path):
    manifest = _manifest(tmp_path)
    _write_png(tmp_path / "cornet_renard.png", 1280, 960)
    with pytest.raises(EvidenceValidationError):
        validate_evidence(GATE, manifest, tmp_path)


def test_rejects_truncated_or_crc_corrupt_png(tmp_path):
    manifest = _manifest(tmp_path)
    png = tmp_path / "cornet_renard.png"
    png.write_bytes(png.read_bytes()[:24])
    with pytest.raises(EvidenceValidationError):
        validate_evidence(GATE, manifest, tmp_path)

    manifest = _manifest(tmp_path)
    png = tmp_path / "cornet_renard.png"
    payload = bytearray(png.read_bytes())
    payload[-1] ^= 0x01
    png.write_bytes(payload)
    with pytest.raises(EvidenceValidationError):
        validate_evidence(GATE, manifest, tmp_path)


def test_rejects_absolute_or_traversing_png_paths(tmp_path):
    manifest = _manifest(tmp_path)
    data = json.loads(manifest.read_text(encoding="utf-8"))
    data["views"][0]["png"] = "../canonical.png"
    manifest.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(EvidenceValidationError):
        validate_evidence(GATE, manifest, tmp_path)

    manifest = _manifest(tmp_path)
    data = json.loads(manifest.read_text(encoding="utf-8"))
    data["views"][0]["png"] = str((tmp_path / "canonical.png").resolve())
    manifest.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(EvidenceValidationError):
        validate_evidence(GATE, manifest, tmp_path)
