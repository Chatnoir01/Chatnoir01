#!/usr/bin/env python3
"""Dense temporal same-bottom-row subpixel analysis for CIV-1 player-distance rasters.

Diagnostic only. Preflights every 111..119 capture with the validated sparse
same-bottom-row estimator, selects the longest contiguous sample window resolved
at all 2/4/8 m distances, requires at least seven common samples, then evaluates
perspective-scale consistency without lowering the 15-pixel semantic floor.
"""
from __future__ import annotations
import importlib.util, json, math, sys
from pathlib import Path
DISTANCES=(2,4,8); SAMPLES=tuple(range(111,120)); MIN_COMMON_SAMPLES=7; MAX_SCALE_REL_ERROR=0.25

def _load_sparse():
    p=Path(__file__).with_name('analyze_civ1_bottomrow_subpixel.py'); spec=importlib.util.spec_from_file_location('civ1_sparse_subpixel',p)
    if spec is None or spec.loader is None: raise RuntimeError('cannot load sparse estimator')
    m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    if not callable(getattr(m,'observation',None)): raise RuntimeError('validated sparse observation API unavailable')
    return m

def _path(records):
    v=sum(abs(records[i]['subpixel_centroid_x_px']-records[i-1]['subpixel_centroid_x_px']) for i in range(1,len(records)))
    if not math.isfinite(v): raise ValueError('non-finite path')
    return v

def _steps(records):
    out=[abs(records[i]['subpixel_centroid_x_px']-records[i-1]['subpixel_centroid_x_px']) for i in range(1,len(records))]
    if not all(math.isfinite(v) for v in out): raise ValueError('non-finite step')
    return out

def _rel(measured,expected): return abs(measured-expected)/max(abs(expected),1e-9)

def longest_contiguous(samples):
    vals=sorted(set(int(v) for v in samples)); best=[]; cur=[]
    for v in vals:
        if not cur or v==cur[-1]+1: cur.append(v)
        else:
            if len(cur)>len(best): best=cur
            cur=[v]
    if len(cur)>len(best): best=cur
    return best

def scale_calibration(measurements):
    by={int(d['distance_m']):d for d in measurements}; p2=float(by[2]['subpixel_path_px']); p4=float(by[4]['subpixel_path_px']); p8=float(by[8]['subpixel_path_px'])
    e4=p2*0.5; e8=p4*0.5; nerr=_rel(p4,e4); ferr=_rel(p8,e8)
    return {'near_2_to_4_expected_half':e4,'near_2_to_4_relative_error':nerr,'near_calibration_passed':nerr<=MAX_SCALE_REL_ERROR,'far_4_to_8_expected_half':e8,'far_4_to_8_relative_error':ferr,'far_scale_calibration_passed':ferr<=MAX_SCALE_REL_ERROR,'quantitative_8m_candidate':nerr<=MAX_SCALE_REL_ERROR and ferr<=MAX_SCALE_REL_ERROR}

def analyze(capture_dir:Path):
    sparse=_load_sparse(); resolved={d:{} for d in DISTANCES}; rejected=[]
    for d in DISTANCES:
        for s in SAMPLES:
            p=capture_dir/f'civ1-distance-{d}m-{s}.png'
            if not p.is_file(): raise ValueError(f'missing capture d={d} sample={s}')
            try:
                rec=sparse.observation(p)
                if rec['position_row_semantic']!='same_bottom_most_near_white_row': raise ValueError('semantic drift')
                resolved[d][s]={'sample_index':s,**rec}
            except ValueError as exc:
                rejected.append({'distance_m':d,'sample_index':s,'reason':str(exc)})
    common=set(SAMPLES)
    for d in DISTANCES: common &= set(resolved[d])
    window=longest_contiguous(common)
    if len(window)<MIN_COMMON_SAMPLES: raise ValueError(f'insufficient common resolved window: {window}')
    measurements=[]
    for d in DISTANCES:
        records=[resolved[d][s] for s in window]; steps=_steps(records)
        measurements.append({'distance_m':d,'records':records,'subpixel_path_px':_path(records),'step_count':len(steps),'step_mean_px':sum(steps)/len(steps),'step_max_px':max(steps)})
    scale=scale_calibration(measurements)
    verdict='AMELIORER_DENSE_TEMPORAL_SCALE_CONSISTENT_NO_PROMOTION' if scale['quantitative_8m_candidate'] else 'AMELIORER_DENSE_TEMPORAL_8M_SCALE_REJECTED_NO_PROMOTION'
    return {'schema':'grand-bruxelles-civ1-dense-bottomrow-subpixel-v2','diagnostic_only':True,'source_semantic':'fresh_godot_1280x720_dense_same_bottom_most_row_luminance_weighted','position_row_semantic':'same_bottom_most_near_white_row','distances_m':list(DISTANCES),'requested_samples':list(SAMPLES),'selected_common_samples':window,'selected_common_sample_count':len(window),'minimum_common_samples':MIN_COMMON_SAMPLES,'rejected_observations':rejected,'distance_measurements':measurements,'distance_scale_calibration':scale,'perceptual_2_8m_claimed':False,'planted_contact_claimed':False,'animation_correction_authorized':False,'runtime_authorized':False,'visual_approval_claimed':False,'player_view_claimed':False,'verdict':verdict}

def main(argv):
    if len(argv)!=3: print('usage: analyze_civ1_dense_bottomrow_subpixel.py CAPTURE_DIR OUT.json',file=sys.stderr); return 2
    try: r=analyze(Path(argv[1])); Path(argv[2]).write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8')
    except Exception as exc: print(f'CIV1_DENSE_BOTTOMROW_SUBPIXEL_FAIL: {exc}',file=sys.stderr); return 3
    print('CIV1_DENSE_BOTTOMROW_SUBPIXEL_OK',r['selected_common_samples'],{d['distance_m']:d['subpixel_path_px'] for d in r['distance_measurements']},r['distance_scale_calibration'],r['verdict']); return 0
if __name__=='__main__': raise SystemExit(main(sys.argv))