#!/usr/bin/env python3
"""Validate the official STIB-MIVB developer GTFS endpoint without credentials.

A 401/403 response is expected when no bearer token is supplied. That confirms
we reached the developer API rather than the retired catalog redirect.
"""

from __future__ import annotations

import sys
import urllib.error
import urllib.request

GTFS_URL = "https://opendata-api.stib-mivb.be/Files/1.0/Gtfs"


def main() -> int:
    request = urllib.request.Request(
        GTFS_URL,
        headers={
            "Accept": "application/zip",
            "User-Agent": "Grand-Bruxelles-Game/1.0 (STIB endpoint validation)",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = response.read(32)
            if response.status == 200 and payload[:2] == b"PK":
                print("STIB_DEVELOPER_ENDPOINT_OK: anonymous GTFS ZIP accepted")
                return 0
            print(
                f"STIB_DEVELOPER_ENDPOINT_FAIL: unexpected anonymous response "
                f"status={response.status} prefix={payload!r}",
                file=sys.stderr,
            )
            return 1
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            print(f"STIB_DEVELOPER_ENDPOINT_OK: reachable; authentication required (HTTP {exc.code})")
            return 0
        print(f"STIB_DEVELOPER_ENDPOINT_FAIL: HTTP {exc.code}", file=sys.stderr)
        return 2
    except Exception as exc:  # noqa: BLE001 - diagnostic boundary
        print(f"STIB_DEVELOPER_ENDPOINT_FAIL: {exc}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
