#!/usr/bin/env python3
from __future__ import annotations
import importlib.util, json, shutil, tempfile
from pathlib import Path

HERE=Path(__file__).resolve()
GAME_ROOT=HERE.parents[2]
MODULE=HERE.with_name("review_anneessens_canonical_cell_registration.py")
spec=importlib.util.spec_from_file_location("anneessens_review",MODULE); assert spec and spec.loader
review=importlib.util.module_from_spec(spec); spec.loader.exec_module(review)

def copy_fixture(dst: Path) -> Path:
    game=dst/"grand-bruxelles-game"
    shutil.copytree(GAME_ROOT/review.SOURCE_REL,game/review.SOURCE_REL)
    for rel in (review.SOURCE_LOCK,review.SOURCE_CONTRACT,review.MUNICIPAL_LOCK,review.REGISTERED_INDEX):
        target=game/rel; target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(GAME_ROOT/rel,target)
    return game

def write(path: Path,payload: dict)->None:
    path.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

def expect_red(mutator,label):
    with tempfile.TemporaryDirectory() as tmp:
        game=copy_fixture(Path(tmp)); mutator(game)
        try: review.build_review(game,"fixture-main")
        except RuntimeError: return
        raise AssertionError(f"expected fail-closed RED: {label}")

def main():
    base=review.build_review(GAME_ROOT,"fixture-main")
    assert base["status"]=="READY_FOR_CANONICAL_MANIFEST_REVIEW_BOUNDARY_CELL"
    assert base["registration_authorized"] is False
    assert [x["niscode"] for x in base["municipality_boundary"]["intersections"]]==["21013","21001","21004"]

    def collapse(game):
        p=game/review.MUNICIPAL_LOCK; x=review.load(p)
        x["municipality_coverage"]["intersections"]=x["municipality_coverage"]["intersections"][:1]
        x["municipality_coverage"]["municipality_id"]=x["municipality_coverage"]["intersections"][0]["municipality_id"]
        x["municipality_coverage"]["municipality_niscode"]="21013"; write(p,x)
    def mutate_raw(game):
        p=game/review.SOURCE_REL/"raw/buildings.geojson"; p.write_bytes(p.read_bytes()+b"\n")
    def open_gate(game):
        p=game/review.SOURCE_LOCK; x=review.load(p); x["runtime_mount_authorized"]=True; write(p,x)
    def premature_registration(game):
        p=game/review.REGISTERED_INDEX; x=review.load(p); x["entries"].append({"cell_id":review.CELL_ID}); write(p,x)
    def reorder_municipalities(game):
        p=game/review.MUNICIPAL_LOCK; x=review.load(p); x["municipality_coverage"]["intersections"]=list(reversed(x["municipality_coverage"]["intersections"])); write(p,x)

    expect_red(collapse,"dominant municipality shortcut")
    expect_red(mutate_raw,"persisted source byte drift")
    expect_red(open_gate,"runtime authorization widening")
    expect_red(premature_registration,"premature canonical registration")
    expect_red(reorder_municipalities,"municipality identity/order drift")
    print("ANNEESSENS_CANONICAL_REGISTRATION_REVIEW_REGRESSIONS_OK")
if __name__=="__main__": main()
