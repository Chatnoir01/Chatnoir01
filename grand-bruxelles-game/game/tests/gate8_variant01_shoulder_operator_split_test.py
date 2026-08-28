#!/usr/bin/env python3
import json, pathlib, sys

contract=json.load(open(sys.argv[1]))
result=json.load(open(sys.argv[2]))
errors=[]

def need(cond,msg):
    if not cond: errors.append(msg)

need(result.get('diagnostic_state')==contract['source_artifact']['expected_state'],'state drift')
need(result.get('failures')==[],'source diagnostic failures')
need(result.get('shoulder_report_count')==2,'shoulder count drift')
need(result.get('isolated_broad_endpoint_count')==1,'isolated count drift')
need(result.get('extended_broad_endpoint_count')==1,'extended count drift')
rows={int(x['broad_vertex']):x for x in result.get('shoulders',[])}
for side in ('expected_left','expected_right'):
    exp=contract[side]
    row=rows.get(exp['broad_vertex'])
    need(row is not None,f'{side} broad vertex missing')
    if row:
        need(int(row.get('coherent_vertex',-1))==exp['coherent_vertex'],f'{side} coherent vertex drift')
        need(int(row.get('broad_like_count',-1))==exp['broad_like_count'],f'{side} broad-like drift')
        need(int(row.get('coherent_like_count',-1))==exp['coherent_like_count'],f'{side} coherent-like drift')
        family='ISOLATED_BROAD_ENDPOINT' if int(row.get('broad_like_count',-1))==0 else 'EXTENDED_BROAD_CLUSTER'
        need(family==exp['operator_family'],f'{side} operator family drift')
need(all(v is False for v in contract['rails'].values()),'authorization rail opened')
need(result.get('production_activation_allowed') is False,'production activation opened')
need(result.get('visual_approval_allowed') is False,'visual approval opened')
if errors:
    print('SHOULDER_OPERATOR_SPLIT_FAIL: '+'; '.join(errors))
    raise SystemExit(1)
print('SHOULDER_OPERATOR_SPLIT_CONFIRMED left=ISOLATED_BROAD_ENDPOINT right=EXTENDED_BROAD_CLUSTER')
