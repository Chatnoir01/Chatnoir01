#!/usr/bin/env python3
import argparse, hashlib, json, math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNS = ROOT / "data/provenance/brussels_sidewalk_high_coverage_runs.json"
OSM = ROOT / "data/osm/vertical_slice_01.game.json"


def canonical_sha(obj):
    payload = json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", required=True)
    args = ap.parse_args()
    lock = json.loads(RUNS.read_text())
    osm = json.loads(OSM.read_text())
    roads = {int(r["osm_id"]): r for r in osm["roads"]}
    anchors = osm["corridor"]["anchors"]
    queue = []
    for run in lock["runs"]:
        oid = int(run["osm_id"])
        if oid not in roads:
            raise SystemExit(f"missing OSM road {oid}")
        road = roads[oid]
        pts = road["points"]
        start = int(run["start_segment_index"])
        end = int(run["end_segment_index"])
        if start < 0 or end >= len(pts) - 1 or start > end:
            raise SystemExit(f"invalid segment range for {run['run_id']}")
        mids = [((pts[i][0]+pts[i+1][0])*0.5, (pts[i][1]+pts[i+1][1])*0.5) for i in range(start, end+1)]
        mx = sum(p[0] for p in mids)/len(mids); mz = sum(p[1] for p in mids)/len(mids)
        nearest = min(anchors, key=lambda a: math.hypot(mx-float(a["x"]), mz-float(a["z"])))
        dist = math.hypot(mx-float(nearest["x"]), mz-float(nearest["z"]))
        queue.append({
            "run_id": run["run_id"], "osm_id": oid, "road_name": road.get("name", ""),
            "road_class": road.get("class", ""), "side": int(run["side"]),
            "start_segment_index": start, "end_segment_index": end,
            "surface_count": int(run["surface_count"]),
            "midpoint_xz": [round(mx, 3), round(mz, 3)],
            "nearest_corridor_anchor": nearest["id"], "nearest_anchor_distance_m": round(dist, 3),
            "exact_location_owner_review_required": True,
            "runtime_replacement_authorized": False,
        })
    out = {
        "schema": "grand-bruxelles-sidewalk-owner-review-queue-v1",
        "production_base_sha": "202a2ff0e34629961f80c9b839a8a8d453a88368",
        "source_run_lock_sha256": lock["candidate_sha256"],
        "run_count": len(queue), "surface_count": sum(x["surface_count"] for x in queue),
        "queue": queue,
        "policy": {"horizontal_only": True, "curb_height_authorized": False, "vertical_profile_authorized": False,
                   "runtime_geometry_authorized": False, "runtime_replacement_authorized": False,
                   "jouable_promotion_authorized": False, "exact_location_owner_review_required": True},
    }
    out["canonical_sha256"] = canonical_sha(out)
    Path(args.output).write_text(json.dumps(out, indent=2, sort_keys=True, ensure_ascii=False)+"\n")
    print(f"SIDEWALK_OWNER_REVIEW_QUEUE_OK runs={out['run_count']} surfaces={out['surface_count']} sha={out['canonical_sha256']}")

if __name__ == "__main__": main()
