import hashlib, importlib.util, json, struct
from pathlib import Path

P=Path(__file__).parents[1]/'tools'/'inspect_civ1_head_glb.py'
s=importlib.util.spec_from_file_location('headintake',P); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)

def glb(doc):
    raw=json.dumps(doc,separators=(',',':')).encode(); raw+=b' ' * ((4-len(raw)%4)%4)
    chunk=struct.pack('<II',len(raw),0x4E4F534A)+raw
    return b'glTF'+struct.pack('<II',2,12+len(chunk))+chunk

def valid_doc():
    return {
      'asset':{'version':'2.0'},'scenes':[{'nodes':[0]}],
      'nodes':[{'name':'HeadMesh','mesh':0}],
      'meshes':[{'primitives':[{'attributes':{'POSITION':0},'material':0,'targets':[{'POSITION':1}]}], 'extras':{'targetNames':['Smile']}}],
      'materials':[{'name':'skin'}], 'skins':[],
      'accessors':[{'componentType':5126,'count':1,'type':'VEC3','min':[0,0,0],'max':[1,1,1]},{'componentType':5126,'count':1,'type':'VEC3'}]
    }

def write(tmp_path,doc):
    p=tmp_path/'head.glb'; p.write_bytes(glb(doc)); return p

def inspect_fixture(tmp_path, doc):
    p=write(tmp_path,doc); return m.inspect(p, hashlib.sha256(p.read_bytes()).hexdigest())

def test_accepts_rigid_morph_material_head(tmp_path):
    r=inspect_fixture(tmp_path,valid_doc())
    assert r['intake_pass'] and r['skin_count']==0 and r['morph_target_primitive_count']==1
    assert r['attachment_mode']=='rigid_to_body_head_bone'
    assert r['runtime_authorized'] is False and r['visual_approval_claimed'] is False

def test_rejects_embedded_skin_contract_drift(tmp_path):
    d=valid_doc(); d['skins']=[{'joints':[0]}]; d['nodes'][0]['skin']=0
    assert inspect_fixture(tmp_path,d)['intake_pass'] is False

def test_rejects_unbound_material(tmp_path):
    d=valid_doc(); d['meshes'][0]['primitives'][0].pop('material')
    assert inspect_fixture(tmp_path,d)['intake_pass'] is False

def test_rejects_missing_morph_targets(tmp_path):
    d=valid_doc(); d['meshes'][0]['primitives'][0].pop('targets')
    assert inspect_fixture(tmp_path,d)['intake_pass'] is False

def test_rejects_nonfinite_accessor_bounds(tmp_path):
    d=valid_doc(); d['accessors'][0]['max'][2]=float('inf')
    assert inspect_fixture(tmp_path,d)['intake_pass'] is False

def test_rejects_wrong_digest(tmp_path):
    p=write(tmp_path,valid_doc()); assert m.inspect(p, '0'*64)['intake_pass'] is False
