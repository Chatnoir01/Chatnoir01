#!/usr/bin/env python3
import hashlib
import io
import json
import pathlib
import sys
import time
import urllib.error
import urllib.request

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "data/qa/grand_place_town_hall_dormer_photo_evidence.json"
OUT = ROOT / "artifacts/qa/grand_place_town_hall_dormer_photo_evidence"
EXPECTED_BASE = "bffe110b9212ace10e1d4847436b51542bd95ab0"
EXPECTED_POPULATION = [3, 4, 4, 5]
MAX_ATTEMPTS = 6


def fail(message: str) -> None:
    print(f"GRAND_PLACE_DORMER_PHOTO_EVIDENCE_FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def download(source: dict) -> bytes:
    url = source["download_url"]
    headers = {
        "User-Agent": "GrandBruxellesGame-QA/1.1 (+https://github.com/Chatnoir01/Chatnoir01)",
        "Accept": "image/jpeg,image/*;q=0.9,*/*;q=0.5",
        "Referer": source["source_page"],
    }
    last_error = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        request = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                payload = response.read()
                if not payload:
                    raise RuntimeError("empty response")
                return payload
        except urllib.error.HTTPError as exc:
            last_error = exc
            retryable = exc.code == 429 or 500 <= exc.code < 600
            if not retryable or attempt == MAX_ATTEMPTS:
                break
            retry_after = exc.headers.get("Retry-After")
            try:
                delay = float(retry_after) if retry_after else min(2 ** attempt, 20)
            except ValueError:
                delay = min(2 ** attempt, 20)
            delay = min(max(delay, 1.0), 30.0)
            print(
                f"GRAND_PLACE_DORMER_PHOTO_EVIDENCE_RETRY "
                f"source={source['id']} status={exc.code} attempt={attempt}/{MAX_ATTEMPTS} sleep_s={delay:g}",
                file=sys.stderr,
            )
            time.sleep(delay)
        except (urllib.error.URLError, TimeoutError, RuntimeError) as exc:
            last_error = exc
            if attempt == MAX_ATTEMPTS:
                break
            delay = min(2 ** attempt, 20)
            print(
                f"GRAND_PLACE_DORMER_PHOTO_EVIDENCE_RETRY "
                f"source={source['id']} transport={type(exc).__name__} attempt={attempt}/{MAX_ATTEMPTS} sleep_s={delay:g}",
                file=sys.stderr,
            )
            time.sleep(delay)
    fail(f"{source['id']} download failed after {MAX_ATTEMPTS} attempts: {last_error}")


def validate_source(source: dict) -> dict:
    payload = download(source)
    digest = hashlib.sha256(payload).hexdigest()
    if digest != source["sha256"]:
        fail(f"{source['id']} sha256 drift: {digest}")

    image = Image.open(io.BytesIO(payload)).convert("RGB")
    if image.size != (int(source["width"]), int(source["height"])):
        fail(f"{source['id']} dimensions drift: {image.size}")

    crop_box = [int(v) for v in source["crop_xyxy"]]
    if len(crop_box) != 4 or crop_box[0] < 0 or crop_box[1] < 0 or crop_box[2] > image.width or crop_box[3] > image.height:
        fail(f"{source['id']} invalid crop")
    crop = image.crop(tuple(crop_box))
    rows = source["row_points_crop_xy"]
    if [len(row) for row in rows] != EXPECTED_POPULATION:
        fail(f"{source['id']} visible row population drift")

    row_means = []
    for row_index, points in enumerate(rows):
        ys = []
        xs = []
        for point in points:
            if len(point) != 2:
                fail(f"{source['id']} malformed annotation point")
            x, y = int(point[0]), int(point[1])
            if not (0 <= x < crop.width and 0 <= y < crop.height):
                fail(f"{source['id']} annotation outside crop: {point}")
            xs.append(x)
            ys.append(y)
        if any(xs[i] >= xs[i + 1] for i in range(len(xs) - 1)):
            fail(f"{source['id']} row {row_index + 1} is not left-to-right ordered")
        row_means.append(sum(ys) / len(ys))

    if any(row_means[i + 1] - row_means[i] < 35.0 for i in range(3)):
        fail(f"{source['id']} four rows are not independently separated")

    annotated = crop.copy()
    draw = ImageDraw.Draw(annotated)
    for row_index, points in enumerate(rows):
        for point_index, (x, y) in enumerate(points):
            radius = 9
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), outline=(255, 30, 30), width=4)
            draw.text((x + 11, y - 11), f"R{row_index + 1}.{point_index + 1}", fill=(255, 230, 20))
    annotated.save(OUT / f"{source['id']}_annotated.jpg", quality=92)

    return {
        "id": source["id"],
        "sha256": digest,
        "dimensions": [image.width, image.height],
        "crop_xyxy": crop_box,
        "crop_dimensions": [crop.width, crop.height],
        "row_population_top_to_bottom": [len(row) for row in rows],
        "row_mean_y_crop_px": row_means,
        "license": source["license"],
        "author": source["author"],
        "source_page": source["source_page"],
    }


def main() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    if contract.get("schema") != "grand-bruxelles-town-hall-dormer-photo-evidence-v1":
        fail("contract schema drift")
    if contract.get("production_base") != EXPECTED_BASE:
        fail("production base drift")

    heritage = contract.get("heritage_source", {})
    if int(heritage.get("supported_row_count", 0)) != 4:
        fail("Urban four-row fact drift")
    if bool(heritage.get("supports_exact_dormer_positions", True)) or bool(heritage.get("supports_exact_dormer_dimensions", True)):
        fail("heritage source over-claim")

    observation = contract.get("cross_source_observation", {})
    sources = contract.get("photo_sources", [])
    if len(sources) != int(observation.get("required_source_count", 0)) or len(sources) != 3:
        fail("photo source count drift")
    if int(observation.get("required_row_count", 0)) != 4:
        fail("required row count drift")
    if observation.get("required_visible_population_by_row_top_to_bottom") != EXPECTED_POPULATION:
        fail("cross-source population contract drift")
    if not bool(observation.get("photo_points_are_manual_visual_annotations", False)):
        fail("annotation provenance must be explicit")
    if bool(observation.get("photo_points_are_survey_coordinates", True)):
        fail("manual photo points must not be promoted to survey coordinates")

    decision = contract.get("decision", {})
    if not bool(decision.get("four_rows_confirmed", False)) or not bool(decision.get("visible_population_pattern_confirmed", False)):
        fail("source-backed photo observation not locked")
    for key in [
        "exact_3d_positions_resolved",
        "exact_dimensions_resolved",
        "runtime_changed",
        "geometry_changed",
        "dormers_authored",
        "implementation_authorized",
        "visual_candidate_approved",
        "realism_complete",
    ]:
        if bool(decision.get(key, True)):
            fail(f"fail-closed decision drift: {key}")

    OUT.mkdir(parents=True, exist_ok=True)
    results = []
    for index, source in enumerate(sources):
        if index:
            time.sleep(2.0)
        results.append(validate_source(source))

    attribution = []
    for source in sources:
        attribution.append(
            f"{source['id']} — photo by {source['author']} ({source['date']}), {source['license']}, {source['source_page']}"
        )
    (OUT / "ATTRIBUTION.txt").write_text("\n".join(attribution) + "\n", encoding="utf-8")

    evidence = {
        "schema": "grand-bruxelles-town-hall-dormer-photo-evidence-result-v1",
        "production_base": EXPECTED_BASE,
        "heritage_row_count": 4,
        "cross_source_visible_population": EXPECTED_POPULATION,
        "sources": results,
        "exact_3d_positions_resolved": False,
        "exact_dimensions_resolved": False,
        "implementation_authorized": False,
    }
    (OUT / "evidence.json").write_text(json.dumps(evidence, indent=2), encoding="utf-8")
    print("GRAND_PLACE_DORMER_PHOTO_EVIDENCE_JSON " + json.dumps(evidence, separators=(",", ":")))
    print("GRAND_PLACE_DORMER_PHOTO_EVIDENCE_OK sources=3 rows=4 population=3/4/4/5 implementation_authorized=false")


if __name__ == "__main__":
    main()
