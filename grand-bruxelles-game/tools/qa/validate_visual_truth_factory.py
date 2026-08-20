#!/usr/bin/env python3
from __future__ import annotations
import argparse,json
from pathlib import Path
EXPECTED_MUNICIPALITIES={"Bruxelles-Ville","Anderlecht","Auderghem","Berchem-Sainte-Agathe","Etterbeek","Evere","Forest","Ganshoren","Ixelles","Jette","Koekelberg","Molenbeek-Saint-Jean","Saint-Gilles","Saint-Josse-ten-Noode","Schaerbeek","Uccle","Watermael-Boitsfort","Woluwe-Saint-Lambert","Woluwe-Saint-Pierre"}
def load(path): return json.loads(Path(path).read_text(encoding="utf-8"))
def require(cond,msg):
    if not cond: raise SystemExit(msg)
def validate(root):
    root=Path(root); c=load(root/"factory_contract.json"); s=load(root/"source_registry.json"); m=load(root/"zone_matrix.json")
    require(c.get("schema")=="grand-bruxelles-visual-truth-factory-v1","bad factory schema")
    require(s.get("schema")=="grand-bruxelles-visual-source-registry-v1","bad source schema")
    require(m.get("schema")=="grand-bruxelles-visual-truth-zone-matrix-v1","bad matrix schema")
    hard=c["hard_rules"]
    for key in ("factory_is_evaluator_not_runtime_owner","no_wholesale_merge_of_stale_visual_branches","no_source_geometry_mutation_for_visual_rescue","no_camera_fov_threshold_rescue","numeric_pass_never_overrides_human_fail","human_full_frame_veto","three_second_recognition_required","building_specific_identity_requires_exact_crosswalk","nearest_neighbour_identity_fallback_forbidden","raw_reference_pixels_shipping_requires_explicit_reuse_license","reference_only_sources_must_not_ship_as_textures","authored_convention_must_be_labeled_authored","unknown_visual_fact_must_remain_hold"):
        require(hard.get(key) is True,f"hard rule disabled: {key}")
    require(hard.get("runtime_authorized") is False,"factory cannot authorize runtime")
    require(hard.get("jouable_promotion_authorized") is False,"factory cannot auto-promote JOUABLE")
    names=[x.get("name") for x in m.get("municipalities",[])]
    require(len(names)==19,f"expected 19 municipalities, got {len(names)}")
    require(set(names)==EXPECTED_MUNICIPALITIES,"municipality set drift")
    require(len(names)==len(set(names)),"duplicate municipality")
    for row in m["municipalities"]: require(row.get("visual_truth_status") in {"UNPROVEN","PARTIAL","VISUAL_GREEN"},f"bad municipality status: {row}")
    source_ids=set()
    for src in s.get("sources",[]):
        sid=src.get("source_id"); require(isinstance(sid,str) and sid,"source_id missing"); require(sid not in source_ids,f"duplicate source_id: {sid}"); source_ids.add(sid)
        for key in ("license","reuse_mode","pixel_shipping"): require(src.get(key),f"{key} missing: {sid}")
        if "reference_only" in str(src.get("reuse_mode","")): require("forbidden" in str(src.get("pixel_shipping","")),f"reference-only pixels not fail-closed: {sid}")
    profiles=c["profiles"]; zone_ids=set()
    for z in m.get("priority_zones",[]):
        zid=z.get("zone_id"); require(isinstance(zid,str) and zid,"zone_id missing"); require(zid not in zone_ids,f"duplicate zone_id: {zid}"); zone_ids.add(zid)
        profile_name=z.get("profile"); require(profile_name in profiles,f"unknown profile {profile_name} for {zid}")
        require(z.get("status") in {"HOLD","CANDIDATE","VISUAL_GREEN"},f"bad zone status for {zid}")
        require(z.get("human_full_frame_verdict") in {"UNREVIEWED","PASS","FAIL"},f"bad human verdict for {zid}")
        require(z.get("three_second_recognition") in {"UNREVIEWED","PASS","FAIL"},f"bad recognition verdict for {zid}")
        require(z.get("runtime_authorized") is False,f"factory row cannot authorize runtime: {zid}")
        require(z.get("jouable_promotion_authorized") is False,f"factory row cannot authorize JOUABLE: {zid}")
        profile=profiles[profile_name]
        if z.get("status")=="VISUAL_GREEN" or z.get("realism_complete") is True:
            require(z.get("reference_count",0)>=profile["min_reference_views"],f"not enough reference views: {zid}")
            require(z.get("human_full_frame_verdict")=="PASS",f"human veto not passed: {zid}")
            require(z.get("three_second_recognition")=="PASS" or profile_name=="background_fabric",f"3-second gate not passed: {zid}")
            require(z.get("materials") is True,f"materials unproven: {zid}")
            require(z.get("ground_contact") is True or z.get("street_join") is True,f"ground/street join unproven: {zid}")
            require(z.get("player_height_photo_match") is True or profile_name=="background_fabric",f"player-height photo match unproven: {zid}")
            if profile["authored_individual_required"]:
                require(z.get("authored_individual") is True,f"hero landmark must be individually authored: {zid}")
                require(z.get("exact_identity_proven") is True,f"hero landmark identity unproven: {zid}")
                for key in ("silhouette","facade_rhythm","ground_floor","roofline","street_furniture_context"): require(z.get(key) is True,f"{key} unproven for hero landmark: {zid}")
    print("VISUAL_TRUTH_FACTORY_GREEN",f"municipalities={len(names)}",f"priority_zones={len(zone_ids)}",f"sources={len(source_ids)}","promotion=fail-closed")
def main():
    p=argparse.ArgumentParser(); p.add_argument("--root",default="grand-bruxelles-game/data/visual_truth"); a=p.parse_args(); validate(a.root)
if __name__=="__main__": main()
