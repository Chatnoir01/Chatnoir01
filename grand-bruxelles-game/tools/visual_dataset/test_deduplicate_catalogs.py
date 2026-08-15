#!/usr/bin/env python3
import importlib.util, json, random
from pathlib import Path
p=Path(__file__).with_name('deduplicate_catalogs.py'); s=importlib.util.spec_from_file_location('d',p); d=importlib.util.module_from_spec(s); s.loader.exec_module(d)
rows=[
 {'source':'Commons','source_id':'1','url':'a','lat':50.850000,'lon':4.350000,'sha256':'same','usage_class':'REUSABLE_ASSET_SOURCE'},
 {'source':'Mirror','source_id':'9','url':'b','lat':50.850000,'lon':4.350000,'sha256':'same','usage_class':'REFERENCE_ONLY'},
 {'source':'KartaView','source_id':'2','url':'c','lat':50.850010,'lon':4.350010,'usage_class':'REFERENCE_ONLY'},
 {'source':'KartaView','source_id':'3','url':'d','lat':50.860000,'lon':4.360000,'usage_class':'REFERENCE_ONLY'},
 {'source':'KartaView','source_id':'3','url':'d-copy','lat':50.860000,'lon':4.360000,'usage_class':'REFERENCE_ONLY'},
]
a=d.deduplicate(rows)
shuffled=list(rows); random.Random(42).shuffle(shuffled); b=d.deduplicate(shuffled)
assert a==b, 'input ordering must not change output'
assert a['summary']['input']==5 and a['summary']['canonical']==3 and a['summary']['exact_duplicates_removed']==2
merged=[r for r in a['records'] if r['exact_duplicate_count']==1]
assert len(merged)==2
assert any(set(r['usage_classes'])=={'REFERENCE_ONLY','REUSABLE_ASSET_SOURCE'} for r in merged)
assert a['summary']['possible_cross_source_pairs']>=1, 'near cross-source refs must be flagged, not destroyed'
assert all(pair['a']!=pair['b'] for pair in a['possible_duplicate_pairs'])
print('REFERENCE_DEDUP_GUARDRAILS_OK deterministic=true exact_only=true near_refs_preserved=true')
