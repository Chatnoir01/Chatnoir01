#!/usr/bin/env python3
"""Correlate dense same-row raster motion with canonical LeftFoot projection.

Diagnostic only. Uses the exact player-distance witness camera contract (1280x720,
vertical FOV 45 deg, camera=(d, placement+0.23, 0), target=(0, placement+0.16, 0))
and canonical-ground LeftFoot world samples. Magnitude agreement alone is not enough:
one global screen orientation must explain signed motion at every distance.
"""
from __future__ import annotations
import json, math, sys
from pathlib import Path

DISTANCES=(2,4,8)
WIDTH=1280; HEIGHT=720; VERTICAL_FOV_DEG=45.0
CAMERA_Y_OFFSET=0.23; TARGET_Y_OFFSET=0.16
MAX_PATH_REL_ERROR=0.25
MIN_COMMON_SAMPLES=5
CAMERA_CONTRACT_SOURCE_COMMIT="f24157e28526ef517586efe8928b0be6adf28462"


def _claims_false(d:dict)->bool:
    return all(d.get(k) is False for k in (
        'perceptual_2_8m_claimed','planted_contact_claimed','animation_correction_authorized',
        'runtime_authorized','visual_approval_claimed','player_view_claimed'))

def _longest_contiguous(values):
    vals=sorted(set(int(v) for v in values)); best=[]; cur=[]
    for v in vals:
        if not cur or v==cur[-1]+1: cur.append(v)
        else:
            if len(cur)>len(best): best=cur
            cur=[v]
    if len(cur)>len(best): best=cur
    return best

def _path(xs): return sum(abs(xs[i]-xs[i-1]) for i in range(1,len(xs)))
def _signed(xs): return xs[-1]-xs[0]
def _rel(a,b): return abs(a-b)/max(abs(b),1e-12)

def _project_x(world, distance_m:float, placement_y:float)->float:
    x,y,z=(float(v) for v in world)
    cy=placement_y+CAMERA_Y_OFFSET; ty=placement_y+TARGET_Y_OFFSET
    fx=-distance_m; fy=ty-cy
    n=math.hypot(fx,fy)
    forward=(fx/n,fy/n,0.0)
    vx=x-distance_m; vy=y-cy
    depth=vx*forward[0]+vy*forward[1]
    if not math.isfinite(depth) or depth<=0: raise ValueError('invalid projected depth')
    focal=HEIGHT/(2.0*math.tan(math.radians(VERTICAL_FOV_DEG)/2.0))
    return focal*(z/depth)

def correlate(dense:dict, ground:dict)->dict:
    if dense.get('schema')!='grand-bruxelles-civ1-dense-bottomrow-subpixel-v2': raise ValueError('dense schema')
    if dense.get('position_row_semantic')!='same_bottom_most_near_white_row': raise ValueError('dense semantic')
    if dense.get('diagnostic_only') is not True or not _claims_false(dense): raise ValueError('dense claim rail')
    if ground.get('schema')!='grand-bruxelles-civ1-left-ground-reference-v2': raise ValueError('ground schema')
    if ground.get('diagnostic_only') is not True or ground.get('ground_contact_claimed') is not False: raise ValueError('ground claim rail')
    if ground.get('reference_semantic')!='canonical_main_ground_collision_raycast': raise ValueError('ground semantic')
    if ground.get('resolution')!=[WIDTH,HEIGHT]: raise ValueError('ground resolution')
    placement=float(ground['placement_y_m'])
    gmap={int(r['sample_index']):r for r in ground.get('samples',[]) if isinstance(r,dict)}
    dense_by={int(m['distance_m']):m for m in dense.get('distance_measurements',[]) if isinstance(m,dict)}
    if set(dense_by)!=set(DISTANCES): raise ValueError('distance set')
    overlap=set(int(v) for v in dense.get('selected_common_samples',[])) & set(gmap)
    window=_longest_contiguous(overlap)
    if len(window)<MIN_COMMON_SAMPLES: raise ValueError(f'insufficient geometry/raster overlap: {window}')
    per=[]
    for distance in DISTANCES:
        rmap={int(r['sample_index']):r for r in dense_by[distance].get('records',[]) if isinstance(r,dict)}
        if any(s not in rmap for s in window): raise ValueError('dense record gap')
        obs=[float(rmap[s]['subpixel_centroid_x_px']) for s in window]
        proj=[_project_x(gmap[s]['left_world'],float(distance),placement) for s in window]
        op=_path(obs); pp=_path(proj); os=_signed(obs); ps=_signed(proj)
        per.append({'distance_m':distance,'samples':window,'observed_path_px':op,'projected_leftfoot_path_px':pp,
                    'path_relative_error':_rel(op,pp),'magnitude_passed':_rel(op,pp)<=MAX_PATH_REL_ERROR,
                    'observed_signed_displacement_px':os,'projected_signed_displacement_px_orientation_plus':ps})
    candidates=[]
    for orientation in (1,-1):
        matches=[]
        for m in per:
            expected=orientation*m['projected_signed_displacement_px_orientation_plus']
            observed=m['observed_signed_displacement_px']
            matches.append(abs(expected)>1e-9 and abs(observed)>1e-9 and ((expected>0)==(observed>0)))
        candidates.append({'orientation_sign':orientation,'direction_matches':matches,'all_distances_match':all(matches)})
    orientation_ok=any(c['all_distances_match'] for c in candidates)
    magnitude_ok=all(m['magnitude_passed'] for m in per)
    quantitative=magnitude_ok and orientation_ok
    verdict=('AMELIORER_PROJECTION_CORRELATION_CONSISTENT_NO_PROMOTION' if quantitative
             else 'AMELIORER_PROJECTION_DIRECTION_INCONSISTENT_NO_PROMOTION' if magnitude_ok and not orientation_ok
             else 'AMELIORER_PROJECTION_MAGNITUDE_INCONSISTENT_NO_PROMOTION')
    return {'schema':'grand-bruxelles-civ1-raster-projection-correlation-v1','diagnostic_only':True,
            'camera_contract_source_commit':CAMERA_CONTRACT_SOURCE_COMMIT,'resolution':[WIDTH,HEIGHT],
            'vertical_fov_deg':VERTICAL_FOV_DEG,'camera_y_offset_m':CAMERA_Y_OFFSET,'target_y_offset_m':TARGET_Y_OFFSET,
            'common_samples':window,'minimum_common_samples':MIN_COMMON_SAMPLES,'max_path_relative_error':MAX_PATH_REL_ERROR,
            'measurements':per,'orientation_candidates':candidates,'magnitude_consistent_all_distances':magnitude_ok,
            'single_screen_orientation_consistent':orientation_ok,'quantitative_raster_projection_candidate':quantitative,
            'perceptual_2_8m_claimed':False,'planted_contact_claimed':False,'animation_correction_authorized':False,
            'runtime_authorized':False,'visual_approval_claimed':False,'player_view_claimed':False,'verdict':verdict}

def main(argv):
    if len(argv)!=4:
        print('usage: correlate_civ1_dense_raster_projection.py DENSE.json GROUND.json OUT.json',file=sys.stderr); return 2
    try:
        dense=json.loads(Path(argv[1]).read_text(encoding='utf-8')); ground=json.loads(Path(argv[2]).read_text(encoding='utf-8'))
        out=correlate(dense,ground); Path(argv[3]).write_text(json.dumps(out,indent=2)+'\n',encoding='utf-8')
    except Exception as exc:
        print(f'CIV1_RASTER_PROJECTION_CORRELATION_FAIL: {exc}',file=sys.stderr); return 3
    print('CIV1_RASTER_PROJECTION_CORRELATION_OK',[(m['distance_m'],m['observed_path_px'],m['projected_leftfoot_path_px'],m['path_relative_error']) for m in out['measurements']],out['single_screen_orientation_consistent'],out['verdict'])
    return 0
if __name__=='__main__': raise SystemExit(main(sys.argv))
