#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools" / "data_factory"
EXPECTED_BASE = "96e26ee71f8428ff1ab4887a471c9e35d3174b20"


def run(*args: str, expect: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run([sys.executable, *args], cwd=ROOT, text=True, capture_output=True)
    if result.returncode != expect:
        raise AssertionError(
            f"command returncode {result.returncode} != {expect}: {' '.join(args)}\nstdout={result.stdout}\nstderr={result.stderr}"
        )
    return result


def test_artifact_gate(tmp: Path) -> None:
    artifact = tmp / "artifact"
    artifact.mkdir()
    payload = artifact / "payload.geojson"
    payload.write_text('{"type":"FeatureCollection","features":[]}\n', encoding="utf-8")
    digest = hashlib.sha256(payload.read_bytes()).hexdigest()
    manifest = artifact / "manifest.json"
    manifest.write_text(json.dumps({
        "license": "CC0",
        "crs": "EPSG:31370",
        "runtime_authorized": False,
        "production_authorized": False,
        "results": [{"file": "payload.geojson", "bytes": payload.stat().st_size, "sha256": digest}],
    }), encoding="utf-8")
    summary = artifact / "verification.json"
    run(str(TOOLS / "verify_intake_artifact.py"), "--manifest", str(manifest), "--root", str(artifact), "--require-crs", "--summary", str(summary))
    parsed = json.loads(summary.read_text(encoding="utf-8"))
    assert parsed["result"] == "ARTIFACT_VERIFIED"
    assert parsed["verified_file_count"] == 1
    assert parsed["reuse_terms_resolved"] is True
    assert parsed["production_gate"] == "TERMS_OK"

    unresolved = artifact / "manifest-unresolved.json"
    unresolved.write_text(json.dumps({
        "license": "REUSE_TERMS_UNRESOLVED_PER_LAYER",
        "runtime_authorized": False,
        "production_authorized": False,
        "results": [{"file": "payload.geojson", "bytes": payload.stat().st_size, "sha256": digest}],
    }), encoding="utf-8")
    unresolved_summary = artifact / "verification-unresolved.json"
    run(str(TOOLS / "verify_intake_artifact.py"), "--manifest", str(unresolved), "--root", str(artifact), "--summary", str(unresolved_summary))
    parsed_unresolved = json.loads(unresolved_summary.read_text(encoding="utf-8"))
    assert parsed_unresolved["result"] == "ARTIFACT_VERIFIED"
    assert parsed_unresolved["reuse_terms_resolved"] is False
    assert parsed_unresolved["production_gate"] == "TERMS_BLOCKED"

    payload.write_text("tampered", encoding="utf-8")
    result = subprocess.run(
        [sys.executable, str(TOOLS / "verify_intake_artifact.py"), "--manifest", str(manifest), "--root", str(artifact), "--require-crs"],
        cwd=ROOT, text=True, capture_output=True,
    )
    assert result.returncode != 0, "tampered artifact must fail"


def test_urbis_addresses(tmp: Path) -> None:
    numbers = tmp / "AddressNumbers.geojson"
    addresses = tmp / "Addresses.geojson"
    numbers.write_text(json.dumps({
        "type": "FeatureCollection",
        "features": [{
            "type": "Feature",
            "id": "fallback-id",
            "geometry": {"type": "Point", "coordinates": [147900.0, 169600.0]},
            "properties": {
                "INSPIRE_ID": "addr-1", "STRNAMEFRE": "Rue Exemple", "STRNAMEDUT": "Voorbeeldstraat",
                "POLICENUM": "12A", "MUNNAMEFRE": "Bruxelles", "MUNNAMEDUT": "Brussel", "POSTCODE": "1000"
            }
        }]
    }), encoding="utf-8")
    addresses.write_text(json.dumps({"type":"FeatureCollection","features":[]}), encoding="utf-8")
    output = tmp / "addresses-normalized.json"
    run(str(TOOLS / "normalize_urbis_addresses.py"), "--address-numbers", str(numbers), "--addresses", str(addresses), "--output", str(output), "--license", "CC0-test")
    parsed = json.loads(output.read_text(encoding="utf-8"))
    record = parsed["records"][0]
    assert parsed["stats"]["normalized_record_count"] == 1
    assert record["source_id"] == "addr-1" and record["house_number"] == "12A"
    assert record["game_xz"] == [31.706, -61.376]
    assert parsed["runtime_authorized"] is False


def test_stib_open_data(tmp: Path) -> None:
    stops = tmp / "gtfs-stops-production.csv"
    stops.write_text("stop_id,stop_name,stop_lat,stop_lon\nS1,Gare du Midi,50.836,4.336\n", encoding="utf-8")
    network = tmp / "shapefiles-production.geojson"
    network.write_text(json.dumps({
        "type": "FeatureCollection",
        "features": [
            {"type":"Feature","id":"line-3","geometry":{"type":"LineString","coordinates":[[4.336,50.836],[4.337,50.837]]},"properties":{"source_label":"published-commercial-route"}},
            {"type":"Feature","id":"stop-point","geometry":{"type":"Point","coordinates":[4.336,50.836]},"properties":{"source_label":"published-stop-position"}}
        ]
    }), encoding="utf-8")
    output = tmp / "stib-open-data-normalized.json"
    run(str(TOOLS / "normalize_stib_open_data.py"), "--stops", str(stops), "--network-shapes", str(network), "--output", str(output), "--license", "STIB-test")
    parsed = json.loads(output.read_text(encoding="utf-8"))
    assert parsed["stats"]["normalized_stop_count"] == 1
    assert parsed["stats"]["normalized_network_feature_count"] == 2
    assert "routes" not in parsed and "trips" not in parsed
    assert parsed["runtime_authorized"] is False


def test_stib_gtfs(tmp: Path) -> None:
    gtfs = tmp / "stib.zip"
    with zipfile.ZipFile(gtfs, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("stops.txt", "stop_id,stop_name,stop_lat,stop_lon,wheelchair_boarding\nS1,Gare du Midi,50.836,4.336,1\n")
        zf.writestr("routes.txt", "route_id,route_short_name,route_long_name,route_type,route_color,route_text_color\nR1,3,Tram 3,0,FFCC00,000000\n")
        zf.writestr("trips.txt", "route_id,service_id,trip_id,trip_headsign,direction_id,shape_id\nR1,WK,T1,Esplanade,0,SH1\n")
        zf.writestr("shapes.txt", "shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence\nSH1,50.836,4.336,1\nSH1,50.837,4.337,2\n")
    output = tmp / "stib-normalized.json"
    run(str(TOOLS / "normalize_stib_gtfs.py"), "--gtfs", str(gtfs), "--output", str(output), "--license", "STIB-test", "--include-shapes")
    parsed = json.loads(output.read_text(encoding="utf-8"))
    assert parsed["stats"] == {"stop_count":1,"route_count":1,"trip_count":1,"shape_count":1}
    assert parsed["routes"][0]["colour"] == "FFCC00"
    assert parsed["runtime_authorized"] is False


def test_planning_permits(tmp: Path) -> None:
    source = tmp / "permits.json"
    source.write_text(json.dumps([
        {"numero_dossier":"PU-1","adresse":"Rue Exemple 12, 1000 Bruxelles","date_decision":"2026-07-01","objet":"transformation facade"}
    ]), encoding="utf-8")
    output = tmp / "permit-signals.json"
    run(str(TOOLS / "normalize_planning_permit_signals.py"), "--input", str(source), "--output", str(output), "--license", "CC0 1.0")
    parsed=json.loads(output.read_text(encoding="utf-8"))
    sig=parsed["signals"][0]
    assert sig["permit_id"] == "PU-1"
    assert sig["exact_building_crosswalk"] is False and sig["requires_review"] is True
    assert parsed["runtime_authorized"] is False


def write_minimal_xlsx(path: Path) -> None:
    workbook='''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Periods" sheetId="1" r:id="rId1"/></sheets></workbook>'''
    rels='''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'''
    sheet='''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Municipality</t></is></c><c r="B1" t="inlineStr"><is><t>Before 1919</t></is></c></row><row r="2"><c r="A2" t="inlineStr"><is><t>Bruxelles</t></is></c><c r="B2"><v>42</v></c></row></sheetData></worksheet>'''
    with zipfile.ZipFile(path,"w",compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("xl/workbook.xml",workbook)
        zf.writestr("xl/_rels/workbook.xml.rels",rels)
        zf.writestr("xl/worksheets/sheet1.xml",sheet)


def test_statistical_xlsx(tmp: Path) -> None:
    source=tmp/"periods.xlsx"; write_minimal_xlsx(source)
    output=tmp/"periods-evidence.json"
    run(str(TOOLS/"extract_statistical_xlsx.py"),"--xlsx",str(source),"--output",str(output),"--publisher","Statbel","--license","CC BY 4.0")
    parsed=json.loads(output.read_text(encoding="utf-8"))
    assert parsed["stats"] == {"file_count":1,"sheet_count":1}
    assert parsed["source"]["files"][0]["sheets"][0]["name"] == "Periods"
    assert parsed["runtime_authorized"] is False


def test_context_archive(tmp: Path) -> None:
    source=tmp/"context.zip"
    with zipfile.ZipFile(source,"w",compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("data/context.tif",b"synthetic-raster-placeholder")
        zf.writestr("data/readme.txt",b"metadata")
    output=tmp/"context-inventory.json"
    run(str(TOOLS/"inspect_context_geospatial_archive.py"),"--archive",str(source),"--output",str(output),"--publisher","Brussels Environment","--license","CC BY 4.0","--semantic-role","context only")
    parsed=json.loads(output.read_text(encoding="utf-8"))
    assert parsed["stats"]["archive_count"] == 1
    assert parsed["stats"]["geospatial_member_count"] == 1
    assert parsed["runtime_authorized"] is False

    unsafe=tmp/"unsafe-context.zip"
    with zipfile.ZipFile(unsafe,"w") as zf:
        zf.writestr("../escape.tif",b"bad")
    result=subprocess.run([sys.executable,str(TOOLS/"inspect_context_geospatial_archive.py"),"--archive",str(unsafe),"--output",str(tmp/"bad.json"),"--publisher","x","--license","CC0","--semantic-role","test"],cwd=ROOT,text=True,capture_output=True)
    assert result.returncode != 0


def test_queue_contract() -> None:
    queue=json.loads((ROOT/"data"/"processing"/"data_factory_processing_queue.json").read_text(encoding="utf-8"))
    assert queue["production_base_sha"] == EXPECTED_BASE and queue["runtime_authorized"] is False
    families={item["family"]:item for item in queue["queue"]}
    assert families["mobiris_traffic_counts"]["processor"] == "grand-bruxelles-game/tools/build_brussels_mobility_traffic_snapshot.py"
    assert families["stib_static_schedule"]["state"] == "PROCESSOR_READY_ARTIFACT_BLOCKED"
    assert families["planning_permit_change_signals"]["state"] == "PROCESSOR_READY_ARTIFACT_BLOCKED"
    assert "TERMS_BLOCKED" in families["ibsa_building_age_context"]["state"]
    assert families["impervious_surface_context"]["processor"].endswith("inspect_context_geospatial_archive.py")
    assert families["heat_island_context"]["processor"].endswith("inspect_context_geospatial_archive.py")
    assert families["flood_hazard_context"]["processor"] is None
    assert (ROOT/"tools"/"build_brussels_mobility_traffic_snapshot.py").is_file()
    assert (ROOT/"tools"/"citygen"/"validate_cell_elevation_archives.py").is_file()
    assert (ROOT/"tools"/"citygen"/"validate_cell_elevation_rasters.py").is_file()


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        tmp=Path(td)
        test_artifact_gate(tmp)
        test_urbis_addresses(tmp)
        test_stib_open_data(tmp)
        test_stib_gtfs(tmp)
        test_planning_permits(tmp)
        test_statistical_xlsx(tmp)
        test_context_archive(tmp)
    test_queue_contract()
    print("DATA_FACTORY_PROCESSOR_TESTS_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
