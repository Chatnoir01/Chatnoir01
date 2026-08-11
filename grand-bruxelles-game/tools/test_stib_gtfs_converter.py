#!/usr/bin/env python3
"""Self-contained test for convert_stib_gtfs.py using a synthetic GTFS ZIP."""

from __future__ import annotations

import csv
import importlib.util
import io
import tempfile
import zipfile
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("stib_converter", HERE / "convert_stib_gtfs.py")
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def csv_bytes(fieldnames: list[str], rows: list[dict[str, str]]) -> bytes:
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue().encode("utf-8")


def build_fixture(path: Path) -> None:
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr(
            "routes.txt",
            csv_bytes(
                ["route_id", "route_short_name", "route_long_name", "route_type", "route_color", "route_text_color"],
                [
                    {"route_id": "T1", "route_short_name": "81", "route_long_name": "Tram test", "route_type": "0", "route_color": "FFAA00", "route_text_color": "000000"},
                    {"route_id": "B1", "route_short_name": "48", "route_long_name": "Bus test", "route_type": "3", "route_color": "0055AA", "route_text_color": "FFFFFF"},
                    {"route_id": "M1", "route_short_name": "2", "route_long_name": "Metro ignored", "route_type": "1", "route_color": "", "route_text_color": ""},
                ],
            ),
        )
        zf.writestr(
            "trips.txt",
            csv_bytes(
                ["route_id", "service_id", "trip_id", "shape_id"],
                [
                    {"route_id": "T1", "service_id": "WK", "trip_id": "t", "shape_id": "shape_tram"},
                    {"route_id": "B1", "service_id": "WK", "trip_id": "b", "shape_id": "shape_bus"},
                    {"route_id": "M1", "service_id": "WK", "trip_id": "m", "shape_id": "shape_metro"},
                ],
            ),
        )
        zf.writestr(
            "shapes.txt",
            csv_bytes(
                ["shape_id", "shape_pt_lat", "shape_pt_lon", "shape_pt_sequence"],
                [
                    {"shape_id": "shape_tram", "shape_pt_lat": "50.8419", "shape_pt_lon": "4.3480", "shape_pt_sequence": "1"},
                    {"shape_id": "shape_tram", "shape_pt_lat": "50.8422", "shape_pt_lon": "4.3484", "shape_pt_sequence": "2"},
                    {"shape_id": "shape_bus", "shape_pt_lat": "50.8418", "shape_pt_lon": "4.3478", "shape_pt_sequence": "1"},
                    {"shape_id": "shape_bus", "shape_pt_lat": "50.8420", "shape_pt_lon": "4.3481", "shape_pt_sequence": "2"},
                    {"shape_id": "shape_metro", "shape_pt_lat": "50.8419", "shape_pt_lon": "4.3480", "shape_pt_sequence": "1"},
                    {"shape_id": "shape_metro", "shape_pt_lat": "50.8420", "shape_pt_lon": "4.3481", "shape_pt_sequence": "2"},
                ],
            ),
        )
        zf.writestr(
            "stops.txt",
            csv_bytes(
                ["stop_id", "stop_name", "stop_lat", "stop_lon"],
                [{"stop_id": "S1", "stop_name": "Midi test", "stop_lat": "50.8419", "stop_lon": "4.3480"}],
            ),
        )
        zf.writestr(
            "calendar.txt",
            csv_bytes(
                ["service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "start_date", "end_date"],
                [{
                    "service_id": "WK", "monday": "1", "tuesday": "1", "wednesday": "1", "thursday": "1",
                    "friday": "1", "saturday": "1", "sunday": "1", "start_date": "20260101", "end_date": "20261231",
                }],
            ),
        )


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        gtfs = Path(tmp) / "synthetic.zip"
        build_fixture(gtfs)
        current = MODULE.convert(gtfs, radius_m=2000.0, today=date(2026, 8, 12))
        stale = MODULE.convert(gtfs, radius_m=2000.0, today=date(2027, 1, 5))

    assert current["format"] == "grand-bruxelles-stib-gtfs-v1"
    assert current["stats"]["routes"] == 2, current["stats"]
    assert current["stats"]["tram_routes"] == 1, current["stats"]
    assert current["stats"]["bus_routes"] == 1, current["stats"]
    assert current["stats"]["shapes"] == 2, current["stats"]
    assert current["stats"]["stops"] == 1, current["stats"]
    assert {r["mode"] for r in current["routes"]} == {"tram", "bus"}
    assert all(len(shape["points"]) >= 2 for shape in current["shapes"])
    assert current["freshness"]["service_start"] == "2026-01-01", current["freshness"]
    assert current["freshness"]["service_end"] == "2026-12-31", current["freshness"]
    assert current["freshness"]["runtime_current_eligible"] is True, current["freshness"]
    assert stale["freshness"]["current_coverage"] is False, stale["freshness"]
    assert stale["freshness"]["runtime_current_eligible"] is False, stale["freshness"]
    print("STIB_GTFS_CONVERTER_OK: surface modes + freshness gate passed", current["stats"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
