#!/usr/bin/env python3
"""Classify CIV-1 RightFoot rendered-sole stability around a verified bone landmark."""
from __future__ import annotations
import importlib.util, json, math, statistics, sys
from pathlib import Path

DISTANCES=(2,4,8)
SAMPLES=(68,69,70,71)
ROI_RADIUS_MULT=4.0
MIN_ROI_HALF_WIDTH_PX=8
MAX_DISTANCE_MEAN_REL_SPREAD=0.15
MAX_WITHIN_DISTANCE_REL_DEVIATION=0.15
MAX_ANCHOR_CENTROID_ERROR_PX=1.5

def _load_helper(path: Path):
    spec=importlib.util.spec_from_file_location("civ1_rightfoot_contact_landmark",path)
    if spec is None or spec.loader is None: raise RuntimeError("cannot load landmark analyzer")
    module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module

def _relative(a: float,b: float)->float:
    return abs(a-b)/max(abs(b),1e-12)

def assess_normalized_series(series_by_distance: dict[int,list[float]])->dict:
    if set(series_by_distance)!=set(DISTANCES): raise ValueError("distance series")
    if any(len(series_by_distance[d])!=len(SAMPLES) for d in DISTANCES): raise ValueError("sample series")
    means={d:statistics.mean(series_by_distance[d]) for d in DISTANCES}
    medians={d:statistics.median(series_by_distance[d]) for d in DISTANCES}
    signs={1 if means[d]>0 else -1 if means[d]<0 else 0 for d in DISTANCES}
    single_side=signs in ({1},{-1})
    center=statistics.median(means.values())
    mean_spread=(max(means.values())-min(means.values()))/max(abs(center),1e-12)
    within={d:max(_relative(v,medians[d]) for v in series_by_distance[d]) for d in DISTANCES}
    passed=single_side and mean_spread<=MAX_DISTANCE_MEAN_REL_SPREAD and all(v<=MAX_WITHIN_DISTANCE_REL_DEVIATION for v in within.values())
    return {"mean_normalized_offset_x_by_distance":means,"median_normalized_offset_x_by_distance":medians,"distance_mean_relative_spread":mean_spread,"max_within_distance_relative_deviation":within,"single_side_consistent":single_side,"passed":passed}

def _validate_inputs(witness:dict,landmark_analysis:dict)->dict:
    if witness.get("schema")!="grand-bruxelles-civ1-rightfoot-landmark-witness-v1": raise ValueError("witness schema")
    if witness.get("landmark_semantic")!="rightfoot_bone_pose_with_verified_same_skeleton_skin": raise ValueError("identity semantic")
    if witness.get("sample_indices")!=list(SAMPLES) or witness.get("player_distances_m")!=[2.0,4.0,8.0]: raise ValueError("witness sample/distance contract")
    if witness.get("resolution")!=[1280,720] or float(witness.get("vertical_fov_deg",0))!=45.0: raise ValueError("camera contract")
    if witness.get("marker_no_depth_test") is not True or float(witness.get("marker_radius_m",0))!=0.025: raise ValueError("marker contract")
    integrity=witness.get("skin_integrity",{})
    for key in ("mesh_instance_count","surface_count","skinned_mesh_count","skin_bind_count","same_skeleton_skin_count"):
        if int(integrity.get(key,0))<1: raise ValueError("skin integrity "+key)
    for key in ("perceptual_2_8m_claimed","planted_contact_claimed","animation_correction_authorized","runtime_authorized","visual_approval_claimed","player_view_claimed"):
        if witness.get(key) is not False: raise ValueError("witness claim "+key)
    if landmark_analysis.get("schema")!="grand-bruxelles-civ1-rightfoot-landmark-raster-analysis-v1": raise ValueError("landmark analysis schema")
    if landmark_analysis.get("samples")!=list(SAMPLES) or landmark_analysis.get("distances_m")!=list(DISTANCES): raise ValueError("landmark analysis sample/distance contract")
    measurements=landmark_analysis.get("measurements",[])
    if [int(m.get("distance_m",-1)) for m in measurements]!=list(DISTANCES): raise ValueError("landmark measurement matrix")
    max_anchor_error=0.0
    for measurement in measurements:
        if measurement.get("direction_match") is not True: raise ValueError("landmark signed direction")
        records=measurement.get("records",[])
        if [int(r.get("sample_index",-1)) for r in records]!=list(SAMPLES): raise ValueError("landmark record matrix")
        for record in records:
            err=float(record.get("centroid_error_px",999.0))
            if not math.isfinite(err): raise ValueError("non-finite anchor error")
            max_anchor_error=max(max_anchor_error,err)
    if max_anchor_error>MAX_ANCHOR_CENTROID_ERROR_PX: raise ValueError("bone landmark not precise enough for local ROI anchor")
    return {"roi_anchor_usable":True,"max_observed_anchor_centroid_error_px":max_anchor_error,"landmark_path_quantitative_candidate":bool(landmark_analysis.get("quantitative_landmark_candidate",False))}

def local_sole_observation(path:Path,landmark)->dict:
    width,height,rows=landmark.read_png(path); channels=len(rows[0])//width
    marker=landmark.marker_centroid(path); marker_radius_px=math.sqrt(marker["marker_pixel_count"]/math.pi)
    if marker_radius_px<=0 or not math.isfinite(marker_radius_px): raise ValueError("marker radius")
    roi=max(MIN_ROI_HALF_WIDTH_PX,int(math.ceil(ROI_RADIUS_MULT*marker_radius_px)))
    cx=float(marker["centroid_x_px"]); cy=float(marker["centroid_y_px"]); white=[]
    for y in range(max(0,int(math.floor(cy-roi))),min(height-1,int(math.ceil(cy+roi)))+1):
        row=rows[y]
        for x in range(max(0,int(math.floor(cx-roi))),min(width-1,int(math.ceil(cx+roi)))+1):
            i=x*channels; r,g,b=row[i],row[i+1],row[i+2]
            if r>=220 and g>=220 and b>=220: white.append((x,y))
    if not white: raise ValueError(f"no local near-white sole pixels in {path}")
    bottom_y=max(y for _,y in white); bottom_xs=[x for x,y in white if y==bottom_y]; bottom_centroid_x=sum(bottom_xs)/len(bottom_xs)
    return {"marker_centroid_x_px":cx,"marker_centroid_y_px":cy,"marker_pixel_count":marker["marker_pixel_count"],"marker_radius_px":marker_radius_px,"roi_half_width_px":roi,"local_bottom_y_px":bottom_y,"local_bottom_centroid_x_px":bottom_centroid_x,"local_bottom_pixel_count":len(bottom_xs),"normalized_offset_x":(bottom_centroid_x-cx)/marker_radius_px,"normalized_offset_y":(bottom_y-cy)/marker_radius_px}

def analyze(helper_path:Path,witness:dict,landmark_analysis:dict,capture_dir:Path)->dict:
    landmark=_load_helper(helper_path); anchor=_validate_inputs(witness,landmark_analysis)
    cmap={(int(c["distance_m"]),int(c["sample_index"])):c for c in witness.get("captures",[]) if isinstance(c,dict)}
    if set(cmap)!={(d,s) for d in DISTANCES for s in SAMPLES}: raise ValueError("capture matrix")
    measurements=[]; series={}
    for d in DISTANCES:
        records=[]
        for s in SAMPLES:
            path=capture_dir/Path(cmap[(d,s)]["png"]).name
            records.append({"sample_index":s,**local_sole_observation(path,landmark)})
        series[d]=[r["normalized_offset_x"] for r in records]
        measurements.append({"distance_m":d,"records":records,"mean_normalized_offset_x":statistics.mean(series[d]),"median_normalized_offset_x":statistics.median(series[d]),"normalized_offset_y_span":max(r["normalized_offset_y"] for r in records)-min(r["normalized_offset_y"] for r in records)})
    quality=assess_normalized_series(series); passed=quality["passed"]
    return {"schema":"grand-bruxelles-civ1-rightfoot-contact-local-sole-v1","diagnostic_only":True,"identity_anchor":"verified_rightfoot_bone_magenta_landmark_roi_anchor_only","pixel_semantic":"near_white_lowest_row_inside_marker_scaled_roi","samples":list(SAMPLES),"distances_m":list(DISTANCES),"roi_radius_multiplier":ROI_RADIUS_MULT,"min_roi_half_width_px":MIN_ROI_HALF_WIDTH_PX,"max_distance_mean_relative_spread":MAX_DISTANCE_MEAN_REL_SPREAD,"max_within_distance_relative_deviation":MAX_WITHIN_DISTANCE_REL_DEVIATION,**anchor,"measurements":measurements,**quality,"bone_local_sole_identity_preserved_2_4_8m":passed,"contact_phase_ready":False,"quantitative_foot_slide_candidate":False,"perceptual_2_8m_claimed":False,"planted_contact_claimed":False,"animation_correction_authorized":False,"runtime_authorized":False,"visual_approval_claimed":False,"player_view_claimed":False,"verdict":"AMELIORER_RIGHTFOOT_CONTACT_LOCAL_SOLE_IDENTITY_PRESERVED_NO_PROMOTION" if passed else "JETER_RIGHTFOOT_CONTACT_CONTEXT_LOCAL_SOLE_UNSTABLE"}

def main(argv:list[str])->int:
    if len(argv)!=6:
        print("usage: analyze_civ1_rightfoot_contact_local_sole.py LANDMARK_ANALYZER.py WITNESS.json LANDMARK_ANALYSIS.json CAPTURE_DIR OUT.json",file=sys.stderr); return 2
    try:
        witness=json.loads(Path(argv[2]).read_text(encoding="utf-8")); landmark_analysis=json.loads(Path(argv[3]).read_text(encoding="utf-8"))
        out=analyze(Path(argv[1]),witness,landmark_analysis,Path(argv[4])); Path(argv[5]).write_text(json.dumps(out,indent=2)+"\n",encoding="utf-8")
    except Exception as exc:
        print(f"CIV1_RIGHTFOOT_CONTACT_LOCAL_SOLE_FAIL: {exc}",file=sys.stderr); return 3
    print("CIV1_RIGHTFOOT_CONTACT_LOCAL_SOLE_CLASSIFIED",out["mean_normalized_offset_x_by_distance"],out["distance_mean_relative_spread"],out["max_within_distance_relative_deviation"],out["verdict"]); return 0

if __name__=="__main__": raise SystemExit(main(sys.argv))
