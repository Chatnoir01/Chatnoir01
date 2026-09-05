#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, math, struct
from pathlib import Path

EXPECTED_ASSET = "vitruvian_head.glb"
EXPECTED_UPSTREAM = "ibrews/VitruvianGodot@bdecdcd537b4031fdd0fb299b7e4f93f084fffa0"
EXPECTED_SHA256 = "54efb42e9f3dd7e7cf3c3e86ed5298f3ba26e341d5743245cbe2621c547c5f1f"


def parse_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"glTF": raise ValueError("not a GLB")
    version, total = struct.unpack_from("<II", data, 4)
    if version != 2 or total != len(data): raise ValueError("invalid GLB header")
    off = 12; doc = None
    while off + 8 <= len(data):
        size, kind = struct.unpack_from("<II", data, off); off += 8
        if off + size > len(data): raise ValueError("invalid GLB chunk")
        chunk = data[off:off+size]; off += size
        if kind == 0x4E4F534A:
            if doc is not None: raise ValueError("duplicate JSON chunk")
            doc = json.loads(chunk.rstrip(b" \t\r\n\x00").decode("utf-8"))
    if doc is None or off != len(data): raise ValueError("missing JSON chunk or trailing bytes")
    return doc, data


def finite_accessor_bounds(doc: dict) -> bool:
    for a in doc.get("accessors", []):
        for key in ("min", "max"):
            if key in a and not all(math.isfinite(float(x)) for x in a[key]): return False
    return True


def inspect(path: Path, expected_sha256: str = EXPECTED_SHA256) -> dict:
    doc, data = parse_glb(path)
    meshes = doc.get("meshes", []); nodes = doc.get("nodes", []); skins = doc.get("skins", []); mats = doc.get("materials", [])
    primitives = [p for mesh in meshes for p in mesh.get("primitives", [])]
    material_bound = sum(1 for p in primitives if isinstance(p.get("material"), int) and 0 <= p["material"] < len(mats))
    morph_primitives = sum(1 for p in primitives if isinstance(p.get("targets"), list) and len(p["targets"]) > 0)
    target_names = sorted({str(n) for mesh in meshes for n in mesh.get("extras", {}).get("targetNames", []) if str(n)})
    digest = hashlib.sha256(data).hexdigest()
    report = {
        "schema": "grand-bruxelles-civ1-head-intake-v2",
        "asset": EXPECTED_ASSET, "upstream": EXPECTED_UPSTREAM,
        "sha256": digest, "sha256_pinned": digest == expected_sha256, "bytes": len(data),
        "scene_count": len(doc.get("scenes", [])), "node_count": len(nodes),
        "mesh_count": len(meshes), "primitive_count": len(primitives),
        "material_count": len(mats), "material_bound_primitive_count": material_bound,
        "morph_target_primitive_count": morph_primitives, "morph_target_names": target_names,
        "skin_count": len(skins), "animations": len(doc.get("animations", [])),
        "attachment_mode": "rigid_to_body_head_bone", "attachment_bone": "mixamorig_Head",
        "source_wiring_required": True, "finite_accessor_bounds": finite_accessor_bounds(doc),
        "diagnostic_only": True, "runtime_authorized": False, "visual_approval_claimed": False,
    }
    required = (
        report["sha256_pinned"] and report["scene_count"] >= 1 and report["mesh_count"] >= 1
        and report["primitive_count"] >= 1 and report["material_count"] >= 1
        and report["material_bound_primitive_count"] == report["primitive_count"]
        and report["morph_target_primitive_count"] >= 1 and report["finite_accessor_bounds"]
        and report["skin_count"] == 0 and report["animations"] == 0
    )
    report["intake_pass"] = bool(required)
    report["verdict"] = "AMELIORER_RIGID_HEAD_INTAKE" if required else "JETER_HEAD_INTAKE"
    return report


def main() -> None:
    ap=argparse.ArgumentParser(); ap.add_argument("glb"); ap.add_argument("output"); a=ap.parse_args()
    r=inspect(Path(a.glb)); Path(a.output).write_text(json.dumps(r,indent=2,sort_keys=True)+"\n")
    if not r["intake_pass"]: raise SystemExit("CIV1_HEAD_INTAKE_REJECTED")
    print(f"CIV1_HEAD_INTAKE_OK sha256={r['sha256']} bytes={r['bytes']} meshes={r['mesh_count']} morph_primitives={r['morph_target_primitive_count']} mode={r['attachment_mode']}")

if __name__ == "__main__": main()
