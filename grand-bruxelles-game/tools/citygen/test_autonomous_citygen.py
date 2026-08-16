#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("autonomous_citygen", HERE / "autonomous_citygen.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp); source = root / "source"; maturity = root / "maturity"; out1 = root / "out1"; out2 = root / "out2"; target_grid = root / "target_grid.json"
    cells = ["bxl-e149000-n169000-s500","bxl-e149000-n169500-s500","bxl-e149500-n169000-s500","bxl-e149500-n169500-s500","bxl-e150000-n169000-s500"]
    for cell in cells[:4]: write_json(source / cell / "manifest.json", {"cell_id": cell, "layers": ["buildings"]})
    write_json(target_grid,{"format":"grand-bruxelles-regional-target-grid-v1","crs":"EPSG:31370","cell_size_m":500.0,"cells":[{"cell_id":cell,"bbox":[149000+i*500,169000,149500+i*500,169500],"municipalities":["test"]} for i,cell in enumerate(cells)]})
    legacy_gates=("runtime_geometry","collisions","streaming","terrain","heights","photo_match","performance")
    all_gates=mod.MATURITY_GATES
    assert len(all_gates) == 16
    assert set(legacy_gates).issubset(set(all_gates))
    assert {"source_requirements","crs","materials","facade","clutter","mobility","verification","license","region_scalable"}.issubset(set(all_gates))
    write_json(maturity/f"{cells[0]}.json",{"cell_id":cells[0],"crs":"EPSG:31370","geometry":{"authoritative_geometry_ready":True},"maturity":{"gates":{name:True for name in all_gates}}})
    write_json(maturity/f"{cells[1]}.json",{"cell_id":cells[1],"crs":"EPSG:31370","geometry":{"authoritative_geometry_ready":True},"maturity":{"gates":{"runtime_geometry":False}}})
    write_json(maturity/f"{cells[2]}.json",{"cell_id":cells[2],"crs":"EPSG:4326","geometry":{"authoritative_geometry_ready":True},"maturity":{"gates":{}}})
    write_json(source/cells[3]/"maturity.json",{"cell_id":cells[3],"crs":"EPSG:31370","geometry":{"authoritative_geometry_ready":True},"maturity":{"gates":{name:False for name in all_gates}}})

    # Regression: the legacy seven runtime gates are insufficient for a
    # Region-scale mature cell. A legacy-complete manifest must remain pending
    # until production evidence exists for sources/materials/facade/clutter,
    # mobility, verification, licensing and hero-independent scalability.
    contract_source = root / "contract-source"
    contract_maturity = root / "contract-maturity"
    legacy_cell = "bxl-e160000-n175000-s500"
    write_json(contract_source / legacy_cell / "manifest.json", {"cell_id": legacy_cell, "crs": "EPSG:31370", "layers": ["buildings"]})
    write_json(
        contract_maturity / f"{legacy_cell}.json",
        {
            "cell_id": legacy_cell,
            "crs": "EPSG:31370",
            "geometry": {"authoritative_geometry_ready": True},
            "maturity": {"gates": {name: True for name in legacy_gates}},
        },
    )
    legacy_state, legacy_blockers = mod.classify_cell(legacy_cell, contract_source, contract_maturity)
    assert legacy_state == "DATA_READY", (legacy_state, legacy_blockers)
    assert {
        "source_requirements",
        "crs",
        "materials",
        "facade",
        "clutter",
        "mobility",
        "verification",
        "license",
        "region_scalable",
    }.issubset(set(legacy_blockers)), legacy_blockers

    report1=mod.run(source,maturity,None,out1,2,target_grid)
    assert report1["source_cell_count"]==4 and report1["target_cell_count"]==5
    assert report1["counts"]=={"DATA_READY":2,"MISSING_SOURCE":1,"QUARANTINE":1,"RUNTIME_READY":1},report1["counts"]
    assert report1["policy"]["maturity_gate_count"] == len(all_gates)
    assert report1["policy"]["runtime_promotion"] == "forbidden_without_full_regional_maturity_contract"
    # Existing authoritative source cells must mature before CityGen expands into
    # a new MISSING_SOURCE cell, otherwise a large target grid can starve evidence.
    assert report1["selected_batch"]==[cells[1],cells[3]],report1["selected_batch"]
    local=next(cell for cell in report1["cells"] if cell["cell_id"]==cells[3])
    assert local["state"]=="DATA_READY" and "terrain" in local["blockers"]
    assert local["next_action"]=="derive_elevation_requirements" and local["evidence_progress"]==0
    missing=next(cell for cell in report1["cells"] if cell["cell_id"]==cells[4])
    assert missing["state"]=="MISSING_SOURCE" and missing["bbox"]==[151000,169000,151500,169500]
    assert missing["next_action"]=="materialize_authoritative_source"

    report2=mod.run(source,maturity,out1/"autonomous_citygen_state.json",out2,2,target_grid)
    attempts={cell["cell_id"]:cell["attempts"] for cell in report2["cells"]}
    assert report2["run_number"]==2
    assert attempts[cells[4]]==0
    assert attempts[cells[1]]==2
    assert attempts[cells[3]]==2
    assert attempts[cells[0]]==0 and attempts[cells[2]]==0

    rotation=[{"cell_id":"bxl-e100000-n100000-s500","state":"DISCOVERED","attempts":3},{"cell_id":"bxl-e100500-n100000-s500","state":"DISCOVERED","attempts":0},{"cell_id":"bxl-e101000-n100000-s500","state":"DISCOVERED","attempts":1}]
    assert mod.select_batch(rotation,2)==["bxl-e100500-n100000-s500","bxl-e101000-n100000-s500"]
    frontier=[
        {"cell_id":"bxl-e100000-n100000-s500","state":"DATA_READY","attempts":0,"evidence_progress":1},
        {"cell_id":"bxl-e100500-n100000-s500","state":"DATA_READY","attempts":7,"evidence_progress":6},
        {"cell_id":"bxl-e101000-n100000-s500","state":"DATA_READY","attempts":1,"evidence_progress":6},
    ]
    assert mod.select_batch(frontier,2)==["bxl-e101000-n100000-s500","bxl-e100500-n100000-s500"]
    mature_vs_expansion=[
        {"cell_id":"bxl-e141500-n167500-s500","state":"DATA_READY","attempts":1,"evidence_progress":7},
        {"cell_id":"bxl-e142000-n168000-s500","state":"MISSING_SOURCE","attempts":0,"evidence_progress":0},
    ]
    assert mod.select_batch(mature_vs_expansion,1)==["bxl-e141500-n167500-s500"]

    frontier_cell = cells[3]
    for filename, _action in mod.EVIDENCE_STAGES[:-2]:
        write_json(source/frontier_cell/filename, {"cell_id": frontier_cell})
    progress, action = mod.evidence_plan(frontier_cell, source)
    assert progress == len(mod.EVIDENCE_STAGES)-2
    assert action == "derive_building_height_candidates"
    write_json(source/frontier_cell/"building_height_candidates.json", {"cell_id": frontier_cell})
    progress, action = mod.evidence_plan(frontier_cell, source)
    assert progress == len(mod.EVIDENCE_STAGES)-1
    assert action == "evaluate_terrain_lod"
    write_json(source/frontier_cell/"terrain_lod_evidence.json", {"cell_id": frontier_cell})
    progress, action = mod.evidence_plan(frontier_cell, source)
    assert progress == len(mod.EVIDENCE_STAGES)
    assert action == "secondary_height_validation_and_terrain_runtime_checks"
    assert mod.discover_cells(source)==sorted(cells[:4])

    # Regression: durable scheduler state must be refreshed after the selected
    # worklist has materially advanced. Refreshing must never count as another
    # scheduler run or another attempt, and it must not select a new batch.
    refreshed_source = root / "refreshed-source"
    refreshed_maturity = root / "refreshed-maturity"
    refreshed_out1 = root / "refreshed-out1"
    refreshed_out2 = root / "refreshed-out2"
    refresh_cell = "bxl-e141500-n167500-s500"
    refresh_target = root / "refresh-target.json"
    write_json(refresh_target,{"format":"grand-bruxelles-regional-target-grid-v1","crs":"EPSG:31370","cell_size_m":500.0,"cells":[{"cell_id":refresh_cell,"bbox":[141500,167500,142000,168000],"municipalities":["test"]}]})
    first=mod.run(refreshed_source,refreshed_maturity,None,refreshed_out1,1,refresh_target)
    assert first["selected_batch"] == [refresh_cell]
    assert first["run_number"] == 1
    write_json(refreshed_source/refresh_cell/"manifest.json",{"cell_id":refresh_cell,"crs":"EPSG:31370","layers":["buildings"]})
    write_json(refreshed_source/refresh_cell/"maturity.json",{"cell_id":refresh_cell,"crs":"EPSG:31370","geometry":{"authoritative_geometry_ready":True},"maturity":{"gates":{name:False for name in all_gates}}})
    for filename, _action in mod.EVIDENCE_STAGES:
        write_json(refreshed_source/refresh_cell/filename,{"cell_id":refresh_cell})
    refreshed=mod.run(
        refreshed_source,
        refreshed_maturity,
        refreshed_out1/"autonomous_citygen_state.json",
        refreshed_out2,
        1,
        refresh_target,
        refresh_only=True,
    )
    refreshed_row=refreshed["cells"][0]
    assert refreshed["run_number"] == 1
    assert refreshed["selected_batch"] == []
    assert refreshed_row["attempts"] == 1
    assert refreshed_row["state"] == "DATA_READY"
    assert refreshed_row["evidence_progress"] == len(mod.EVIDENCE_STAGES)
    assert refreshed_row["next_action"] == mod.MANUAL_FRONTIER_ACTION

print("AUTONOMOUS_CITYGEN_GUARDRAILS_OK source_local_maturity=true mature_before_expansion=true terrain_lod_stage=true building_height_stage=true evidence_frontier=true fair_within_stage=true fail_closed=true resume=true post_pass_refresh=true regional_maturity_contract=true")
