#!/usr/bin/env python3
"""Download one locked UrbIS package with strict wall-clock and slow-link bounds.

This helper exists because urllib HTTPResponse.read() can remain alive indefinitely
when a server trickles bytes often enough to avoid the socket timeout. CI needs an
actual per-attempt wall-clock cap. curl provides that via --max-time plus a minimum
transfer speed window; this wrapper adds host validation, explicit retries, logging,
and a required SHA-256 check for production use.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

OFFICIAL_HOST = "urbisdownload.datastore.brussels"


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_url(url: str, allowed_host: str, allow_http: bool) -> None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ({"http", "https"} if allow_http else {"https"}):
        raise RuntimeError(f"unsupported URL scheme: {parsed.scheme!r}")
    if (parsed.hostname or "").lower() != allowed_host.lower():
        raise RuntimeError(
            f"download host drift: {(parsed.hostname or '').lower()!r} != {allowed_host.lower()!r}"
        )


def download(
    url: str,
    output: Path,
    *,
    expected_sha256: str | None,
    allowed_host: str = OFFICIAL_HOST,
    allow_http: bool = False,
    connect_timeout_seconds: float = 20.0,
    attempt_max_seconds: float = 240.0,
    slow_speed_bytes_per_second: int = 1024,
    slow_speed_window_seconds: int = 30,
    retries: int = 4,
) -> dict[str, object]:
    validate_url(url, allowed_host, allow_http)
    if retries < 1:
        raise RuntimeError("retries must be >= 1")
    if connect_timeout_seconds <= 0 or attempt_max_seconds <= 0:
        raise RuntimeError("timeouts must be > 0")
    if slow_speed_bytes_per_second < 1 or slow_speed_window_seconds < 1:
        raise RuntimeError("slow-transfer limits must be positive")
    if expected_sha256 is not None:
        expected_sha256 = expected_sha256.lower()
        if len(expected_sha256) != 64 or any(ch not in "0123456789abcdef" for ch in expected_sha256):
            raise RuntimeError("expected SHA-256 must be 64 lowercase/uppercase hex chars")

    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    temp = output.with_name(output.name + ".part")
    last_error = "not attempted"

    for attempt in range(1, retries + 1):
        temp.unlink(missing_ok=True)
        started = time.monotonic()
        print(
            "URBIS_BOUNDED_DOWNLOAD_ATTEMPT: "
            f"attempt={attempt}/{retries} max_seconds={attempt_max_seconds:g} "
            f"slow_limit={slow_speed_bytes_per_second}Bps/{slow_speed_window_seconds}s",
            flush=True,
        )
        command = [
            "curl",
            "--fail",
            "--location",
            "--silent",
            "--show-error",
            "--connect-timeout",
            str(connect_timeout_seconds),
            "--max-time",
            str(attempt_max_seconds),
            "--speed-limit",
            str(slow_speed_bytes_per_second),
            "--speed-time",
            str(slow_speed_window_seconds),
            "--output",
            str(temp),
            url,
        ]
        try:
            completed = subprocess.run(
                command,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=attempt_max_seconds + 30.0,
            )
        except subprocess.TimeoutExpired:
            elapsed = time.monotonic() - started
            partial_bytes = temp.stat().st_size if temp.exists() else 0
            last_error = f"wrapper subprocess timeout after {elapsed:.1f}s; partial_bytes={partial_bytes}"
            print(f"URBIS_BOUNDED_DOWNLOAD_RETRY: {last_error}", flush=True)
        else:
            elapsed = time.monotonic() - started
            partial_bytes = temp.stat().st_size if temp.exists() else 0
            if completed.returncode != 0:
                stderr = completed.stderr.strip().replace("\n", " | ")
                last_error = (
                    f"curl_exit={completed.returncode} elapsed={elapsed:.1f}s "
                    f"partial_bytes={partial_bytes} stderr={stderr}"
                )
                print(f"URBIS_BOUNDED_DOWNLOAD_RETRY: {last_error}", flush=True)
            elif not temp.is_file() or partial_bytes <= 0:
                last_error = f"empty download elapsed={elapsed:.1f}s"
                print(f"URBIS_BOUNDED_DOWNLOAD_RETRY: {last_error}", flush=True)
            else:
                actual_sha256 = sha256_path(temp)
                if expected_sha256 is not None and actual_sha256 != expected_sha256:
                    last_error = (
                        f"SHA-256 mismatch elapsed={elapsed:.1f}s bytes={partial_bytes} "
                        f"expected={expected_sha256} actual={actual_sha256}"
                    )
                    print(f"URBIS_BOUNDED_DOWNLOAD_RETRY: {last_error}", flush=True)
                else:
                    os.replace(temp, output)
                    print(
                        "URBIS_BOUNDED_DOWNLOAD_OK: "
                        f"attempt={attempt}/{retries} elapsed={elapsed:.1f}s "
                        f"bytes={partial_bytes} sha256={actual_sha256}",
                        flush=True,
                    )
                    return {
                        "attempt": attempt,
                        "elapsed_seconds": elapsed,
                        "bytes": partial_bytes,
                        "sha256": actual_sha256,
                    }

        temp.unlink(missing_ok=True)
        if attempt < retries:
            backoff = min(2 ** attempt, 8)
            print(f"URBIS_BOUNDED_DOWNLOAD_BACKOFF: seconds={backoff}", flush=True)
            time.sleep(backoff)

    raise RuntimeError(f"locked UrbIS package download exhausted {retries} attempts: {last_error}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-sha256")
    parser.add_argument("--allowed-host", default=OFFICIAL_HOST)
    parser.add_argument("--allow-http", action="store_true")
    parser.add_argument("--connect-timeout-seconds", type=float, default=20.0)
    parser.add_argument("--attempt-max-seconds", type=float, default=240.0)
    parser.add_argument("--slow-speed-bytes-per-second", type=int, default=1024)
    parser.add_argument("--slow-speed-window-seconds", type=int, default=30)
    parser.add_argument("--retries", type=int, default=4)
    args = parser.parse_args()
    try:
        download(
            args.url,
            args.output,
            expected_sha256=args.expected_sha256,
            allowed_host=args.allowed_host,
            allow_http=args.allow_http,
            connect_timeout_seconds=args.connect_timeout_seconds,
            attempt_max_seconds=args.attempt_max_seconds,
            slow_speed_bytes_per_second=args.slow_speed_bytes_per_second,
            slow_speed_window_seconds=args.slow_speed_window_seconds,
            retries=args.retries,
        )
    except Exception as exc:
        print(f"URBIS_BOUNDED_DOWNLOAD_ERROR: {exc}", file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
