#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import shutil
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve()
GAME_ROOT = HERE.parents[2]
MODULE_PATH = HERE.with_name("review_bourse_canonical_cell_registration.py")
spec = importlib.util.spec_from_file_location("bourse_review", MODULE_PATH)
assert spec and spec.loader
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)


def copy_fixture(dst: Path) -> Path:
    game = dst / "grand-bruxelles-game"
    src_cell = GAME_ROOT / review.SOURCE_REL
    dst_cell = game / review.SOURCE_REL
    dst_cell.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src_cell, dst_cell)
    for rel in (review.SOURCE_LOCK, review.MUNICIPAL_LOCK, review.REGISTERED_INDEX):
        target = game / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(GAME_ROOT / rel, target)
    return game


def expect_red(mutator, label: str) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        game = copy_fixture(Path(tmp))
        mutator(game)
        try:
            review.build_review(game, "fixture-main")
        except RuntimeError:
            return
        raise AssertionError(f"expected fail-closed RED: {label}")


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    baseline = review.build_review(GAME_ROOT, "fixture-main")
    assert baseline["status"] == "READY_FOR_CANONICAL_MANIFEST_REVIEW_BOUNDARY_CELL"
    assert baseline["registration_authorized"] is False
    assert len(baseline["municipality_boundary"]["intersections"]) == 2

    def collapse_boundary(game: Path) -> None:
        path = game / review.MUNICIPAL_LOCK
        payload = review.load(path)
        payload["stable_measurement"]["municipality_coverage"]["intersections"] = payload["stable_measurement"]["municipality_coverage"]["intersections"][:1]
        payload["stable_measurement"]["municipality_coverage"]["municipality_id"] = "https://databrussels.be/id/municipality/5000071"
        payload["stable_measurement"]["municipality_coverage"]["municipality_niscode"] = "21001"
        write_json(path, payload)

    def open_runtime_gate(game: Path) -> None:
        path = game / review.SOURCE_LOCK
        payload = review.load(path)
        payload["runtime_mount_authorized"] = True
        write_json(path, payload)

    def mutate_raw_source(game: Path) -> None:
        path = game / review.SOURCE_REL / "raw/buildings.geojson"
        path.write_bytes(path.read_bytes() + b"\n")

    def pre_register_target(game: Path) -> None:
        path = game / review.REGISTERED_INDEX
        payload = review.load(path)
        payload["entries"].append({"cell_id": review.CELL_ID})
        write_json(path, payload)

    expect_red(collapse_boundary, "dominant municipality shortcut")
    expect_red(open_runtime_gate, "runtime authorization widening")
    expect_red(mutate_raw_source, "persisted source byte drift")
    expect_red(pre_register_target, "review phase after target registration")
    print("BOURSE_CANONICAL_REGISTRATION_REVIEW_REGRESSIONS_OK")


if __name__ == "__main__":
    main()
