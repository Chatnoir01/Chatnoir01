import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import test from 'node:test';

test('Grand Bruxelles shared sidewalk edge contract', () => {
  const output = execFileSync(
    'python3',
    ['grand-bruxelles-game/tools/qa/validate_sidewalk_edge_runtime.py'],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
  );
  assert.match(output, /BRUSSELS_SIDEWALK_EDGE_OK:/);
});
