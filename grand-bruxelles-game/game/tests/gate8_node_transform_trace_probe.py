#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, math, os, struct, sys
from pathlib import Path
from typing import Any
import bpy

SOURCE_DIR=Path(os.environ['GATE8_SOURCE_DIR']).resolve()
RESULT_PATH=Path(os.environ['GATE8_TRANSFORM_RESULT']).resolve()
sys.path.insert(0,str(SOURCE_DIR))
import generate_mpfb_gate8_export_ready_glbs as ready

TARGET='npc_gate_01.glb'
TARGET_SHA='912ac8dedf4509640f90771f4c9d3b1af818b59261caab4d9b3f1fb0fe3e2ac9'
TARGET_SIZE=15580240
TARGET_SEED=53756543
OBJECT_FRAGMENT='female_sportsuit01'
GLTF_VERTS=(538,681)
PREPARED_VERTS=(486,601)
COMP={5120:('b',1),5121:('B',1),5122:('h',2),5123:('H',2),5125:('I',4),5126:('f',4)}
COUNT={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}

class StopAfterVariantOne(RuntimeError): pass

def sha256_path(p:Path)->str:
 h=hashlib.sha256()
 with p.open('rb') as f:
  for c in iter(lambda:f.read(1024*1024),b''): h.update(c)
 return h.hexdigest()

def yup(v): return (float(v[0]),float(v[2]),-float(v[1]))
def dist(a,b): return math.sqrt(sum((float(x)-float(y))**2 for x,y in zip(a,b)))
def sub(a,b): return [float(x)-float(y) for x,y in zip(a,b)]
def matmul(a,b):
 return [[sum(a[r][k]*b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]
def apply(m,v):
 x,y,z=map(float,v); q=[x,y,z,1.0]; out=[sum(m[r][k]*q[k] for k in range(4)) for r in range(4)]
 w=out[3] if out[3] else 1.0
 return (out[0]/w,out[1]/w,out[2]/w)
def ident(): return [[1.0 if r==c else 0.0 for c in range(4)] for r in range(4)]
def trs(node):
 if 'matrix' in node:
  a=list(map(float,node['matrix']))
  return [[a[c*4+r] for c in range(4)] for r in range(4)]
 t=list(map(float,node.get('translation',[0,0,0]))); s=list(map(float,node.get('scale',[1,1,1]))); x,y,z,w=map(float,node.get('rotation',[0,0,0,1]))
 q=[[1-2*y*y-2*z*z,2*x*y-2*z*w,2*x*z+2*y*w,0],[2*x*y+2*z*w,1-2*x*x-2*z*z,2*y*z-2*x*w,0],[2*x*z-2*y*w,2*y*z+2*x*w,1-2*x*x-2*y*y,0],[0,0,0,1]]
 sm=[[s[0],0,0,0],[0,s[1],0,0],[0,0,s[2],0],[0,0,0,1]]; tm=ident(); tm[0][3],tm[1][3],tm[2][3]=t
 return matmul(tm,matmul(q,sm))
def parse_glb(p:Path):
 blob=p.read_bytes(); assert blob[:4]==b'glTF'; ver,total=struct.unpack_from('<II',blob,4); assert ver==2 and total==len(blob)
 off=12; doc=None; binary=b''
 while off<len(blob):
  n,t=struct.unpack_from('<II',blob,off); off+=8; chunk=blob[off:off+n]; off+=n
  if t==0x4E4F534A: doc=json.loads(chunk.rstrip(b' \t\r\n\x00').decode())
  elif t==0x004E4942: binary=chunk
 assert doc is not None and binary
 return doc,binary
def norm(v,ct):
 if ct==5120:return max(float(v)/127,-1)
 if ct==5121:return float(v)/255
 if ct==5122:return max(float(v)/32767,-1)
 if ct==5123:return float(v)/65535
 return float(v)
def accessor(doc,binary,i):
 a=doc['accessors'][i]; assert 'sparse' not in a; view=doc['bufferViews'][a['bufferView']]; ct=int(a['componentType']); fmt,cs=COMP[ct]; nc=COUNT[a['type']]; stride=int(view.get('byteStride',cs*nc)); base=int(view.get('byteOffset',0))+int(a.get('byteOffset',0)); st=struct.Struct('<'+fmt*nc); out=[]
 for j in range(int(a['count'])):
  raw=st.unpack_from(binary,base+j*stride); vals=tuple(norm(v,ct) if a.get('normalized',False) else v for v in raw); out.append(vals[0] if nc==1 else vals)
 return out
def world_mats(nodes):
 parent={}
 for i,n in enumerate(nodes):
  for ch in n.get('children',[]): parent[int(ch)]=i
 cache={}
 def w(i):
  if i in cache:return cache[i]
  local=trs(nodes[i]); cache[i]=matmul(w(parent[i]),local) if i in parent else local; return cache[i]
 return [w(i) for i in range(len(nodes))]
def matrix_rows(m): return [[float(m[r][c]) for c in range(4)] for r in range(4)]
def snapshot(root):
 ms=[o for o in ready.base.descendants(root) if o.type=='MESH' and OBJECT_FRAGMENT in o.name.lower()]
 if len(ms)!=1: raise RuntimeError(f'expected one sportsuit: {[o.name for o in ms]}')
 o=ms[0]; verts={}
 for idx in PREPARED_VERTS:
  v=o.data.vertices[idx].co.copy(); w=o.matrix_world@v
  verts[str(idx)]={'local_xyz':[float(x) for x in v],'local_yup':list(yup(v)),'world_xyz':[float(x) for x in w],'world_yup':list(yup(w))}
 return {'name':o.name,'matrix_world':matrix_rows(o.matrix_world),'matrix_local':matrix_rows(o.matrix_local),'vertices':verts}
def inspect_glb(p:Path,snap):
 doc,binary=parse_glb(p); nodes=doc.get('nodes',[]); worlds=world_mats(nodes)
 mesh_hits=[]
 for ni,n in enumerate(nodes):
  if 'mesh' in n and OBJECT_FRAGMENT in str(doc['meshes'][int(n['mesh'])].get('name','')).lower(): mesh_hits.append(ni)
 if len(mesh_hits)!=1: raise RuntimeError(f'expected one sportsuit node, got {mesh_hits}')
 ni=mesh_hits[0]; n=nodes[ni]; mesh=doc['meshes'][int(n['mesh'])]; prim=mesh['primitives'][0]; pos=accessor(doc,binary,int(prim['attributes']['POSITION']))
 records=[]
 for gi,pi in zip(GLTF_VERTS,PREPARED_VERTS):
  raw=tuple(map(float,pos[gi])); nw=apply(worlds[ni],raw); target=tuple(snap['vertices'][str(pi)]['world_yup'])
  records.append({'gltf_vertex':gi,'prepared_vertex':pi,'gltf_raw':list(raw),'gltf_node_world':list(nw),'prepared_world_yup':list(target),'raw_residual_vector':sub(raw,target),'raw_distance':dist(raw,target),'node_world_residual_vector':sub(nw,target),'node_world_distance':dist(nw,target)})
 equal_raw=dist(records[0]['raw_residual_vector'],records[1]['raw_residual_vector'])
 equal_world=dist(records[0]['node_world_residual_vector'],records[1]['node_world_residual_vector'])
 max_world=max(r['node_world_distance'] for r in records)
 if max_world<=0.0001:
  state='GLTF_NODE_TRANSFORM_RESOLVES_SERIALIZED_EDGE_MAPPING'; nxt='MEASURE_SOURCE_WEIGHT_TRANSFER_BEFORE_EXPORT'
 elif equal_raw<=1e-7:
  state='COMMON_RIGID_OFFSET_CONFIRMED_BUT_NODE_TRANSFORM_NOT_APPLIED'; nxt='TRACE_EXPORTER_MESH_BASIS_ORIGIN'
 else:
  state='GLTF_NODE_TRANSFORM_DOES_NOT_EXPLAIN_POSITION_RESIDUAL'; nxt='TRACE_EXPORTER_VERTEX_POSITION_TRANSFORMATION'
 return {'diagnostic_state':state,'next_safe_axis':nxt,'mesh_index':int(n['mesh']),'mesh_name':mesh.get('name'),'node_index':ni,'node_name':n.get('name'),'node':{k:n[k] for k in ('translation','rotation','scale','matrix') if k in n},'node_world_matrix':worlds[ni],'endpoint_records':records,'raw_residual_vector_delta':equal_raw,'node_world_residual_vector_delta':equal_world,'max_node_world_distance':max_world}
def main():
 original=ready._original_export_character; captured=None
 def instrumented(root,out):
  nonlocal captured
  if out.name!=TARGET: raise RuntimeError(f'unexpected first target {out.name}')
  snap=snapshot(root); rec=original(root,out); digest=sha256_path(out)
  if digest!=TARGET_SHA or out.stat().st_size!=TARGET_SIZE or int(rec['seed'])!=TARGET_SEED: raise RuntimeError('deterministic regeneration drift')
  trace=inspect_glb(out,snap)
  captured={'format':'grand-bruxelles-gate8-node-transform-trace-v1','diagnostic_state':trace['diagnostic_state'],'next_safe_axis':trace['next_safe_axis'],'generated_glb_sha256':digest,'generated_glb_size_bytes':out.stat().st_size,'generated_seed':int(rec['seed']),'source_head_sha':'afcb7b352ed054d98fdf83eae3333ec82c814b3e','snapshot':snap,'trace':trace,'canonical_asset_mutation':False,'canonical_generator_mutation':False,'runtime_npc_mutation':False,'production_activation_allowed':False,'visual_approval_allowed':False}
  RESULT_PATH.parent.mkdir(parents=True,exist_ok=True); RESULT_PATH.write_text(json.dumps(captured,indent=2,sort_keys=True)+'\n')
  raise StopAfterVariantOne()
 ready._original_export_character=instrumented
 try: ready.main()
 except StopAfterVariantOne: pass
 finally: ready._original_export_character=original
 if captured is None: raise RuntimeError('variant01 trace not captured')
 print('GATE8_NODE_TRANSFORM_TRACE',captured['diagnostic_state'],captured['next_safe_axis'])
if __name__=='__main__': main()
