extends "res://base_probe.gd"

var diagnostic_sample_index := -1

func _measure_skin_edges(out:Dictionary)->void:
    diagnostic_sample_index += 1
    if not out.has("max_absolute_edge"): out["max_absolute_edge"]={}
    if not out.has("max_stretch_edge"): out["max_stretch_edge"]={}
    if not out.has("min_compression_edge"): out["min_compression_edge"]={}
    for mesh in target_meshes:
        var skin:=mesh.skin
        for s in range(mesh.mesh.get_surface_count()):
            var arrays:=mesh.mesh.surface_get_arrays(s)
            var vertices=arrays[Mesh.ARRAY_VERTEX]
            var bones=arrays[Mesh.ARRAY_BONES]
            var weights=arrays[Mesh.ARRAY_WEIGHTS]
            var indices=arrays[Mesh.ARRAY_INDEX]
            if vertices==null or bones==null or weights==null or vertices.size()<3 or bones.size()==0 or bones.size()!=weights.size() or bones.size()%vertices.size()!=0:
                continue
            var ipv:=int(bones.size()/vertices.size())
            var ids:Array[int]=[]
            if indices!=null and indices.size()>=3:
                for v in indices: ids.append(int(v))
            else:
                for v in range(vertices.size()): ids.append(v)
            for tri in range(int(ids.size()/3)):
                var tri_ids=[ids[tri*3],ids[tri*3+1],ids[tri*3+2]]
                for pair in [[tri_ids[0],tri_ids[1]],[tri_ids[1],tri_ids[2]],[tri_ids[2],tri_ids[0]]]:
                    var a:=int(pair[0])
                    var b:=int(pair[1])
                    var ra:=_skin_vertex(vertices[a],a,bones,weights,ipv,skin,true)
                    var rb:=_skin_vertex(vertices[b],b,bones,weights,ipv,skin,true)
                    var pa:=_skin_vertex(vertices[a],a,bones,weights,ipv,skin,false)
                    var pb:=_skin_vertex(vertices[b],b,bones,weights,ipv,skin,false)
                    var rest_length:=ra.distance_to(rb)
                    if rest_length<MIN_EDGE_M: continue
                    var posed_length:=pa.distance_to(pb)
                    var ratio:=posed_length/rest_length
                    var delta:=absf(posed_length-rest_length)
                    out.edge_count=int(out.edge_count)+1
                    if delta>float(out.max_absolute_edge_change_m):
                        out.max_absolute_edge_change_m=delta
                        out.max_absolute_edge=_edge_record(mesh,s,tri,a,b,rest_length,posed_length,ra,rb,pa,pb,bones,weights,ipv,skin)
                    if ratio>float(out.max_stretch_ratio):
                        out.max_stretch_ratio=ratio
                        out.max_stretch_edge=_edge_record(mesh,s,tri,a,b,rest_length,posed_length,ra,rb,pa,pb,bones,weights,ipv,skin)
                    if ratio<float(out.min_compression_ratio):
                        out.min_compression_ratio=ratio
                        out.min_compression_edge=_edge_record(mesh,s,tri,a,b,rest_length,posed_length,ra,rb,pa,pb,bones,weights,ipv,skin)

func _edge_record(mesh:MeshInstance3D,surface:int,triangle:int,a:int,b:int,rest_length:float,posed_length:float,ra:Vector3,rb:Vector3,pa:Vector3,pb:Vector3,bones,weights,ipv:int,skin:Skin)->Dictionary:
    return {
        "sample_index":diagnostic_sample_index,
        "mesh":mesh.name,
        "surface":surface,
        "triangle":triangle,
        "vertex_a":a,
        "vertex_b":b,
        "rest_length_m":rest_length,
        "posed_length_m":posed_length,
        "absolute_change_m":absf(posed_length-rest_length),
        "stretch_ratio":posed_length/rest_length,
        "endpoint_a_displacement_m":ra.distance_to(pa),
        "endpoint_b_displacement_m":rb.distance_to(pb),
        "vertex_a_influences":_vertex_influences(a,bones,weights,ipv,skin),
        "vertex_b_influences":_vertex_influences(b,bones,weights,ipv,skin)
    }

func _vertex_influences(vertex_index:int,bones,weights,ipv:int,skin:Skin)->Array:
    var result:Array=[]
    for j in range(ipv):
        var slot:=vertex_index*ipv+j
        var weight:=float(weights[slot])
        if weight<=0.0: continue
        var bind_index:=int(bones[slot])
        if bind_index<0 or bind_index>=skin.get_bind_count(): continue
        var bone_index:=skin.get_bind_bone(bind_index)
        var bind_name:=String(skin.get_bind_name(bind_index))
        if bone_index<0 and not bind_name.is_empty():
            bone_index=target_skeleton.find_bone(bind_name)
        var bone_name:=bind_name
        if bone_index>=0:
            bone_name=target_skeleton.get_bone_name(bone_index)
        result.append({"bind_index":bind_index,"bone_index":bone_index,"bone_name":bone_name,"weight":weight})
    result.sort_custom(func(x,y): return float(x.weight)>float(y.weight))
    return result
