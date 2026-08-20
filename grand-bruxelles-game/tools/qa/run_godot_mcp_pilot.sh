#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PROJECT_ROOT="$REPO_ROOT/grand-bruxelles-game"
CONTRACT="$PROJECT_ROOT/data/qa/godot_mcp_pilot_contract.json"
WORK_ROOT="${RUNNER_TEMP:-/tmp}/grand-bruxelles-godot-mcp-pilot"
UPSTREAM="$WORK_ROOT/upstream"
PILOT_PROJECT="$WORK_ROOT/project"
BIN_DIR="$WORK_ROOT/bin"
EVIDENCE="$WORK_ROOT/evidence"

rm -rf "$WORK_ROOT"
mkdir -p "$BIN_DIR" "$EVIDENCE"

read_contract() {
  python3 - "$CONTRACT" "$1" <<'PY'
import json
import sys
from pathlib import Path
obj = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
value = obj
for part in sys.argv[2].split('.'):
    value = value[part]
print(value)
PY
}

MCP_REPO="$(read_contract upstream.repository)"
MCP_TAG="$(read_contract upstream.tag)"
MCP_COMMIT="$(read_contract upstream.commit)"
MCP_ADDON_SOURCE="$(read_contract upstream.addon_source_path)"
GODOT_VERSION="$(read_contract engine.version)"
MAIN_SCENE="$(read_contract engine.main_scene)"

if [[ "$GODOT_VERSION" != "4.7.1-stable" ]]; then
  echo "GODOT_MCP_PILOT_FAIL unexpected engine version: $GODOT_VERSION" >&2
  exit 2
fi

GODOT_ZIP="Godot_v4.7.1-stable_linux.x86_64.zip"
GODOT_BIN="$BIN_DIR/Godot_v4.7.1-stable_linux.x86_64"
MCP_BIN="$BIN_DIR/godot-mcp"
EDITOR_LOG="$EVIDENCE/editor.log"
MCP_LOG="$EVIDENCE/mcp.log"

python3 "$PROJECT_ROOT/tools/qa/godot_mcp_export_guard.py" | tee "$EVIDENCE/export-guard-before.log"

echo "GODOT_MCP_PILOT_PHASE source_pin"
git clone --depth 1 --branch "$MCP_TAG" "$MCP_REPO" "$UPSTREAM"
actual_commit="$(git -C "$UPSTREAM" rev-parse HEAD)"
if [[ "$actual_commit" != "$MCP_COMMIT" ]]; then
  echo "GODOT_MCP_PILOT_FAIL upstream commit $actual_commit != $MCP_COMMIT" >&2
  exit 3
fi
grep -q "MIT License" "$UPSTREAM/LICENSE"
printf '%s\n' "$actual_commit" > "$EVIDENCE/upstream-commit.txt"
cp "$UPSTREAM/LICENSE" "$EVIDENCE/upstream-LICENSE.txt"

echo "GODOT_MCP_PILOT_PHASE build_cli"
go version | tee "$EVIDENCE/go-version.txt"
if ! go version | grep -Eq 'go1\.26([. ]|$)'; then
  echo "GODOT_MCP_PILOT_FAIL Go 1.26.x is required to build pinned MCP CLI" >&2
  exit 4
fi
(
  cd "$UPSTREAM"
  go build -o "$MCP_BIN" ./cmd/godot-mcp
)
"$MCP_BIN" --help > "$EVIDENCE/cli-help.txt"

echo "GODOT_MCP_PILOT_PHASE godot_4_7_1"
curl -fL --retry 3 --retry-delay 3 \
  "https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/$GODOT_ZIP" \
  -o "$WORK_ROOT/$GODOT_ZIP"
unzip -q "$WORK_ROOT/$GODOT_ZIP" -d "$BIN_DIR"
chmod +x "$GODOT_BIN"
"$GODOT_BIN" --version | tee "$EVIDENCE/godot-version.txt"
grep -q '^4\.7\.1\.stable' "$EVIDENCE/godot-version.txt"

echo "GODOT_MCP_PILOT_PHASE isolated_install"
cp -a "$PROJECT_ROOT" "$PILOT_PROJECT"
"$MCP_BIN" install \
  --project "$PILOT_PROJECT" \
  --from "$UPSTREAM/$MCP_ADDON_SOURCE" \
  --skill=false \
  --enable | tee "$EVIDENCE/install.log"
test -f "$PILOT_PROJECT/addons/godot_mcp/plugin.cfg"
grep -q 'MCPGameInspector' "$PILOT_PROJECT/project.godot"
grep -q 'MCPGameInput' "$PILOT_PROJECT/project.godot"
test ! -d "$PROJECT_ROOT/addons/godot_mcp"
! grep -q 'MCPGameInspector\|MCPGameInput\|addons/godot_mcp' "$PROJECT_ROOT/project.godot"

echo "GODOT_MCP_PILOT_PHASE live_editor"
EDITOR_PID=""
cleanup() {
  if [[ -n "$EDITOR_PID" ]]; then
    kill "$EDITOR_PID" 2>/dev/null || true
    wait "$EDITOR_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

"$GODOT_BIN" --headless --editor --path "$PILOT_PROJECT" --audio-driver Dummy >"$EDITOR_LOG" 2>&1 &
EDITOR_PID=$!

for _ in $(seq 1 180); do
  if [[ -f "$PILOT_PROJECT/.godot/godot-mcp.json" ]]; then
    break
  fi
  if ! kill -0 "$EDITOR_PID" 2>/dev/null; then
    cat "$EDITOR_LOG"
    echo "GODOT_MCP_PILOT_FAIL editor exited before MCP discovery" >&2
    exit 5
  fi
  sleep 1
done
if [[ ! -f "$PILOT_PROJECT/.godot/godot-mcp.json" ]]; then
  cat "$EDITOR_LOG"
  echo "GODOT_MCP_PILOT_FAIL MCP discovery file never appeared" >&2
  exit 6
fi
cp "$PILOT_PROJECT/.godot/godot-mcp.json" "$EVIDENCE/discovery.json"

(
  cd "$PILOT_PROJECT"
  timeout 45 "$MCP_BIN" doctor | tee "$EVIDENCE/doctor.log"
  timeout 45 "$MCP_BIN" project info | tee "$EVIDENCE/project-info.log"
  timeout 45 "$MCP_BIN" scene open --path "$MAIN_SCENE" | tee "$EVIDENCE/scene-open.log"
  timeout 45 "$MCP_BIN" scene tree | tee "$EVIDENCE/scene-tree.log"
) | tee "$MCP_LOG"

grep -q "$MAIN_SCENE" "$EVIDENCE/scene-open.log"
grep -q "$MAIN_SCENE" "$EVIDENCE/scene-tree.log"
grep -q '\[MCP\] Server listening on ws://127\.0\.0\.1:' "$EDITOR_LOG"

cleanup
EDITOR_PID=""
trap - EXIT

echo "GODOT_MCP_PILOT_PHASE canonical_clean"
python3 "$PROJECT_ROOT/tools/qa/godot_mcp_export_guard.py" | tee "$EVIDENCE/export-guard-after.log"
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain -- grand-bruxelles-game)" ]]; then
  git -C "$REPO_ROOT" status --porcelain -- grand-bruxelles-game >&2
  echo "GODOT_MCP_PILOT_FAIL canonical project tree changed" >&2
  exit 7
fi

cat > "$EVIDENCE/result.txt" <<EOF
GODOT_MCP_REAL_SCENE_INSPECTION_GREEN
main_scene=$MAIN_SCENE
mcp_tag=$MCP_TAG
mcp_commit=$MCP_COMMIT
godot_version=$GODOT_VERSION
canonical_addon_installed=false
runtime_authorized=false
export_authorized=false
EOF
cat "$EVIDENCE/result.txt"
