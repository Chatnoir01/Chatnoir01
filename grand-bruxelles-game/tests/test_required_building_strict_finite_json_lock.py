#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
VALIDATOR = PROJECT / "tools" / "validate_required_building_urbis_crosswalk_lock.py"
SOURCE = PROJECT / "data" / "osm" / "vertical_slice_01.game.json"


def run(source: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(VALIDATOR), "--source", str(source)],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        check=False,
    )


def main() -> int:
    canonical = run(SOURCE)
    assert canonical.returncode == 0, canonical.stdout + canonical.stderr

    raw = SOURCE.read_text(encoding="utf-8")
    # Causal witness: JSON's standard numeric grammar permits 1e309, but Python's
    # default json decoder materializes it as +inf. Put it in an unrelated field so
    # the existing Bourse semantic comparisons cannot catch it. A strict source lock
    # must reject non-finite decoded numbers anywhere in the document.
    assert raw.rstrip().endswith("}")
    mutated = raw.rstrip()[:-1] + ',"strict_finite_json_witness":1e309}'

    with tempfile.TemporaryDirectory(prefix="gb-bourse-finite-json-") as tmp:
        source = Path(tmp) / "vertical_slice_01.game.json"
        source.write_text(mutated, encoding="utf-8")
        result = run(source)
        assert result.returncode != 0, (
            "Bourse crosswalk lock accepted finite-syntax numeric overflow (1e309); "
            "strict JSON intake must fail closed on decoded non-finite floats\n"
            + result.stdout
            + result.stderr
        )

    print("REQUIRED_BUILDING_STRICT_FINITE_JSON_LOCK_TEST_OK network_used=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
