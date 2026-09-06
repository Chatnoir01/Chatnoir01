#!/usr/bin/env python3
"""Dense temporal same-bottom-row subpixel analysis for CIV-1 player-distance rasters.

Diagnostic only. Uses the exact bottom-most near-white row semantic and the same
subpixel weighting contract as the validated sparse v3 estimator, but evaluates
nine consecutive source frames so 8 m evidence is not decided by four samples.
"""
from __future__ import annotations
import importlib.util, json, math, sys
from pathlib import Path

DISTANCES=(2,4,8)
SAMPLES=tuple(range(111,120))
MAX_SCALE_REL_ERROR=0.25


def _load_sparse():
    p=Path(__file__).with_name('analyze_civ1_bottomrow_subpixel.py')
    spec=importlib.util.spec_from_file_location('civ1_sparse_subpixel',p)
    if spec is None or spec.loader is None: raise RuntimeError('cannot load sparse estimator')
    m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m


def _path(records:list[dict])->float:
    v=sum(abs(records[i]['subpixel_centroid_x_px']-records[i-1]['subpixel_centroid_x_px']) for i in range(1,len(records)))
    if not math.isfinite(v): raise ValueError('non-finite path')
    return v


def _steps(records:list[dict])->list[float]:
    out=[abs(records[i]['subpixel_centroid_x_px']-records[i-1]['subpixel_centroid_x_px']) for i in range(1,len(records))]
    if not all(math.isfinite(v) for v in out): raise ValueError('non-finite step')
    return out


def _rel(measured:float,expected:float)->float:
    return abs(measured-expected)/max(abs(expected),1e-9)


def scale_calibration(measurements:list[dict])->dict:
    by={int(d['distance_m']):d for d in measurements}
    p2=float(by[2]['subpixel_path_px']); p4=float(by[4]['subpixel_path_px']); p8=float(by[8]['subpixel_path_px'])
    e4=p2*0.5; e8=p4*0.5
    nerr=_rel(p4,e4); ferr=_rel(p8,e8)
    return {
        'near_2_to_4_expected_half':e4,
        'near_2_to_4_relative_error':nerr,
        'near_calibration_passed':nerr<=MAX_SCALE_REL_ERROR,
        'far_4_to_8_expected_half':e8,
        'far_4_to_8_relative_error':ferr,
        'far_scale_calibration_passed':ferr<=MAX_SCALE_REL_ERROR,
        'quantitative_8m_candidate':nerr<=MAX_SCALE_REL_ERROR and ferr<=MAX_SCALE_REL_ERROR,
    }


def analyze(capture_dir:Path)->dict:
    sparse=_load_sparse(); measurements=[]
    for distance in DISTANCES:
        records=[]
        for sample in SAMPLES:
            path=capture_dir/f'civ1-distance-{distance}m-{sample:03d}.png'
            if not path.is_file(): raise ValueError(f'missing capture d={distance} sample={sample}')
            rec=sparse.measure(path)
            if rec['position_row_semantic']!='same_bottom_most_near_white_row': raise ValueError('semantic drift')
            records.append({'sample_index':sample,**rec})
        steps=_steps(records)
        measurements.append({
            'distance_m':distance,
            'records':records,
            'subpixel_path_px':_path(records),
            'step_count':len(steps),
            'step_mean_px':sum(steps)/len(steps),
            'step_max_px':max(steps),
        })
    scale=scale_calibration(measurements)
    verdict='AMELIORER_DENSE_TEMPORAL_SCALE_CONSISTENT_NO_PROMOTION' if scale['quantitative_8m_candidate'] else 'AMELIORER_DENSE_TEMPORAL_8M_SCALE_REJECTED_NO_PROMOTION'
    return {
        'schema':'grand-bruxelles-civ1-dense-bottomrow-subpixel-v1',
        'diagnostic_only':True,
        'source_semantic':'fresh_godot_1280x720_dense_same_bottom_most_row_luminance_weighted',
        'position_row_semantic':'same_bottom_most_near_white_row',
        'distances_m':list(DISTANCES),
        'samples':list(SAMPLES),
        'sample_count_per_distance':len(SAMPLES),
        'distance_measurements':measurements,
        'distance_scale_calibration':scale,
        'perceptual_2_8m_claimed':False,
        'planted_contact_claimed':False,
        'animation_correction_authorized':False,
        'runtime_authorized':False,
        'visual_approval_claimed':False,
        'player_view_claimed':False,
        'verdict':verdict,
    }


def main(argv:list[str])->int:
    if len(argv)!=3:
        print('usage: analyze_civ1_dense_bottomrow_subpixel.py CAPTURE_DIR OUT.json',file=sys.stderr); return 2
    try:
        r=analyze(Path(argv[1])); Path(argv[2]).write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8')
    except Exception as exc:
        print(f'CIV1_DENSE_BOTTOMROW_SUBPIXEL_FAIL: {exc}',file=sys.stderr); return 3
    print('CIV1_DENSE_BOTTOMROW_SUBPIXEL_OK', {d['distance_m']:d['subpixel_path_px'] for d in r['distance_measurements']}, r['distance_scale_calibration'], r['verdict'])
    return 0

if __name__=='__main__': raise SystemExit(main(sys.argv))
