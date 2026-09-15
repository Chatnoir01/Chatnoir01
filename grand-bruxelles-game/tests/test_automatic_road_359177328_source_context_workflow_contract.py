#!/usr/bin/env python3
from pathlib import Path
PROJECT=Path(__file__).resolve().parents[1]; REPO=PROJECT.parent
SCRIPT=PROJECT/"game"/"tests"/"automatic_road_359177328_source_context_balance_test.gd"
WORKFLOW=REPO/".github"/"workflows"/"grand-bruxelles-automatic-road-359177328-source-context-balance.yml"
EXPECTED_MARKER="AUTOMATIC_ROAD_359177328_SOURCE_CONTEXT_DIAGNOSTIC_GREEN:"
TABLE_MARKER="AUTOMATIC_ROAD_359177328_SOURCE_CONTEXT_CLASSIFICATION_TABLE_GREEN:"
INSUFFICIENT_CLASSIFICATION="source_coverage_insufficient_for_visual_void_claim"
BOUNDED_BILATERAL_CLASSIFICATION="bilateral_source_context_present_within_covered_radius"
SOURCE_ONLY_REMOVE_PATHS=("PrototypeCar","PhysicalCarB","MissionDriveToCenter","MissionReturnToBourse","RuntimeGameplayState","MissionQuickSave","MissionCheckpointAutosave","MissionRewardController","WalletHud","MiniMap","MobileControls")
def main():
    script=SCRIPT.read_text(encoding="utf-8"); workflow=WORKFLOW.read_text(encoding="utf-8")
    assert EXPECTED_MARKER in script and EXPECTED_MARKER in workflow
    assert "SOURCE_CONTEXT_COMPILE_CONTAMINATION_FAIL" in workflow and "SOURCE_CONTEXT_IMPORT_CONTAMINATION_FAIL" in workflow
    assert "--headless --editor --path . --quit 2>&1" in workflow and "--quit-after" not in workflow
    for marker in ("SCRIPT ERROR: Parse Error:","SCRIPT ERROR: Compile Error:","ERROR: Failed to load script"): assert workflow.count(marker)>=2
    assert INSUFFICIENT_CLASSIFICATION in script and BOUNDED_BILATERAL_CLASSIFICATION in script
    assert "func _classify_source_context(left_hits: int, right_hits: int, coverage_clamped: bool) -> Dictionary:" in script
    assert "func _verify_classification_truth_table() -> bool:" in script and TABLE_MARKER in script
    instantiate_at=script.index("var scene := MAIN_SCENE.instantiate()"); hide_at=script.index("_hide_dynamic(scene)",instantiate_at); add_at=script.index("viewport.add_child(scene)",instantiate_at); assert instantiate_at<hide_at<add_at
    assert 'traffic.set("dedicated_ambulance_count", 0)' in script
    for path in SOURCE_ONLY_REMOVE_PATHS: assert f'"{path}"' in script
    for marker in ("human_visual_reject_still_binding=true","destination_advertisable=false","visual_acceptance=false","jouable=false"): assert marker in script
    print("AUTOMATIC_ROAD_359177328_SOURCE_CONTEXT_WORKFLOW_CONTRACT_GREEN"); return 0
if __name__=="__main__": raise SystemExit(main())
