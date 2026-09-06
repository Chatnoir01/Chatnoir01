#!/usr/bin/env python3
"""Fail-closed phase selector for CIV-1 LeftFoot contact evidence."""
from __future__ import annotations
import json, math, sys
from pathlib import Path
FRAME_COUNT=120
IDENTITY_SAMPLES=(114,115,116,117,118)
CONTACT_RENDER_SAMPLES=(118,119,0,1,2)
LOW_BAND_M=0.010

def _origin(frame:dict,bone:str)->tuple[float,float,float]:
 v=frame.get('poses',{}).get(bone,{}).get('origin')
 if not isinstance(v,list) or len(v)!=3: raise ValueError(f'{bone} origin')
 return float(v[0]),float(v[1]),float(v[2])
def assess_bundle(bundle:dict,rendered_samples:set[int]|None=None)->dict:
 if bundle.get('schema')!='grand-bruxelles-civ1-skeleton-witness-bundle-v1': raise ValueError('bundle schema')
 frames=bundle.get('frames',[])
 if not isinstance(frames,list) or len(frames)!=FRAME_COUNT: raise ValueError('frame count')
 left=[_origin(frames[i],'LeftFoot') for i in range(FRAME_COUNT)]; ys=[p[1] for p in left]; min_y=min(ys); min_sample=ys.index(min_y); offsets=[y-min_y for y in ys]
 low={i for i,o in enumerate(offsets) if o<=LOW_BAND_M+1e-12}; prev_i=(min_sample-1)%FRAME_COUNT; next_i=(min_sample+1)%FRAME_COUNT; prev_low=prev_i in low; next_low=next_i in low; two_sided=prev_low and next_low
 rendered=set(IDENTITY_SAMPLES if rendered_samples is None else rendered_samples); target=set(CONTACT_RENDER_SAMPLES); contact_target_contains_min=min_sample in target; contact_complete=target.issubset(rendered); identity_contains=min_sample in set(IDENTITY_SAMPLES); contact_contains=min_sample in rendered
 horizontal_path=0.0
 for a,b in ((prev_i,min_sample),(min_sample,next_i)):
  pa,pb=left[a],left[b]; horizontal_path+=math.hypot(pb[0]-pa[0],pb[2]-pa[2])
 planted=two_sided and contact_target_contains_min and contact_contains and contact_complete
 if planted:
  verdict='AMELIORER_CONTACT_PHASE_BRACKETED_READY_FOR_SOLE_GROUND_CORRELATION'
 elif not contact_target_contains_min:
  verdict='AMELIORER_CONTACT_TARGET_MISALIGNED_NO_SLIDE_PROMOTION'
 elif two_sided:
  verdict='AMELIORER_CONTACT_RENDER_MISSING_NO_SLIDE_PROMOTION'
 else:
  verdict='AMELIORER_CONTACT_MIN_OR_BRACKET_MISSING_NO_SLIDE_PROMOTION'
 return {'schema':'grand-bruxelles-civ1-leftfoot-contact-phase-v2','diagnostic_only':True,'frame_count':FRAME_COUNT,'low_band_m':LOW_BAND_M,'identity_samples':list(IDENTITY_SAMPLES),'contact_render_samples':list(CONTACT_RENDER_SAMPLES),'leftfoot_min_sample':min_sample,'leftfoot_min_height_source_m':min_y,'low_samples':sorted(low),'prev_sample':prev_i,'next_sample':next_i,'prev_offset_from_min_m':offsets[prev_i],'next_offset_from_min_m':offsets[next_i],'prev_low':prev_low,'next_low':next_low,'two_sided_low_contact':two_sided,'identity_window_contains_contact_min':identity_contains,'contact_target_contains_contact_min':contact_target_contains_min,'contact_render_contains_contact_min':contact_contains,'contact_render_complete':contact_complete,'three_sample_horizontal_path_m':horizontal_path,'planted_contact_verified':planted,'quantitative_foot_slide_candidate':planted,'animation_correction_authorized':False,'runtime_authorized':False,'visual_approval_claimed':False,'player_view_claimed':False,'verdict':verdict}
def main(argv:list[str])->int:
 if len(argv)!=3:return 2
 try: out=assess_bundle(json.loads(Path(argv[1]).read_text())); Path(argv[2]).write_text(json.dumps(out,indent=2)+'\n')
 except Exception as exc: print(f'CIV1_LEFTFOOT_CONTACT_PHASE_FAIL: {exc}',file=sys.stderr); return 3
 print('CIV1_LEFTFOOT_CONTACT_PHASE_OK',out['leftfoot_min_sample'],out['prev_low'],out['next_low'],out['contact_target_contains_contact_min'],out['identity_window_contains_contact_min'],out['contact_render_complete'],out['verdict']); return 0
if __name__=='__main__': raise SystemExit(main(sys.argv))
