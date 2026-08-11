#!/usr/bin/env python3
from __future__ import annotations

import sys
import urllib.request

GTFS_URL = "https://datasets.api.production.belgianmobility.io/api/datasets-static/gtfs"


def main() -> int:
    request = urllib.request.Request(
        GTFS_URL,
        headers={"Accept": "application/zip", "User-Agent": "Grand-Bruxelles-Game/1.0"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = response.read(64)
            content_type = response.headers.get("Content-Type", "")
            if response.status == 200 and payload[:2] == b"PK":
                print(
                    "STIB_PUBLIC_ENDPOINT_OK: "
                    f"status=200 content_type={content_type!r} zip_prefix=true"
                )
                return 0
            print(
                f"STIB_PUBLIC_ENDPOINT_FAIL: status={response.status} "
                f"content_type={content_type!r} prefix={payload!r}",
                file=sys.stderr,
            )
            return 1
    except Exception as exc:
        print(f"STIB_PUBLIC_ENDPOINT_FAIL: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
