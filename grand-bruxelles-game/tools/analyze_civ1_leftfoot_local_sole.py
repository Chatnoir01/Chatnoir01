#!/usr/bin/env python3
from __future__ import annotations
import importlib.util, json, math, statistics, sys
from pathlib import Path
HERE=Path(__file__).resolve().parent; LANDMARK_TOOL=HERE/'analyze_civ1_leftfoot_landmark_raster.py'; spec=importlib.util.spec_from_file_location('civ1_landmark',LANDMARK_TOOL); landmark=importlib.util.module_from_spec(spec); spec.loader.exec_module(landmark)
DISTANCES=(2,4,8); SAMPLES=(114,115,116,117,118); ROI_RADIUS_MULT=4.0; MIN_ROI_HALF_WIDTH_PX=8; MAX_DISTANCE_MEAN_REL_SPREAD=0.15; MAX_WITHIN_DISTANCE_REL_DEVIATION=0.15

def _relative(a,b): return abs(a-b)/max(abs(b),1e-12)
def assess_normalized_series(series_by_distance):
 means={d:statistics.mean(series_by_distance[d]) for d in DISTANCES}; medians={d:statistics.median(series_by_distance[d]) for d in DISTANCES}; signs={1 if means[d]>0 else -1 if means[d]<0 else 0 for d in DISTANCES}; center=statistics.median(means.values()); spread=(max(means.values())-min(means.values()))/max(abs(center),1e-12); within={d:max(_relative(v,medians[d]) for v in series_by_distance[d]) for d in DISTANCES}; side=signs in ({1},{-1}); passed=side and spread<=MAX_DISTANCE_MEAN_REL_SPREAD and all(v<=MAX_WITHIN_DISTANCE_REL_DEVIATION for v in within.values()); return {'mean_normalized_offset_x_by_distance':means,'median_normalized_offset_x_by_distance':medians,'distance_mean_relative_spread':spread,'max_within_distance_relative_deviation':within,'single_side_consistent':side,'passed':passed}
def local_sole_observation(path):
 width,height,rows=landmark.read_png(path); channels=len(rows[0])//width; marker=landmark.marker_centroid(path); radius=math.sqrt(marker['marker_pixel_count']/math.pi); roi=max(MIN_ROI_HALF_WIDTH_PX,int(math.ceil(ROI_RADIUS_MULT*radius))); cx=float(marker['centroid_x_px']); cy=float(marker['centroid_y_px']); white=[]
 for y in range(max(0,int(cy-roi)),min(height-1,int(cy+roi))+1):
  row=rows[y]
  for x in range(max(0,int(cx-roi)),min(width-1,int(cx+roi))+1):
   i=x*channels; r,g,b=row[i],row[i+1],row[i+2]
   if r>=220 and g>=220 and b>=220:white.append((x,y))
 if not white: raise ValueError('no local near-white sole pixels')
 by=max(y for _,y in white); xs=[x for x,y in white if y==by]; bx=sum(xs)/len(xs)
 return {'marker_centroid_x_px':cx,'marker_centroid_y_px':cy,'marker_pixel_count':marker['marker_pixel_count'],'marker_radius_px':radius,'roi_half_width_px':roi,'local_bottom_y_px':by,'local_bottom_centroid_x_px':bx,'local_bottom_pixel_count':len(xs),'normalized_offset_x':(bx-cx)/radius,'normalized_offset_y':(by-cy)/radius}
def analyze(witness,capture_dir):
 cmap={(int(c['distance_m']),int(c['sample_index'])):c for c in witness['captures']}; measurements=[]; series={}
 for d in DISTANCES:
  rec=[]
  for s in SAMPLES: rec.append({'sample_index':s,**local_sole_observation(capture_dir/Path(cmap[(d,s)]['png']).name)})
  series[d]=[r['normalized_offset_x'] for r in rec]; measurements.append({'distance_m':d,'records':rec,'mean_normalized_offset_x':statistics.mean(series[d]),'median_normalized_offset_x':statistics.median(series[d]),'normalized_offset_y_span':max(r['normalized_offset_y'] for r in rec)-min(r['normalized_offset_y'] for r in rec)})
 q=assess_normalized_series(series); passed=q['passed']
 return {'schema':'grand-bruxelles-civ1-leftfoot-local-sole-v1','diagnostic_only':True,'identity_anchor':'verified_leftfoot_bone_magenta_landmark','pixel_semantic':'near_white_lowest_row_inside_marker_scaled_roi','roi_radius_multiplier':ROI_RADIUS_MULT,'min_roi_half_width_px':MIN_ROI_HALF_WIDTH_PX,'max_distance_mean_relative_spread':MAX_DISTANCE_MEAN_REL_SPREAD,'max_within_distance_relative_deviation':MAX_WITHIN_DISTANCE_REL_DEVIATION,'measurements':measurements,**q,'bone_local_sole_identity_preserved_2_4_8m':passed,'quantitative_foot_slide_candidate':False,'perceptual_2_8m_claimed':False,'planted_contact_claimed':False,'animation_correction_authorized':False,'runtime_authorized':False,'visual_approval_claimed':False,'player_view_claimed':False,'verdict':'AMELIORER_BONE_LOCAL_SOLE_IDENTITY_PRESERVED_NO_SLIDE_PROMOTION' if passed else 'JETER_BONE_LOCAL_SOLE_IDENTITY_UNSTABLE'}
def main(argv):
 if len(argv)!=4:return 2
 try: out=analyze(json.loads(Path(argv[1]).read_text()),Path(argv[2])); Path(argv[3]).write_text(json.dumps(out,indent=2)+'\n')
 except Exception as exc: print(f'CIV1_LEFTFOOT_LOCAL_SOLE_FAIL: {exc}',file=sys.stderr); return 3
 print('CIV1_LEFTFOOT_LOCAL_SOLE_OK',out['distance_mean_relative_spread'],out['verdict']); return 0 if out['bone_local_sole_identity_preserved_2_4_8m'] else 4
if __name__=='__main__': raise SystemExit(main(sys.argv))
