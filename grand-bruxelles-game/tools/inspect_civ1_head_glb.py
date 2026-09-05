#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, math, struct
from pathlib import Path

EXPECTED_ASSET = "vitruvian_head.glb"
EXPECTED_UPSTREAM = "ibrews/VitruvianGodot@bdecdcd537b4031fdd0fb299b7e4f93f084fffa0"


def parse_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"glTF":
        raise ValueError("not a GLB")
    version, total = struct.unpack_from("<II", data, 4)
    if version != 2 or total != len(data):
        raise ValueError("invalid GLB header")
    off = 12
    doc = None
    while off + 8 <= len(data):
        size, kind = struct.unpack_from("<II", data, off); off += 8
        if size < 0 or off + size > len(data):
            raise ValueError("invalid GLB chunk")
        chunk = data[off:off+size]; off += size
        if kind == 0x4E4F534A:
            if doc is not None:
                raise ValueError("duplicate JSON chunk")
            doc = json.loads(chunk.rstrip(b" \t\r\n\x00").decode("utf-8"))
    if doc is None or off != len(data):
        raise ValueError("missing JSON chunk or trailing bytes")
    return doc, data


def finite_accessor_bounds(doc: dict) -> bool:
    for a in doc.get("accessors", []):
        for key in ("min", "max"):
            if key in a and not all(math.isfinite(float(x)) for x in a[key]):
                return False
    return True


def inspect(path: Path) -> dict:
    doc, data = parse_glb(path)
    meshes = doc.get("meshes", []); nodes = doc.get("nodes", []); skins = doc.get("skins", []); mats = doc.get("materials", [])
    primitives = [p for m in meshes for p in m.get("primitives", [])]
    material_bound = sum(1 for p in primitives if isinstance(p.get("material"), int) and 0 <= p["material"] < len(mats))
    skinned_nodes = [n for n in nodes if isinstance(n.get("skin"), int)]
    joint_indices = [j for s in skins for j in s.get("joints", [])]
    joint_names = sorted({str(nodes[j].get("name", "")) for j in joint_indices if isinstance(j, int) and 0 <= j < len(nodes) and nodes[j].get("name")})
    lower_names = {x.lower() for x in joint_names}
    head_anchor = any(any(k in n for k in ("head", "neck")) for n in lower_names)
    report = {
        "schema": "grand-bruxelles-civ1-head-intake-v1",
        "asset": EXPECTED_ASSET,
        "upstream": EXPECTED_UPSTREAM,
        "sha256": hashlib.sha256(data).hexdigest(),
        "bytes": len(data),
        "scene_count": len(doc.get("scenes", [])),
        "node_count": len(nodes),
        "mesh_count": len(meshes),
        "primitive_count": len(primitives),
        "material_count": len(mats),
        "material_bound_primitive_count": material_bound,
        "skin_count": len(skins),
        "skinned_node_count": len(skinned_nodes),
        "joint_count": len(joint_indices),
        "joint_names": joint_names,
        "head_or_neck_joint_present": head_anchor,
        "animations": len(doc.get("animations", [])),
        "finite_accessor_bounds": finite_accessor_bounds(doc),
        "diagnostic_only": True,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
    }
    required = (
        report["scene_count"] >= 1 and report["mesh_count"] >= 1 and report["primitive_count"] >= 1
        and report["material_count"] >= 1 and report["material_bound_primitive_count"] >= 1
        and report["skin_count"] >= 1 and report["skinned_node_count"] >= 1 and report["joint_count"] >= 1
        and report["head_or_neck_joint_present"] and report["finite_accessor_bounds"]
    )
    report["intake_pass"] = bool(required)
    report["verdict"] = "AMELIORER_HEAD_INTAKE" if required else "JETER_HEAD_INTAKE"
    return report


def main() -> None:
    ap = argparse.ArgumentParser(); ap.add_argument("glb"); ap.add_argument("output")
    a = ap.parse_args(); r = inspect(Path(a.glb)); Path(a.output).write_text(json.dumps(r, indent=2, sort_keys=True)+"\n")
    if not r["intake_pass"]:
        raise SystemExit("CIV1_HEAD_INTAKE_REJECTED")
    print(f"CIV1_HEAD_INTAKE_OK sha256={r['sha256']} bytes={r['bytes']} meshes={r['mesh_count']} skins={r['skin_count']} joints={r['joint_count']}")

if __name__ == "__main__":
    main()
