#!/usr/bin/env python3
import hashlib, io, json, pathlib, sys, urllib.request
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "data/qa/grand_place_town_hall_dormer_photo_evidence.json"
OUT = ROOT / "artifacts/qa/grand_place_town_hall_dormer_photo_evidence"
EXPECTED_BASE = "bffe110b9212ace10e1d4847436b51542bd95ab0"
EXPECTED_POPULATION = [3, 4, 4, 5]


def fail(message):
    print(f"GRAND_PLACE_DORMER_PHOTO_EVIDENCE_FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def download(url):
    request = urllib.request.Request(url, headers={"User-Agent": "GrandBruxellesGame-QA/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def validate_source(source):
    payload = download(source["download_url"])
    digest = hashlib.sha256(payload).hexdigest()
    if digest != source["sha256"]:
        fail(f"{source['id']} sha256 drift: {digest}")
    image = Image.open(io.BytesIO(payload)).convert("RGB")
    if image.size != (int(source["width"]), int(source["height"])):
        fail(f"{source['id']} dimensions drift: {image.size}")
    x0, y0, x1, y1 = [int(v) for v in source["crop_xyxy"]]
    if not (0 <= x0 < x1 <= image.width and 0 <= y0 < y1 <= image.height):
        fail(f"{source['id']} invalid crop")
    crop = image.crop((x0, y0, x1, y1))
    rows = source["row_points_crop_xy"]
    if [len(row) for row in rows] != EXPECTED_POPULATION:
        fail(f"{source['id']} visible row population drift")
    means = []
    for row_index, row in enumerate(rows):
        xs, ys = [], []
        for point in row:
            if len(point) != 2:
                fail(f"{source['id']} malformed annotation point")
            x, y = map(int, point)
            if not (0 <= x < crop.width and 0 <= y < crop.height):
                fail(f"{source['id']} annotation outside crop: {point}")
            xs.append(x); ys.append(y)
        if any(xs[i] >= xs[i + 1] for i in range(len(xs) - 1)):
            fail(f"{source['id']} row {row_index + 1} not ordered")
        means.append(sum(ys) / len(ys))
    if any(means[i + 1] - means[i] < 35.0 for i in range(3)):
        fail(f"{source['id']} four rows not independently separated")
    annotated = crop.copy(); draw = ImageDraw.Draw(annotated)
    for ri, row in enumerate(rows):
        for pi, (x, y) in enumerate(row):
            r = 9
            draw.ellipse((x-r, y-r, x+r, y+r), outline=(255,30,30), width=4)
            draw.text((x+11, y-11), f"R{ri+1}.{pi+1}", fill=(255,230,20))
    annotated.save(OUT / f"{source['id']}_annotated.jpg", quality=92)
    return {"id": source["id"], "sha256": digest, "dimensions": list(image.size), "crop_xyxy": [x0,y0,x1,y1], "row_population_top_to_bottom": [len(r) for r in rows], "row_mean_y_crop_px": means, "license": source["license"], "author": source["author"], "source_page": source["source_page"]}


def main():
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    if contract.get("schema") != "grand-bruxelles-town-hall-dormer-photo-evidence-v1": fail("schema drift")
    if contract.get("production_base") != EXPECTED_BASE: fail("production base drift")
    heritage = contract.get("heritage_source", {})
    if heritage.get("record_id") != "31125" or int(heritage.get("supported_row_count", 0)) != 4: fail("heritage fact drift")
    if bool(heritage.get("supports_exact_dormer_positions", True)) or bool(heritage.get("supports_exact_dormer_dimensions", True)): fail("heritage over-claim")
    observation = contract.get("cross_source_observation", {})
    sources = contract.get("photo_sources", [])
    if len(sources) != 3 or int(observation.get("required_source_count", 0)) != 3: fail("source count drift")
    if observation.get("required_visible_population_by_row_top_to_bottom") != EXPECTED_POPULATION: fail("population contract drift")
    if not bool(observation.get("photo_points_are_manual_visual_annotations", False)) or bool(observation.get("photo_points_are_survey_coordinates", True)): fail("annotation provenance drift")
    decision = contract.get("decision", {})
    if not bool(decision.get("four_rows_confirmed", False)) or not bool(decision.get("visible_population_pattern_confirmed", False)): fail("observation not locked")
    for key in ["exact_3d_positions_resolved","exact_dimensions_resolved","runtime_changed","geometry_changed","dormers_authored","implementation_authorized","visual_candidate_approved","realism_complete"]:
        if bool(decision.get(key, True)): fail(f"fail-closed decision drift: {key}")
    OUT.mkdir(parents=True, exist_ok=True)
    results = [validate_source(source) for source in sources]
    (OUT / "ATTRIBUTION.txt").write_text("\n".join(f"{s['id']} — photo by {s['author']} ({s['date']}), {s['license']}, {s['source_page']}" for s in sources) + "\n", encoding="utf-8")
    evidence = {"schema":"grand-bruxelles-town-hall-dormer-photo-evidence-result-v1","production_base":EXPECTED_BASE,"heritage_row_count":4,"cross_source_visible_population":EXPECTED_POPULATION,"sources":results,"exact_3d_positions_resolved":False,"exact_dimensions_resolved":False,"implementation_authorized":False}
    (OUT / "evidence.json").write_text(json.dumps(evidence, indent=2), encoding="utf-8")
    print("GRAND_PLACE_DORMER_PHOTO_EVIDENCE_OK sources=3 rows=4 population=3/4/4/5 implementation_authorized=false")


if __name__ == "__main__":
    main()
