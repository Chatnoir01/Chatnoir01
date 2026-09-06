#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
TOOL=ROOT/'tools'/'correlate_civ1_dense_raster_projection.py'
spec=importlib.util.spec_from_file_location('corr',TOOL); assert spec and spec.loader
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
S=[114,115,116,117,118]
GROUND=[
(114,[0.133383512496948,-0.0158097445964813,0.33700430393219]),
(115,[0.133269056677818,-0.0178129971027374,0.333140432834625]),
(116,[0.133155688643456,-0.0198075473308563,0.329245001077652]),
(117,[0.133044466376305,-0.0217723250389099,0.325358003377914]),
(118,[0.132934898138046,-0.0237168967723846,0.321460366249084]),]
OBS={2:[421.6118769883351,417.78215693299893,415.5,414.5,414.0],4:[542.6295559973493,543.8726260641781,545.0039037085231,545.3539518900344,545.8193645990923],8:[592.9305135951662,592.5335616438356,593.2530779753762,593.5296074517631,594.187040748163]}

def dense(obs):
    return {'schema':'grand-bruxelles-civ1-dense-bottomrow-subpixel-v2','diagnostic_only':True,'position_row_semantic':'same_bottom_most_near_white_row','selected_common_samples':S,
            'distance_measurements':[{'distance_m':d,'records':[{'sample_index':s,'subpixel_centroid_x_px':x} for s,x in zip(S,obs[d])]} for d in (2,4,8)],
            'perceptual_2_8m_claimed':False,'planted_contact_claimed':False,'animation_correction_authorized':False,'runtime_authorized':False,'visual_approval_claimed':False,'player_view_claimed':False}
def ground():
    return {'schema':'grand-bruxelles-civ1-left-ground-reference-v2','diagnostic_only':True,'ground_contact_claimed':False,'reference_semantic':'canonical_main_ground_collision_raycast','resolution':[1280,720],'placement_y_m':-0.213882654905319,'samples':[{'sample_index':s,'left_world':w} for s,w in GROUND]}

def main():
    r=m.correlate(dense(OBS),ground())
    assert r['common_samples']==S
    assert r['magnitude_consistent_all_distances'] is True
    assert r['single_screen_orientation_consistent'] is False
    assert r['quantitative_raster_projection_candidate'] is False
    assert r['verdict']=='AMELIORER_PROJECTION_DIRECTION_INCONSISTENT_NO_PROMOTION'
    errs={x['distance_m']:x['path_relative_error'] for x in r['measurements']}
    assert 0.04<errs[2]<0.05 and 0.08<errs[4]<0.10 and 0.19<errs[8]<0.20
    # Positive control: exact projected positions share one orientation across all distances.
    g=ground(); placement=g['placement_y_m']; positive={}
    gm={x['sample_index']:x for x in g['samples']}
    for d in (2,4,8): positive[d]=[640.0+m._project_x(gm[s]['left_world'],d,placement) for s in S]
    ok=m.correlate(dense(positive),g)
    assert ok['magnitude_consistent_all_distances'] and ok['single_screen_orientation_consistent'] and ok['quantitative_raster_projection_candidate']
    assert ok['verdict']=='AMELIORER_PROJECTION_CORRELATION_CONSISTENT_NO_PROMOTION'
    print('CIV1_RASTER_PROJECTION_CORRELATION_TEST_OK',errs)
    return 0
if __name__=='__main__': raise SystemExit(main())
