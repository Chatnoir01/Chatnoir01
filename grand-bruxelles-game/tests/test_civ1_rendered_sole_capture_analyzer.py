from __future__ import annotations

import importlib.util
import struct
import tempfile
import zlib
from pathlib import Path

TOOL = Path(__file__).parents[1] / "tools" / "analyze_civ1_rendered_sole_capture.py"
spec = importlib.util.spec_from_file_location("civ1_rendered_sole", TOOL)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)


def _chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def _png(path: Path, width: int, height: int, bottom_y: int, x0: int, x1: int) -> None:
    rows = []
    for y in range(height):
        row = bytearray()
        for x in range(width):
            white = y == bottom_y and x0 <= x <= x1
            row += bytes((255, 255, 255) if white else (80, 80, 80))
        rows.append(b"\x00" + bytes(row))
    raw = b"\x89PNG\r\n\x1a\n"
    raw += _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    raw += _chunk(b"IDAT", zlib.compress(b"".join(rows)))
    raw += _chunk(b"IEND", b"")
    path.write_bytes(raw)


def test_rendered_raster_path_is_measured_without_contact_promotion() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        # Candidate 115-118 stays on one rendered bottom row but moves 2 px/frame.
        for sample in mod.TARGET:
            x0 = 20 + max(0, sample - 114) * 2
            _png(root / f"left-ground-side-{sample:03d}.png", 96, 64, 50, x0, x0 + 24)
        report = mod.analyze(root)
        assert report["rendered_mesh_aware"] is True
        assert report["candidate_bottom_row_span_px"] == 0
        assert report["candidate_bottom_centroid_path_px"] == 6.0
        assert report["rendered_sole_contact_claimed"] is False
        assert report["ground_contact_claimed"] is False
        assert report["runtime_authorized"] is False
        assert report["visual_approval_claimed"] is False
        assert report["player_view_claimed"] is False


def test_missing_capture_fails_closed() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        for sample in mod.TARGET[:-1]:
            _png(root / f"left-ground-side-{sample:03d}.png", 96, 64, 50, 20, 50)
        try:
            mod.analyze(root)
        except ValueError as exc:
            assert "missing capture" in str(exc)
        else:
            raise AssertionError("missing evidence must fail")


def test_non_png_fails_closed() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        for sample in mod.TARGET:
            (root / f"left-ground-side-{sample:03d}.png").write_bytes(b"not-png")
        try:
            mod.analyze(root)
        except ValueError as exc:
            assert "not PNG" in str(exc)
        else:
            raise AssertionError("invalid raster evidence must fail")


if __name__ == "__main__":
    test_rendered_raster_path_is_measured_without_contact_promotion()
    test_missing_capture_fails_closed()
    test_non_png_fails_closed()
    print("CIV1_RENDERED_SOLE_CAPTURE_ANALYZER_TESTS_OK")
