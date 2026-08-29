#!/usr/bin/env python3
import json, pathlib, sys

if len(sys.argv) != 4:
    raise SystemExit('usage: gate8_variant01_residual_shoulder_topology.py CONTRACT SPLIT_AB_DIR OUTPUT')
contract=json.load(open(sys.argv[1]))
root=pathlib.Path(sys.argv[2])
out=pathlib.Path(sys.argv[3])


def load(name):
    p=root/name
    if not p.is_file():
        raise AssertionError(f'missing artifact member: {name}')
    return json.loads(p.read_text())

summary=load('split-shoulder-ab-result.json')
baseline=load('baseline-result.json')
left=load('left-result.json')
right=load('right-result.json')
materialize=load('materialize-summary.json')
exp=contract['expected']

assert summary['diagnostic_state']==exp['diagnostic_state']=='BOTH_OPERATORS_REJECTED'
assert summary['left']['state']==exp['left_state']=='LOCAL_NOT_SUPERIOR'
assert summary['right']['state']==exp['right_state']=='LOCAL_NOT_SUPERIOR'
assert summary['left']['baseline']['blocked_case_count']==6==summary['left']['candidate']['blocked_case_count']
assert summary['right']['baseline']['blocked_case_count']==6==summary['right']['candidate']['blocked_case_count']
assert summary['left']['improved']=={
    'blocked_case_count':False,'max_edge_absolute_change_m':True,
    'max_edge_stretch_ratio':False,'min_edge_compression_ratio':False}
assert not any(summary['right']['improved'].values())

def edge(d): return sorted([int(d['worst_edge']['vertex_a']),int(d['worst_edge']['vertex_b'])])
assert edge(baseline)==sorted(exp['baseline_worst_edge'])
assert edge(left)==sorted(exp['left_worst_edge'])
assert edge(right)==sorted(exp['right_worst_edge'])
cluster=sorted(int(v) for v in materialize['report']['right']['corrected_vertices'])
assert cluster==sorted(exp['right_modified_cluster'])
assert 1510 in cluster and 1510 in edge(right)
assert set(edge(right)) != set(edge(baseline))
assert int(right['worst_edge']['triangle']) != int(baseline['worst_edge']['triangle'])
ratio=float(summary['right']['candidate']['max_edge_stretch_ratio'])/float(summary['right']['baseline']['max_edge_stretch_ratio'])
assert ratio >= float(exp['right_stretch_regression_min_ratio'])
assert float(summary['right']['candidate']['max_edge_absolute_change_m']) > float(summary['right']['baseline']['max_edge_absolute_change_m'])
assert float(summary['right']['candidate']['min_edge_compression_ratio']) == float(summary['right']['baseline']['min_edge_compression_ratio'])
assert all(v is False for v in contract['rails'].values())

result={
  'format':'grand-bruxelles-gate8-variant01-residual-shoulder-topology-result-v1',
  'candidate_variant':1,
  'diagnostic_state':'RIGHT_CLUSTER_OPERATOR_CREATES_ADJACENT_RESIDUAL_FAILURE',
  'left':{
    'state':'LOCAL_NOT_SUPERIOR_NONREGRESSIVE_GLOBAL_WORST_EDGE',
    'global_worst_edge':edge(left),
    'blocked_case_count':summary['left']['candidate']['blocked_case_count']
  },
  'right':{
    'state':'LOCAL_NOT_SUPERIOR_WORST_EDGE_MIGRATION',
    'baseline_worst_edge':edge(baseline),
    'candidate_worst_edge':edge(right),
    'candidate_worst_triangle':right['worst_edge']['triangle'],
    'modified_vertex_on_new_worst_edge':1510,
    'stretch_regression_ratio':ratio,
    'stretch_baseline':summary['right']['baseline']['max_edge_stretch_ratio'],
    'stretch_candidate':summary['right']['candidate']['max_edge_stretch_ratio']
  },
  'next_safe_axis':'MAP_RIGHT_CLUSTER_BOUNDARY_ONE_RING_BEFORE_ANY_MORE_REWEIGHT',
  'production_activation_allowed':False,
  'visual_approval_allowed':False
}
out.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
print(json.dumps(result,sort_keys=True))
