#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
import urllib.request
from pathlib import Path

# MobilityDatabase currently classifies this producer URL as the STIB/MIVB
# Official Feed. Freshness is validated separately before runtime activation.
GTFS_URL = "https://stibmivb.opendatasoft.com/api/datasets/1.0/gtfs-files-production/alternative_exports/gtfszip/"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    request = urllib.request.Request(
        GTFS_URL,
        headers={"Accept": "application/zip", "User-Agent": "Grand-Bruxelles-Game/1.0"},
    )
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            data = response.read()
    except Exception as exc:
        print(f"STIB_FETCH_FAIL: {exc}", file=sys.stderr)
        return 1
    if len(data) < 500 or data[:2] != b"PK":
        print(f"STIB_FETCH_FAIL: invalid ZIP response ({len(data)} bytes)", file=sys.stderr)
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    print(f"STIB_GTFS_FETCH_OK: {args.output} bytes={len(data)} source={GTFS_URL}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
