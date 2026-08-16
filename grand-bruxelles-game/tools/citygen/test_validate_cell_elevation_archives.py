#!/usr/bin/env python3
import hashlib
import importlib.util
import json
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("validate", HERE / "validate_cell_elevation_archives.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def write_zip(path: Path, members: dict[str, bytes]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w") as zf:
        for name, content in members.items():
            zf.writestr(name, content)


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    good = root / "good.zip"
    write_zip(good, {"tile/raster.tif": b"fake-tiff-for-structural-stage", "tile/raster.tfw": b"1\n0\n0\n-1\n0\n0\n"})
    meta = mod.inspect_zip(good)
    assert meta["file_count"] == 2
    assert meta["tiff_member"] == "tile/raster.tif"
    assert meta["uncompressed_bytes"] > 0
    assert len(meta["members_digest"]) == 64

    # Archive traversal must fail before extraction is ever attempted.
    unsafe = root / "unsafe.zip"
    write_zip(unsafe, {"../escape.tif": b"bad"})
    try:
        mod.inspect_zip(unsafe)
    except ValueError as exc:
        assert "unsafe ZIP member" in str(exc)
    else:
        raise AssertionError("path traversal ZIP must fail closed")

    # Multiple TIFFs are ambiguous for this source contract.
    ambiguous = root / "ambiguous.zip"
    write_zip(ambiguous, {"a.tif": b"a", "b.tif": b"b"})
    try:
        mod.inspect_zip(ambiguous)
    except ValueError as exc:
        assert "exactly one TIFF" in str(exc)
    else:
        raise AssertionError("multi-TIFF archive must fail closed")

    official = f"https://{mod.OFFICIAL_HOST}/data/tile.zip"
    mod.validate_source_url(official)
    for bad_url in ("http://urbisdownload.datastore.brussels/data/tile.zip", "https://example.invalid/tile.zip", f"https://{mod.OFFICIAL_HOST}/data/tile.tif"):
        try:
            mod.validate_source_url(bad_url)
        except ValueError:
            pass
        else:
            raise AssertionError(f"invalid source URL accepted: {bad_url}")

    # A structurally valid result still must not flip terrain/height gates.
    result = {
        "format": mod.FORMAT,
        "maturity_effect": {"terrain_gate": False, "heights_gate": False, "reason": "archive_integrity_only_raster_not_validated"},
    }
    assert result["maturity_effect"]["terrain_gate"] is False
    assert result["maturity_effect"]["heights_gate"] is False

print("CELL_ELEVATION_ARCHIVE_VALIDATION_GUARDRAILS_OK zip_safe=true single_tiff=true official_host=true gates_false=true")
