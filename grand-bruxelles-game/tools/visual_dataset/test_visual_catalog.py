#!/usr/bin/env python3
import importlib.util
from pathlib import Path
p=Path(__file__).with_name('build_wikimedia_catalog.py'); s=importlib.util.spec_from_file_location('v',p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
def page(lic,url='https://upload.wikimedia.org/x.jpg'):
 return {'pageid':1,'title':'File:X.jpg','coordinates':[{'lat':50.85,'lon':4.35}],'imageinfo':[{'url':url,'mime':'image/jpeg','width':100,'height':100,'sha1':'abc','extmetadata':{'LicenseShortName':{'value':lic},'Artist':{'value':'Author'},'LicenseUrl':{'value':'https://creativecommons.org/licenses/by/4.0/'}}}]}
a=m.record(page('CC BY 4.0')); assert a['usage_class']=='REUSABLE_ASSET_SOURCE' and a['author']=='Author' and a['lat']==50.85
b=m.record(page('All Rights Reserved')); assert b['usage_class']=='REFERENCE_ONLY' and b['url']
c=m.record(page('CC BY 4.0','')); assert c['usage_class']=='REFERENCE_ONLY'
assert 'CC BY-SA 4.0' in m.REUSABLE and 'All Rights Reserved' not in m.REUSABLE
print('VISUAL_CATALOG_GUARDRAILS_OK references_preserved=true reusable_classified=true provenance=true')
