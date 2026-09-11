import test from 'node:test';
import assert from 'node:assert/strict';
import { registerPlugin, clearRegistry } from '../../src/plugins/registry.js';
import { youtubePlugin } from '../../src/plugins/youtube.js';
import { candidate, context, engine } from './helpers.js';

test.beforeEach(() => { clearRegistry(); registerPlugin(youtubePlugin); });

test('YouTube skip resolves to ALLOW and verifies state change', async () => {
  const c = candidate();
  const result = await engine('ALLOW').evaluateCandidate({ candidate: c, rawContext: context() });
  assert.equal(result.status, 'VERIFIED');
  assert.equal(c.clicks(), 1);
});

test('low-confidence candidate is denied before policy execution', async () => {
  const c = candidate({ visible: false, enabled: false, role: null });
  const captured = [];
  const result = await engine('ALLOW', captured).evaluateCandidate({ candidate: c, rawContext: context({ mediaPlaying: false }) });
  assert.equal(result.reason, 'LOW_CONFIDENCE');
  assert.equal(captured.length, 0);
  assert.equal(c.clicks(), 0);
});

test('unknown policy state fails closed', async () => {
  const c = candidate();
  const result = await engine('MAYBE').evaluateCandidate({ candidate: c, rawContext: context() });
  assert.deepEqual([result.status, result.reason, c.clicks()], ['DENIED', 'UNKNOWN_POLICY_STATE', 0]);
});

test('APPROVAL_REQUIRED never enters execution queue', async () => {
  const c = candidate();
  const result = await engine('APPROVAL_REQUIRED').evaluateCandidate({ candidate: c, rawContext: context() });
  assert.equal(result.status, 'APPROVAL_REQUIRED');
  assert.equal(c.clicks(), 0);
});
