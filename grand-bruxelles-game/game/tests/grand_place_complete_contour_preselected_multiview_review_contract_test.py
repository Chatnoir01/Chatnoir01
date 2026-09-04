import json
import pathlib
import re

GAME_ROOT = pathlib.Path(__file__).resolve().parents[2]
RECEIPT = GAME_ROOT / "data/qa/grand_place_complete_contour_preselected_multiview_review.json"

EXPECTED = {
    "q0_selected": (0, "48378427ef734be7c93619cf6a4e553d3911b031bcf55388090a34d748091167", "USABLE_WITNESS_ONLY"),
    "q1_selected": (135, "9224e20fa6e99175369943d4a1db4c6daf3780c4e1964d0471d1a4b0ee40f9f5", "REJECT"),
    "q2_selected": (225, "3cc87d11c9a8f5d1e7c8403b47cf00d0b37ed84f576fda24339645308ebf02a6", "REJECT"),
    "q3_selected": (270, "a4a363c2ebf391209b1dd387ac804ae6e3ff464174cc7d1d00fa854657cc45c3", "USABLE_WITNESS_ONLY"),
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    d = json.loads(RECEIPT.read_text())
    require(d.get("schema") == "grand-bruxelles-grand-place-preselected-multiview-review-v1", "schema drift")
    require(d.get("capture_head") == "34d7cb9a38cfd7e27ca1e4c34277c0679c3246b6", "capture head drift")
    require(re.fullmatch(r"[0-9a-f]{40}", d["capture_head"]) is not None, "capture head malformed")
    require(d.get("workflow_run_id") == 33835477889, "workflow run drift")
    require(d.get("artifact_id") == 9923169120, "artifact id drift")
    require(d.get("artifact_digest_sha256") == "297eeea75d193b31765e80a76110caf8d2256c84bc502a71c90763977aaa067a", "artifact digest drift")
    require(re.fullmatch(r"[0-9a-f]{64}", d["artifact_digest_sha256"]) is not None, "artifact digest malformed")
    require(d.get("resolution") == [1280, 720], "resolution drift")
    require(d.get("full_frame_inspected") is True, "full-frame review missing")
    require(d.get("selection_was_pinned_before_capture") is True, "selection provenance missing")
    require(d.get("post_capture_reselection_performed") is False, "post-capture reselection is forbidden")

    views = d.get("views")
    require(isinstance(views, list) and len(views) == 4, "expected exactly four reviewed views")
    require([v.get("id") for v in views] == list(EXPECTED), "view order/identity drift")
    seen_hashes = set()
    rejected = []
    for view in views:
        view_id = view["id"]
        expected_yaw, expected_hash, expected_verdict = EXPECTED[view_id]
        require(type(view.get("yaw_degrees_from_seed")) in (int, float), f"{view_id} yaw type invalid")
        require(view["yaw_degrees_from_seed"] == expected_yaw, f"{view_id} yaw drift")
        png_hash = view.get("png_sha256", "")
        require(re.fullmatch(r"[0-9a-f]{64}", png_hash) is not None, f"{view_id} png hash malformed")
        require(png_hash == expected_hash, f"{view_id} png hash drift")
        require(png_hash not in seen_hashes, "reviewed PNG hashes must be unique")
        seen_hashes.add(png_hash)
        require(view.get("verdict") == expected_verdict, f"{view_id} verdict drift")
        require(isinstance(view.get("reason"), str) and view["reason"].strip(), f"{view_id} reason missing")
        if view["verdict"] == "REJECT":
            rejected.append(view_id)

    require(rejected == ["q1_selected", "q2_selected"], "rejected-view identity drift")
    require(d.get("overall_verdict") == "REJECT", "overall verdict must remain REJECT")
    for key in (
        "camera_rescue_allowed",
        "threshold_rescue_allowed",
        "source_geometry_modified",
        "collision_modified",
        "runtime_modified",
        "destination_advertisable",
        "visual_acceptance",
        "jouable_authorized",
    ):
        require(d.get(key) is False, f"{key} must remain false")
    require(
        d.get("next_scope") == "official_source_backed_grand_place_ground_street_player_foot_collision_continuity",
        "next scope drift",
    )
    print("GRAND_PLACE_PRESELECTED_MULTIVIEW_REVIEW_OK overall=REJECT rejected=q1_selected,q2_selected visual_acceptance=false jouable_authorized=false")


if __name__ == "__main__":
    main()
