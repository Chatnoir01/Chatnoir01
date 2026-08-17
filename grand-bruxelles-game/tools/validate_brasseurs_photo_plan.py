#!/usr/bin/env python3
import json
import math
from pathlib import Path

PLAN = Path(__file__).resolve().parents[1] / "data/qa/grand_place_brasseurs_photo_plan.json"

def fail(msg: str) -> None:
    raise SystemExit(f"BRASSEURS_PHOTO_PLAN_FAIL: {msg}")

def main() -> None:
    d = json.loads(PLAN.read_text())
    if d.get("schema") != "grand-bruxelles-brasseurs-photo-plan-v1": fail("schema")
    if d.get("runtime_approved") is not False: fail("runtime_approved must remain false")
    if d.get("realism_complete") is not False: fail("realism_complete must remain false")
    src = d["source"]
    if src["width_px"] != 2737 or src["height_px"] != 5600: fail("source dimensions drifted")
    if src["license"] != "CC BY-SA 4.0": fail("license drifted")
    if src["download_sha256"] != "fff8d81aaca8b3dd82247ef8d171bdb61cb1e294d530185a16566298569ed322": fail("source hash drifted")
    placement = d["placement"]
    if placement["owner"] != "UrbIS": fail("placement owner")
    if placement["building_id"] != "1639974" or placement["front_wall_id"] != "10945501": fail("official identity")
    if placement["vertical_world_scale"] != "unresolved": fail("vertical scale must stay unresolved")
    if placement["photo_geometry_claimed_surveyed"] is not False: fail("photo geometry cannot be surveyed")
    span = float(placement["front_wall_span_m"])
    if not math.isclose(span, 8.7490357183, rel_tol=0, abs_tol=1e-9): fail("official span")
    method = d["measurement_method"]
    if method["raw_photo_quad_shipping_allowed"] is not False: fail("raw quad must remain blocked")
    if method["perspective_rectification"] != "not_yet_applied": fail("rectification status")
    p = d["principal_order"]
    left, right = int(p["left_px"]), int(p["right_px"])
    xs = [int(v) for v in p["column_center_x_px"]]
    if not (0 <= left < xs[0] < xs[1] < xs[2] < xs[3] < right <= src["width_px"]): fail("column x ordering")
    if p["bay_count"] != 3 or p["column_count"] != 4: fail("3-bay/4-column contract")
    if p["top_px"] >= p["bottom_px"]: fail("principal order vertical bounds")
    computed_norm = [(x-left)/(right-left) for x in xs]
    for i, (a,b) in enumerate(zip(computed_norm, [float(v) for v in p["normalized_column_x"]])):
        if not math.isclose(a,b,rel_tol=0,abs_tol=5e-5): fail(f"normalized column {i}")
    derived = d["derived_horizontal_world_constraints"]
    offsets = [v*span for v in computed_norm]
    for i, (a,b) in enumerate(zip(offsets, [float(v) for v in derived["column_center_offsets_from_left_m"]])):
        if not math.isclose(a,b,rel_tol=0,abs_tol=0.001): fail(f"world offset {i}")
    spacings = [offsets[i+1]-offsets[i] for i in range(3)]
    for i, (a,b) in enumerate(zip(spacings, [float(v) for v in derived["bay_center_spacing_m"]])):
        if not math.isclose(a,b,rel_tol=0,abs_tol=0.001): fail(f"bay spacing {i}")
    regs = list(d["horizontal_registers"].values())
    if regs != sorted(regs): fail("horizontal registers must increase down image")
    crown = d["crowning_profile"]
    if crown["curved_pediment"] is not True or crown["axial_crowning_stack"] is not True: fail("crowning semantics")
    if not (0 < crown["golden_statue_top_y_px"] < crown["lantern_body_top_y_px"] < crown["arched_pediment_crown_y_px"] < crown["pediment_base_y_px"] < p["top_px"]): fail("crowning y ordering")
    if not (left < crown["central_axis_x_px"] < right): fail("central axis outside facade")
    print("BRASSEURS_PHOTO_PLAN_OK: building=1639974 wall=10945501 span=%.6f columns=%s vertical_world_scale=unresolved raw_quad=false" % (span, xs))

if __name__ == "__main__":
    main()
