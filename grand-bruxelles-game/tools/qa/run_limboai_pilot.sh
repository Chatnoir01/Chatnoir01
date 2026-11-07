#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PROJECT_ROOT="$REPO_ROOT/grand-bruxelles-game"
CONTRACT="$PROJECT_ROOT/data/qa/limboai_pilot_contract.json"
WORK_ROOT="${RUNNER_TEMP:-/tmp}/grand-bruxelles-limboai-pilot"
UPSTREAM="$WORK_ROOT/upstream"
PACKAGE="$WORK_ROOT/limboai.zip"
EXTRACT="$WORK_ROOT/extract"
PILOT="$WORK_ROOT/project"
EVIDENCE="$WORK_ROOT/evidence"
WEB_OUT="$WORK_ROOT/web"

rm -rf "$WORK_ROOT"
mkdir -p "$EXTRACT" "$PILOT/addons" "$EVIDENCE" "$WEB_OUT"

read_contract() {
  python3 - "$CONTRACT" "$1" <<'PY'
import json, sys
from pathlib import Path
v=json.loads(Path(sys.argv[1]).read_text())
for p in sys.argv[2].split('.'): v=v[p]
print(v)
PY
}
TAG="$(read_contract upstream.tag)"
EXPECTED_PREFIX="$(read_contract upstream.expected_commit_prefix)"
ASSET="$(read_contract upstream.release_asset)"
EXPECTED_SHA="$(read_contract upstream.release_asset_sha256)"

if [[ -d "$PROJECT_ROOT/addons/limboai" ]] || grep -qi 'limboai' "$PROJECT_ROOT/project.godot"; then
  echo "LIMBOAI_PILOT_FAIL canonical project already contains LimboAI" >&2
  exit 2
fi

printf 'LIMBOAI_PILOT_PHASE source_pin\n'
git clone -q --depth 1 --branch "$TAG" https://github.com/limbonaut/limboai.git "$UPSTREAM"
actual_commit="$(git -C "$UPSTREAM" rev-parse HEAD)"
[[ "$actual_commit" == "$EXPECTED_PREFIX"* ]]
grep -qi 'MIT' "$UPSTREAM/LICENSE"
printf '%s\n' "$actual_commit" > "$EVIDENCE/upstream-commit.txt"

printf 'LIMBOAI_PILOT_PHASE release_hash\n'
curl -fsSL --retry 3 "https://github.com/limbonaut/limboai/releases/download/$TAG/${ASSET/+/%2B}" -o "$PACKAGE"
actual_sha="$(sha256sum "$PACKAGE" | awk '{print $1}')"
printf '%s  %s\n' "$actual_sha" "$ASSET" | tee "$EVIDENCE/release-sha256.txt"
[[ "$actual_sha" == "$EXPECTED_SHA" ]]
unzip -q "$PACKAGE" -d "$EXTRACT"
unzip -l "$PACKAGE" > "$EVIDENCE/package-files.txt"

gdext="$(find "$EXTRACT" -type f -name 'limboai.gdextension' | head -n1)"
[[ -n "$gdext" ]]
addon_dir="$(dirname "$gdext")"
# gdextension normally lives at addons/limboai/limboai.gdextension.
cp -a "$addon_dir" "$PILOT/addons/limboai"
cp "$gdext" "$EVIDENCE/limboai.gdextension.txt"
wasm_count="$(find "$PILOT/addons/limboai" -type f \( -name '*.wasm' -o -name '*web*' \) | wc -l | tr -d ' ')"
printf 'wasm_or_web_file_count=%s\n' "$wasm_count" | tee "$EVIDENCE/web-binary-count.txt"

printf 'LIMBOAI_PILOT_PHASE canonical_web_policy\n'
python3 - "$PROJECT_ROOT/export_presets.cfg" "$EVIDENCE/canonical-web-policy.txt" <<'PY'
import re, sys
from pathlib import Path
text=Path(sys.argv[1]).read_text()
web=text.split('[preset.0.options]',1)[1].split('[preset.1]',1)[0]
m=re.search(r'variant/extensions_support=(true|false)', web)
if not m: raise SystemExit('LIMBOAI_PILOT_FAIL canonical Web extensions_support missing')
value=m.group(1)
Path(sys.argv[2]).write_text('canonical_web_extensions_support='+value+'\n')
print('LIMBOAI_CANONICAL_WEB_POLICY extensions_support='+value)
PY

cat > "$PILOT/project.godot" <<'EOF'
[application]
config/name="Grand Bruxelles LimboAI Probe"
run/main_scene="res://main.tscn"
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
EOF
cat > "$PILOT/main.tscn" <<'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource path="res://smoke.gd" type="Script" id="1"]

[node name="Main" type="Node"]
script = ExtResource("1")
EOF
cat > "$PILOT/smoke.gd" <<'GDSCRIPT'
extends Node
func _ready() -> void:
    for required in ["BehaviorTree", "BTPlayer", "LimboHSM", "LimboState", "Blackboard"]:
        if not ClassDB.class_exists(required):
            push_error("LIMBOAI_PILOT_FAIL missing class " + required)
            get_tree().quit(20)
            return
    var tree = ClassDB.instantiate("BehaviorTree")
    var player = ClassDB.instantiate("BTPlayer")
    if tree == null or player == null:
        push_error("LIMBOAI_PILOT_FAIL construction failed")
        get_tree().quit(21)
        return
    print("LIMBOAI_PC_API_GREEN")
    print("behavior_tree_constructed=true")
    print("btplayer_constructed=true")
    get_tree().quit(0)
GDSCRIPT

printf 'LIMBOAI_PILOT_PHASE pc_load\n'
godot --version | tee "$EVIDENCE/godot-version.txt"
godot --headless --editor --path "$PILOT" --quit-after 3 > "$EVIDENCE/editor-import.log" 2>&1
if grep -E 'GDExtension.*failed|Cannot open.*limboai|Failed to load extension|SCRIPT ERROR|Parse Error' "$EVIDENCE/editor-import.log"; then
  cat "$EVIDENCE/editor-import.log"
  exit 5
fi
godot --headless --path "$PILOT" 2>&1 | tee "$EVIDENCE/pc-smoke.log"
grep -q 'LIMBOAI_PC_API_GREEN' "$EVIDENCE/pc-smoke.log"

printf 'LIMBOAI_PILOT_PHASE web_feasibility\n'
cat > "$PILOT/export_presets.cfg" <<'EOF'
[preset.0]
name="Web"
platform="Web"
runnable=false
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="build/index.html"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]
custom_template/debug=""
custom_template/release=""
variant/extensions_support=true
variant/thread_support=false
vram_texture_compression/for_desktop=false
vram_texture_compression/for_mobile=false
html/export_icon=false
html/custom_html_shell=""
html/head_include=""
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
html/experimental_virtual_keyboard=false
progressive_web_app/enabled=false
progressive_web_app/ensure_cross_origin_isolation_headers=false
progressive_web_app/offline_page=""
threads/emscripten_pool_size=8
threads/godot_pool_size=4
EOF
if [[ "$wasm_count" -lt 1 ]]; then
  echo "LIMBOAI_WEB_BINARY_MISSING" | tee "$EVIDENCE/web-export.log"
  exit 6
fi
set +e
godot --headless --path "$PILOT" --export-release Web "$WEB_OUT/index.html" > "$EVIDENCE/web-export.log" 2>&1
web_rc=$?
set -e
cat "$EVIDENCE/web-export.log"
if [[ "$web_rc" -ne 0 ]] || [[ ! -s "$WEB_OUT/index.html" ]] || [[ ! -s "$WEB_OUT/index.wasm" ]] || [[ ! -s "$WEB_OUT/index.pck" ]]; then
  echo "LIMBOAI_WEB_EXPORT_FAIL rc=$web_rc" >&2
  exit 7
fi
echo "LIMBOAI_WEB_EXPORT_GREEN" | tee -a "$EVIDENCE/web-export.log"

printf 'LIMBOAI_PILOT_PHASE canonical_clean\n'
test ! -d "$PROJECT_ROOT/addons/limboai"
! grep -qi 'limboai' "$PROJECT_ROOT/project.godot"

cat > "$EVIDENCE/result.txt" <<EOF
LIMBOAI_ISOLATED_PILOT_GREEN
base_main=$(read_contract base_main_sha)
tag=$TAG
upstream_commit=$actual_commit
release_sha256=$actual_sha
godot_version=$(godot --version | head -n1)
pc_api_green=true
web_binary_present=true
web_export_with_extensions_support_green=true
canonical_web_extensions_support=false
canonical_addon_installed=false
runtime_authorized=false
pc_export_authorized=false
web_export_authorized=false
replace_existing_npc_runtime_authorized=false
verdict=technically_viable_but_requires_separate_web_policy_decision
EOF
cat "$EVIDENCE/result.txt"
