from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "fetch_civ1_pinned_sources.py"

spec = importlib.util.spec_from_file_location("fetch_civ1_pinned_sources", TOOL)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

BODY = "assets/characters/civilians/civ1/source/vitruvian_body.glb"
HEAD = "assets/characters/civilians/civ1/source/vitruvian_head.glb"


def test_select_plan_defaults_to_full_plan() -> None:
    plan = [
        {"relative_path": BODY, "git_blob_sha1": "a"},
        {"relative_path": HEAD, "git_blob_sha1": "b"},
    ]
    assert module.select_plan(plan, []) is plan
    assert module.select_plan(plan, None) is plan


def test_select_plan_is_exact_ordered_and_deduplicated() -> None:
    plan = [
        {"relative_path": BODY, "git_blob_sha1": "a"},
        {"relative_path": HEAD, "git_blob_sha1": "b"},
    ]
    selected = module.select_plan(plan, [HEAD, BODY, HEAD])
    assert [item["relative_path"] for item in selected] == [HEAD, BODY]


def test_select_plan_fails_closed_on_unpinned_path() -> None:
    plan = [{"relative_path": BODY, "git_blob_sha1": "a"}]
    try:
        module.select_plan(plan, ["assets/characters/player_character.glb"])
    except ValueError as exc:
        assert "not pinned" in str(exc)
    else:
        raise AssertionError("unpinned selection must fail closed")


def test_live_manifest_can_select_only_pinned_body() -> None:
    plan = module.load_plan(ROOT)
    selected = module.select_plan(plan, [BODY])
    assert len(selected) == 1
    assert selected[0]["relative_path"] == BODY
    assert selected[0]["git_blob_sha1"] == "09bcade1092e5a89b474e91e6013209d4c68c127"
    assert selected[0]["size_bytes"] == 6879364


if __name__ == "__main__":
    test_select_plan_defaults_to_full_plan()
    test_select_plan_is_exact_ordered_and_deduplicated()
    test_select_plan_fails_closed_on_unpinned_path()
    test_live_manifest_can_select_only_pinned_body()
    print("CIV1_PINNED_SOURCE_SELECTION_GREEN")
