import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).parents[1]
RESOLVER = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"
RESOLVER_REPO_PATH = "grand-bruxelles-game/game/scripts/automatic_road_direct_spawn.gd"


def _outside_loader(text: str) -> tuple[str, str]:
    loader_start = text.index("func _load_runtime_index() -> bool:")
    loader_end = text.index("\n\nfunc runtime_index_road_count()", loader_start)
    return text[:loader_start], text[loader_end:]


def test_source_auth_fix_preserves_existing_spawn_safety_pipeline() -> None:
    """Prevent a focused runtime-index auth patch from deleting unrelated proven safety logic."""
    text = RESOLVER.read_text(encoding="utf-8")

    required_functions = (
        "func _source_building_polygons(",
        "func _point_inside_any_source_building(",
        "func _segment_clear_of_source_buildings(",
        "func _source_view_corridor_clearance(",
        "func _source_building_clearance(",
        "func _source_endpoint_continuation_count(",
        "func _safe_viewpoint(",
        "func _nearby_corridor_anchor(",
        "func _corridor_oriented_target(",
        "func apply_to_player(",
    )
    for signature in required_functions:
        assert signature in text, f"focused source-auth change removed unrelated resolver contract: {signature}"

    loader_start = text.index("func _load_runtime_index() -> bool:")
    loader_end = text.index("\n\nfunc runtime_index_road_count()", loader_start)
    loader = text[loader_start:loader_end]

    # The auth correction is allowed to mutate the loader, not erase downstream
    # source-building, viewpoint, collision or player-application contracts.
    assert "_road_source_path_by_id.clear()" in loader
    assert "_source_sha_by_path.clear()" in loader
    assert "_runtime_index_valid = false" in loader


def test_source_auth_fix_changes_only_loader_bytes_against_pr_base() -> None:
    """Fail closed if this focused owner mutates any resolver byte outside the loader."""
    base_sha = os.environ.get("SOURCE_AUTH_BASE_SHA", "").strip()
    if not base_sha:
        # Local/unit invocation has no authoritative PR base. CI supplies it.
        return

    base_text = subprocess.run(
        ["git", "show", f"{base_sha}:{RESOLVER_REPO_PATH}"],
        cwd=ROOT.parent,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    head_text = RESOLVER.read_text(encoding="utf-8")

    base_prefix, base_suffix = _outside_loader(base_text)
    head_prefix, head_suffix = _outside_loader(head_text)
    assert head_prefix == base_prefix, "source-auth owner changed resolver bytes before _load_runtime_index()"
    assert head_suffix == base_suffix, "source-auth owner changed resolver bytes after _load_runtime_index()"
