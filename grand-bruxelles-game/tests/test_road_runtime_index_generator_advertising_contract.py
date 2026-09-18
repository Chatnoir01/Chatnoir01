from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tools" / "build_road_runtime_index.py"


def test_runtime_index_generator_keeps_destination_advertising_fail_closed() -> None:
    text = BUILDER.read_text(encoding="utf-8")

    required = [
        '"destination_advertisable"',
        '"destination_advertisable": False',
        '"jouable_authorized", "destination_advertisable"',
    ]
    for marker in required:
        assert marker in text, f"runtime-index generator lost fail-closed advertising contract: {marker}"

    assert text.count('"destination_advertisable": False') == 1, (
        "runtime-index generator must have one canonical default for destination advertising"
    )
    assert 'authorization.get(forbidden) is not False' in text, (
        "runtime-index validator must require exact false booleans for promotion rails"
    )
