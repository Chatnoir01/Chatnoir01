#!/usr/bin/env python3
"""Fail-closed validator for the frozen Anneessens player-view ray sample contract."""
from __future__ import annotations

import re
import sys
from pathlib import Path

EXPECTED_SAMPLES = ((760, 360), (900, 360), (1100, 360))
TRACE_PREFIX = "ANNEESSENS_VISUAL_BLOCKER_TRACE:"
TRACE_RE = re.compile(
    r"^ANNEESSENS_VISUAL_BLOCKER_TRACE: sample=\((\d+),(\d+)\) hit=(true|false)(?:\s+.*)?$"
)


def fail(message: str) -> None:
    raise AssertionError(message)


def validate(log_text: str) -> tuple[int, int]:
    trace_lines = [line.strip() for line in log_text.splitlines() if line.startswith(TRACE_PREFIX)]
    if len(trace_lines) != len(EXPECTED_SAMPLES):
        fail(f"expected exactly 3 Anneessens visual trace rows, found {len(trace_lines)}")

    parsed_samples: list[tuple[int, int]] = []
    building_hits = 0
    for index, line in enumerate(trace_lines):
        match = TRACE_RE.fullmatch(line)
        if match is None:
            fail(f"trace row {index} does not match the frozen sample format: {line!r}")
        sample = (int(match.group(1)), int(match.group(2)))
        parsed_samples.append(sample)
        if match.group(3) == "true" and "collider_name=Building_" in line:
            building_hits += 1

    if tuple(parsed_samples) != EXPECTED_SAMPLES:
        fail(
            "Anneessens visual trace samples/order drifted: "
            f"expected={EXPECTED_SAMPLES!r} actual={tuple(parsed_samples)!r}"
        )

    return len(parsed_samples), building_hits


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_anneessens_trace_samples.py <runtime.log>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    if not path.is_file() or path.stat().st_size == 0:
        fail("runtime log is missing or empty")
    trace_count, building_hits = validate(path.read_text(encoding="utf-8", errors="replace"))
    print(
        "ANNEESSENS_TRACE_SAMPLE_CONTRACT_GREEN "
        f"trace_count={trace_count} building_hits={building_hits} samples={EXPECTED_SAMPLES!r}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"ANNEESSENS_TRACE_SAMPLE_CONTRACT_FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
