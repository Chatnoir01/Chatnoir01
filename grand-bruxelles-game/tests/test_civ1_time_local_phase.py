#!/usr/bin/env python3
from __future__ import annotations
import copy, importlib.util
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SPEC=importlib.util.spec_from_file_location('phase',ROOT/'tools'/'assess_civ1_time_local_phase.py'); MOD=importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(MOD)
BASE={'schema':'grand-bruxelles-civ1-time-local-phase-v1','godot_version':'4.7.1','runtime_authorized':False,'visual_approval_claimed':False,'candidates':[{'candidate_id':'time_local_r1','baseline_phase_delta_samples':27,'candidate_phase_delta_samples':27},{'candidate_id':'time_local_r2','baseline_phase_delta_samples':27,'candidate_phase_delta_samples':27},{'candidate_id':'time_local_r4','baseline_phase_delta_samples':27,'candidate_phase_delta_samples':27}]}
r=MOD.assess(copy.deepcopy(BASE)); assert r['verdict']=='BLOCK_TIME_LOCAL_NO_PHASE_IMPROVEMENT'
partial=copy.deepcopy(BASE); partial['candidates'][0]['candidate_phase_delta_samples']=20; assert MOD.assess(partial)['verdict']=='BLOCK_TIME_LOCAL_PHASE_STILL_MATERIAL'
fixed=copy.deepcopy(BASE); fixed['candidates'][0]['candidate_phase_delta_samples']=8; assert MOD.assess(fixed)['verdict']=='REQUIRE_FULL_GROUNDING_ASSESSMENT'
rails=copy.deepcopy(BASE); rails['runtime_authorized']=True
try: MOD.assess(rails)
except ValueError: pass
else: raise AssertionError('runtime rail opened')
forged=copy.deepcopy(BASE); forged['candidates'][1]['baseline_phase_delta_samples']=26
try: MOD.assess(forged)
except ValueError: pass
else: raise AssertionError('baseline phase forgery accepted')
print('CIV1_TIME_LOCAL_PHASE_TEST_OK')
