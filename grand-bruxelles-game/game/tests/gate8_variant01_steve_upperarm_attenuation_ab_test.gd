extends "res://culprit.gd"

const FACTORS := [1.0, 0.75, 0.5, 0.25]
const SAMPLES := [2, 8]
const EDGE_SPECS := [
    {"id":"max_absolute","sample":8,"mesh":"Human_female_sportsuit01_gate8_export","surface":0,"a":416,"b":758},
    {"id":"max_stretch","sample":8,"mesh":"Human_female_sportsuit01_gate8_export","surface":0,"a":257,"b":756},
    {"id":"min_compression","sample":2,"mesh":"Human_gate8_export","surface":0,"a":3827,"b":1902}
]

func _measure_skin_edges(out:Dictionary)->void:
    var sample_index := diagnostic_sample_index + 1
    if sample_index in SAMPLES:
        if not out.has("upperarm_attenuation_ab"):
            out["upperarm_attenuation_ab"] = []
        var idx := target_skeleton.find_bone("upperarm_r")
        if idx >= 0:
            var original := target_skeleton.get_bone_pose_rotation(idx).normalized()
            var rest_q := target_skeleton.get_bone_rest(idx).basis.orthonormalized().get_rotation_quaternion().normalized()
            for factor in FACTORS:
                var q := rest_q.slerp(original, float(factor)).normalized()
                target_skeleton.set_bone_pose_rotation(idx, q)
                target_skeleton.force_update_all_bone_transforms()
                var rec := {"sample_index":sample_index,"factor":factor,"upperarm_delta_deg":rad_to_deg(rest_q.angle_to(q)),"edges":[]}
                for spec in EDGE_SPECS:
                    if int(spec.sample) == sample_index:
                        rec.edges.append(_measure_exact_edge(spec))
                out.upperarm_attenuation_ab.append(rec)
            target_skeleton.set_bone_pose_rotation(idx, original)
            target_skeleton.force_update_all_bone_transforms()
    super._measure_skin_edges(out)

func _measure_exact_edge(spec:Dictionary)->Dictionary:
    for mesh in target_meshes:
        if String(mesh.name) != String(spec.mesh):
            continue
        var s := int(spec.surface)
        var arrays := mesh.mesh.surface_get_arrays(s)
        var vertices = arrays[Mesh.ARRAY_VERTEX]
        var bones = arrays[Mesh.ARRAY_BONES]
        var weights = arrays[Mesh.ARRAY_WEIGHTS]
        var ipv := int(bones.size()/vertices.size())
        var skin := mesh.skin
        var a := int(spec.a)
        var b := int(spec.b)
        var ra := _skin_vertex(vertices[a],a,bones,weights,ipv,skin,true)
        var rb := _skin_vertex(vertices[b],b,bones,weights,ipv,skin,true)
        var pa := _skin_vertex(vertices[a],a,bones,weights,ipv,skin,false)
        var pb := _skin_vertex(vertices[b],b,bones,weights,ipv,skin,false)
        var rest_len := ra.distance_to(rb)
        var posed_len := pa.distance_to(pb)
        return {"id":spec.id,"mesh":mesh.name,"vertex_a":a,"vertex_b":b,"rest_length_m":rest_len,"posed_length_m":posed_len,"absolute_change_m":absf(posed_len-rest_len),"ratio":posed_len/rest_len}
    return {"id":spec.id,"error":"mesh_missing"}
