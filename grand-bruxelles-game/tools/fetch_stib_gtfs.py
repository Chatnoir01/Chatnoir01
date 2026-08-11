#!/usr/bin/env python3
"""Download the official STIB-MIVB GTFS archive through the developer API.

Credentials are never stored in the repository. Pass them through environment
variables STIB_CONSUMER_KEY and STIB_CONSUMER_SECRET or explicit CLI options.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

TOKEN_URL = "https://opendata-api.stib-mivb.be/token"
GTFS_URL = "https://opendata-api.stib-mivb.be/Files/1.0/Gtfs"


def request_token(consumer_key: str, consumer_secret: str) -> str:
    raw = f"{consumer_key}:{consumer_secret}".encode("utf-8")
    basic = base64.b64encode(raw).decode("ascii")
    body = urllib.parse.urlencode({"grant_type": "client_credentials"}).encode("ascii")
    request = urllib.request.Request(
        TOKEN_URL,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Basic {basic}",
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
            "User-Agent": "Grand-Bruxelles-Game/1.0",
        },
    )
    with urllib.request.urlopen(request, timeout=45, context=ssl.create_default_context()) as response:
        payload = json.loads(response.read().decode("utf-8"))
    token = str(payload.get("access_token", ""))
    if not token:
        raise RuntimeError("STIB token response did not contain access_token")
    return token


def download_gtfs(token: str, output: Path) -> None:
    request = urllib.request.Request(
        GTFS_URL,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/zip",
            "User-Agent": "Grand-Bruxelles-Game/1.0",
        },
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(request, timeout=90, context=ssl.create_default_context()) as response:
        content_type = response.headers.get("Content-Type", "")
        data = response.read()
    if len(data) < 500 or data[:2] != b"PK":
        raise RuntimeError(
            f"STIB GTFS response is not a ZIP archive: bytes={len(data)} content_type={content_type!r}"
        )
    output.write_bytes(data)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--consumer-key", default=os.getenv("STIB_CONSUMER_KEY", ""))
    parser.add_argument("--consumer-secret", default=os.getenv("STIB_CONSUMER_SECRET", ""))
    args = parser.parse_args()

    if not args.consumer_key or not args.consumer_secret:
        print(
            "STIB_CREDENTIALS_MISSING: configure STIB_CONSUMER_KEY and STIB_CONSUMER_SECRET",
            file=sys.stderr,
        )
        return 2

    try:
        token = request_token(args.consumer_key, args.consumer_secret)
        download_gtfs(token, args.output)
    except urllib.error.HTTPError as exc:
        print(f"STIB_FETCH_HTTP_ERROR status={exc.code}", file=sys.stderr)
        return 3
    except Exception as exc:  # noqa: BLE001 - CLI error boundary
        print(f"STIB_FETCH_FAIL: {exc}", file=sys.stderr)
        return 4

    print(f"STIB_GTFS_FETCH_OK: {args.output} bytes={args.output.stat().st_size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
