#!/usr/bin/env python3
"""Measure the rendered sole locally around a verified LeftFoot raster landmark.

This deliberately avoids the rejected whole-silhouette bottom-row, multi-row and
component fallbacks. Foot identity comes from the Skeleton-tied magenta LeftFoot
landmark first; only near-white body pixels inside a marker-scaled local ROI are
considered. The result is diagnostic identity evidence only, never ground contact
or animation authorization.
"""
from __future__ import annotations
import importlib.util, json, math, statistics, sys
from pathlib import Path

HERE=Path(__file__).resolve().parent
LANDMARK_TOOL=HERE/'analyze_civ1_leftfoot_landmark_raster.py'
spec=importlib.util.spec_from_file_location('civ1_landmark',LANDMARK_TOOL)
if spec is None or spec.loader is None: raise RuntimeError('cannot load landmark analyzer')
landmark=importlib.util.module_from_spec(spec); spec.loader.exec_module(landmark)

DISTANCES=(2,4,8)
SAMPLES=(114,115,116,117,118)
ROI_RADIUS_MULT=4.0
MIN_ROI_HALF_WIDTH_PX=8
MAX_DISTANCE_MEAN_REL_SPREAD=0.15
MAX_WITHIN_DISTANCE_REL_DEVIATION=0.15


def _relative(a:float,b:float)->float:
    return abs(a-b)/max(abs(b),1e-12)


def assess_normalized_series(series_by_distance:dict[int,list[float]])->dict:
    if set(series_by_distance)!=set(DISTANCES): raise ValueError('distance series')
    means={d:statistics.mean(series_by_distance[d]) for d in DISTANCES}
    medians={d:statistics.median(series_by_distance[d]) for d in DISTANCES}
    if any(len(series_by_distance[d])!=len(SAMPLES) for d in DISTANCES): raise ValueError('sample series')
    signs={1 if means[d]>0 else -1 if means[d]<0 else 0 for d in DISTANCES}
    single_side=signs in ({1},{-1})
    center=statistics.median(means.values())
    mean_spread=(max(means.values())-min(means.values()))/max(abs(center),1e-12)
    within={d:max(_relative(v,medians[d]) for v in series_by_distance[d]) for d in DISTANCES}
    passed=single_side and mean_spread<=MAX_DISTANCE_MEAN_REL_SPREAD and all(v<=MAX_WITHIN_DISTANCE_REL_DEVIATION for v in within.values())
    return {'mean_normalized_offset_x_by_distance':means,'median_normalized_offset_x_by_distance':medians,
            'distance_mean_relative_spread':mean_spread,'max_within_distance_relative_deviation':within,
            'single_side_consistent':single_side,'passed':passed}


def local_sole_observation(path:Path)->dict:
    width,height,rows=landmark.read_png(path); channels=len(rows[0])//width
    marker=landmark.marker_centroid(path)
    marker_radius_px=math.sqrt(marker['marker_pixel_count']/math.pi)
    if marker_radius_px<=0 or not math.isfinite(marker_radius_px): raise ValueError('marker radius')
    roi=max(MIN_ROI_HALF_WIDTH_PX,int(math.ceil(ROI_RADIUS_MULT*marker_radius_px)))
    cx=float(marker['centroid_x_px']); cy=float(marker['centroid_y_px'])
    white=[]
    x0=max(0,int(math.floor(cx-roi))); x1=min(width-1,int(math.ceil(cx+roi)))
    y0=max(0,int(math.floor(cy-roi))); y1=min(height-1,int(math.ceil(cy+roi)))
    for y in range(y0,y1+1):
        row=rows[y]
        for x in range(x0,x1+1):
            i=x*channels; r,g,b=row[i],row[i+1],row[i+2]
            if r>=220 and g>=220 and b>=220:
                white.append((x,y))
    if not white: raise ValueError(f'no local near-white sole pixels in {path}')
    bottom_y=max(y for _,y in white); bottom_xs=[x for x,y in white if y==bottom_y]
    if not bottom_xs: raise ValueError('local bottom row')
    bottom_centroid_x=sum(bottom_xs)/len(bottom_xs)
    return {'marker_centroid_x_px':cx,'marker_centroid_y_px':cy,'marker_pixel_count':marker['marker_pixel_count'],
            'marker_radius_px':marker_radius_px,'roi_half_width_px':roi,'local_bottom_y_px':bottom_y,
            'local_bottom_centroid_x_px':bottom_centroid_x,'local_bottom_pixel_count':len(bottom_xs),
            'normalized_offset_x':(bottom_centroid_x-cx)/marker_radius_px,
            'normalized_offset_y':(bottom_y-cy)/marker_radius_px}


def analyze(witness:dict,capture_dir:Path)->dict:
    if witness.get('schema')!='grand-bruxelles-civ1-leftfoot-landmark-witness-v1': raise ValueError('witness schema')
    if witness.get('landmark_semantic')!='leftfoot_bone_pose_with_verified_same_skeleton_skin': raise ValueError('identity semantic')
    if witness.get('marker_no_depth_test') is not True or float(witness.get('marker_radius_m',0))!=0.025: raise ValueError('marker contract')
    if witness.get('resolution')!=[1280,720] or float(witness.get('vertical_fov_deg',0))!=45.0: raise ValueError('camera contract')
    for key in ('perceptual_2_8m_claimed','planted_contact_claimed','animation_correction_authorized','runtime_authorized','visual_approval_claimed','player_view_claimed'):
        if witness.get(key) is not False: raise ValueError('upstream claim '+key)
    cmap={(int(c['distance_m']),int(c['sample_index'])):c for c in witness.get('captures',[]) if isinstance(c,dict)}
    if set(cmap)!={(d,s) for d in DISTANCES for s in SAMPLES}: raise ValueError('capture matrix')
    measurements=[]; series={}
    for d in DISTANCES:
        records=[]
        for s in SAMPLES:
            path=capture_dir/Path(cmap[(d,s)]['png']).name
            records.append({'sample_index':s,**local_sole_observation(path)})
        series[d]=[r['normalized_offset_x'] for r in records]
        measurements.append({'distance_m':d,'records':records,
                             'mean_normalized_offset_x':statistics.mean(series[d]),
                             'median_normalized_offset_x':statistics.median(series[d]),
                             'normalized_offset_y_span':max(r['normalized_offset_y'] for r in records)-min(r['normalized_offset_y'] for r in records)})
    quality=assess_normalized_series(series)
    passed=quality['passed']
    return {'schema':'grand-bruxelles-civ1-leftfoot-local-sole-v1','diagnostic_only':True,
            'identity_anchor':'verified_leftfoot_bone_magenta_landmark','pixel_semantic':'near_white_lowest_row_inside_marker_scaled_roi',
            'roi_radius_multiplier':ROI_RADIUS_MULT,'min_roi_half_width_px':MIN_ROI_HALF_WIDTH_PX,
            'max_distance_mean_relative_spread':MAX_DISTANCE_MEAN_REL_SPREAD,
            'max_within_distance_relative_deviation':MAX_WITHIN_DISTANCE_REL_DEVIATION,
            'measurements':measurements,**quality,
            'bone_local_sole_identity_preserved_2_4_8m':passed,
            'quantitative_foot_slide_candidate':False,'perceptual_2_8m_claimed':False,'planted_contact_claimed':False,
            'animation_correction_authorized':False,'runtime_authorized':False,'visual_approval_claimed':False,'player_view_claimed':False,
            'verdict':'AMELIORER_BONE_LOCAL_SOLE_IDENTITY_PRESERVED_NO_SLIDE_PROMOTION' if passed else 'JETER_BONE_LOCAL_SOLE_IDENTITY_UNSTABLE'}


def main(argv:list[str])->int:
    if len(argv)!=4:
        print('usage: analyze_civ1_leftfoot_local_sole.py WITNESS.json CAPTURE_DIR OUT.json',file=sys.stderr); return 2
    try:
        witness=json.loads(Path(argv[1]).read_text(encoding='utf-8')); out=analyze(witness,Path(argv[2])); Path(argv[3]).write_text(json.dumps(out,indent=2)+'\n',encoding='utf-8')
    except Exception as exc:
        print(f'CIV1_LEFTFOOT_LOCAL_SOLE_FAIL: {exc}',file=sys.stderr); return 3
    print('CIV1_LEFTFOOT_LOCAL_SOLE_OK',out['mean_normalized_offset_x_by_distance'],out['distance_mean_relative_spread'],out['verdict'])
    return 0 if out['bone_local_sole_identity_preserved_2_4_8m'] else 4

if __name__=='__main__': raise SystemExit(main(sys.argv))
