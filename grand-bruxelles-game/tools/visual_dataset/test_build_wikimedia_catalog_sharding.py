#!/usr/bin/env python3
import importlib.util
from pathlib import Path

HERE=Path(__file__).resolve().parent
SPEC=importlib.util.spec_from_file_location('catalog',HERE/'build_wikimedia_catalog.py')
mod=importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(mod)

rows=[{'pageid':i,'title':f'File:{i}.jpg'} for i in range(1,1001)]
for count in (1,2,4,8,16):
    shards=[[r for r in rows if mod.stable_shard(r,count)==idx] for idx in range(count)]
    flat=[r['pageid'] for shard in shards for r in shard]
    assert sorted(flat)==list(range(1,1001)), (count,'loss')
    assert len(flat)==len(set(flat)), (count,'duplicate')
    assert all(mod.stable_shard(r,count)==idx for idx,shard in enumerate(shards) for r in shard)

fallback={'pageid':None,'title':'File:stable-title-only.jpg'}
assert mod.stable_shard(fallback,8)==mod.stable_shard(dict(fallback),8)
print('COMMONS_SHARDING_GUARDRAILS_OK rows=1000 counts=1,2,4,8,16')
