#!/usr/bin/env python3
"""Regression: Anneessens PNG evidence must reject bytes after the zlib image stream."""
from __future__ import annotations

import importlib.util
import struct
import tempfile
import zlib
from pathlib import Path

VALIDATOR = Path(__file__).with_name("validate_anneessens_player_witness_evidence.py")
spec = importlib.util.spec_from_file_location("anneessens_validator", VALIDATOR)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def chunk(kind: bytes, payload: bytes) -> bytes:
    crc = zlib.crc32(kind)
    crc = zlib.crc32(payload, crc) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", crc)


width, height = 1280, 720
ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
scanline = b"\x00" + (b"\x00" * (width * 4))
raw = scanline * height
# A valid zlib stream followed by opaque bytes is accepted by zlib.decompress().
# The evidence validator must fail closed instead of silently ignoring that suffix.
idat = zlib.compress(raw, level=9) + b"HIDDEN_TRAILING_ZLIB_PAYLOAD"
png = module.PNG_SIGNATURE + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")

with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / "frame.png"
    path.write_bytes(png)
    try:
        module.png_dimensions(path)
    except AssertionError as exc:
        assert "trailing compressed bytes" in str(exc) or "zlib stream" in str(exc), str(exc)
    else:
        raise AssertionError("validator accepted trailing bytes after the PNG zlib stream")

print("ANNEESSENS_PNG_TRAILING_ZLIB_PAYLOAD_REGRESSION_GREEN")
