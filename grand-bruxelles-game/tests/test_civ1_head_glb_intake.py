import importlib.util, json, struct
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
      'nodes':[{'name':'HeadMesh','mesh':0,'skin':0},{'name':'Head'}],
      'meshes':[{'primitives':[{'attributes':{'POSITION':0},'material':0}]}],
      'materials':[{'name':'skin'}], 'skins':[{'joints':[1]}],
      'accessors':[{'componentType':5126,'count':1,'type':'VEC3','min':[0,0,0],'max':[1,1,1]}]
    }

def write(tmp_path,doc):
    p=tmp_path/'head.glb'; p.write_bytes(glb(doc)); return p

def test_accepts_skinned_material_head(tmp_path):
    r=m.inspect(write(tmp_path,valid_doc()))
    assert r['intake_pass'] and r['skin_count']==1 and r['head_or_neck_joint_present']
    assert r['runtime_authorized'] is False and r['visual_approval_claimed'] is False

def test_rejects_missing_skin(tmp_path):
    d=valid_doc(); d['skins']=[]; d['nodes'][0].pop('skin')
    assert m.inspect(write(tmp_path,d))['intake_pass'] is False

def test_rejects_unbound_material(tmp_path):
    d=valid_doc(); d['meshes'][0]['primitives'][0].pop('material')
    assert m.inspect(write(tmp_path,d))['intake_pass'] is False

def test_rejects_missing_head_anchor(tmp_path):
    d=valid_doc(); d['nodes'][1]['name']='Spine'
    assert m.inspect(write(tmp_path,d))['intake_pass'] is False

def test_rejects_nonfinite_accessor_bounds(tmp_path):
    d=valid_doc(); d['accessors'][0]['max'][2]=float('inf')
    assert m.inspect(write(tmp_path,d))['intake_pass'] is False
