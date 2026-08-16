#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("resolve", HERE / "resolve_cell_elevation_sources.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def xml(*links: str) -> bytes:
    items = ''.join(f'<link href="{link}" />' for link in links)
    return f'<?xml version="1.0"?><feed>{items}</feed>'.encode()


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    req = root / "requirements.json"
    feed = f"https://{mod.OFFICIAL_HOST}/atomfeed/dsm.xml"
    requirements = {
        "format": mod.REQUIREMENTS_FORMAT,
        "cell_id": "bxl-e149750-n169000-s500",
        "crs": "EPSG:31370",
        "bbox": [149750,169000,150250,169500],
        "expected_1km_tile_codes": ["149169","150169"],
        "official_sources": {
            "dsm": {"dataset_id":"dsm-id","atom_feed":feed},
            "dtm": {"dataset_id":"dtm-id","atom_feed":f"https://{mod.OFFICIAL_HOST}/atomfeed/dtm.xml"},
        },
    }
    req.write_text(json.dumps(requirements), encoding="utf-8")
    child = f"https://{mod.OFFICIAL_HOST}/atomfeed/dsm-child.xml"
    archive_a = f"https://{mod.OFFICIAL_HOST}/data/DSM_149169.zip"
    archive_b = f"https://{mod.OFFICIAL_HOST}/data/DSM_150169.zip"
    payloads = {feed: xml(child), child: xml(archive_b, archive_a, "https://example.invalid/not-official.zip")}
    calls = []
    def fake_fetch(url: str) -> bytes:
        calls.append(url)
        return payloads[url]

    result = mod.build(req, "dsm", fake_fetch)
    assert result["format"] == mod.FORMAT
    assert result["resolved_archives"] == [{"tile":"149169","url":archive_a},{"tile":"150169","url":archive_b}]
    assert result["maturity_effect"]["terrain_gate"] is False
    assert result["maturity_effect"]["heights_gate"] is False
    assert calls == [feed, child]
    assert result["resolution_digest"] == mod._digest({k:v for k,v in result.items() if k != "resolution_digest"})

    duplicate = f"https://{mod.OFFICIAL_HOST}/data/COPY_149169.zip"
    payloads[child] = xml(archive_a, duplicate, archive_b)
    try:
        mod.build(req, "dsm", fake_fetch)
    except ValueError as exc:
        assert "exactly one" in str(exc)
    else:
        raise AssertionError("ambiguous elevation archive must fail closed")

    bad_feed = "https://example.invalid/evil.xml"
    try:
        mod.crawl(bad_feed, lambda _: b"<feed/>")
    except ValueError as exc:
        assert "escaped official elevation host" in str(exc)
    else:
        raise AssertionError("off-domain elevation feed must fail closed")

print("CELL_ELEVATION_SOURCE_RESOLUTION_GUARDRAILS_OK unique=true official_host=true gates_false=true")
