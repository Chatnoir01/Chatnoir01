#!/usr/bin/env python3
"""Fail closed until runtime-index registration authenticates source bytes before intake."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "game/scripts/automatic_road_direct_spawn.gd"
text = SOURCE.read_text(encoding="utf-8")

start = text.index("func _load_runtime_index() -> bool:")
end = text.index("\n\nfunc runtime_index_road_count()", start)
loader = text[start:end]

required = [
    "if staged_source_sha_by_path.has(source_path):",
    "if not FileAccess.file_exists(source_path):",
    "var actual_sha := FileAccess.get_sha256(source_path).to_lower()",
    "if actual_sha.is_empty() or actual_sha != expected_sha:",
    "staged_source_sha_by_path[source_path] = actual_sha",
    "for raw_id: Variant in road_ids:",
]
for needle in required:
    assert needle in loader, f"missing verified-digest registration contract: {needle}"

positions = [loader.index(needle) for needle in required]
assert positions == sorted(positions), (
    "duplicate rejection and source authentication must precede staging and road-id intake"
)
assert "staged_source_sha_by_path[source_path] = expected_sha" not in loader, (
    "declared digest must never become staged authority before byte authentication"
)

# Defense in depth remains mandatory at lookup time as well.
lookup_start = text.index("func _source_bundle_by_id(osm_id: int) -> Dictionary:")
lookup_end = text.index("\n\nfunc _exact_source_point_2d", lookup_start)
lookup = text[lookup_start:lookup_end]
assert "FileAccess.get_sha256(path).to_lower()" in lookup
assert "actual_sha != expected_sha" in lookup

print("PASS: duplicate rejection and verified source digest precede runtime-index road intake")
