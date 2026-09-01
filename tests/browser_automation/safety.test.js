import test from 'node:test';
import assert from 'node:assert/strict';
import { registerPlugin, clearRegistry } from '../../src/plugins/registry.js';
import { youtubePlugin } from '../../src/plugins/youtube.js';
import { candidate, context, engine } from './helpers.js';

test.beforeEach(() => { clearRegistry(); registerPlugin(youtubePlugin); });

test('payment page resolves to DENY even for high-confidence control', async () => {
  const c = candidate();
  const result = await engine('ALLOW').evaluateCandidate({ candidate: c, rawContext: context({ pageText: 'checkout payment card' }) });
  assert.deepEqual([result.status, result.reason, c.clicks()], ['DENIED', 'SENSITIVE_CONTEXT', 0]);
});

test('login page resolves to DENY', async () => {
  const c = candidate({ text: 'Continue' });
  const result = await engine('ALLOW').evaluateCandidate({ candidate: c, rawContext: context({ pageText: 'login password', mediaPlaying: false }) });
  assert.equal(result.reason, 'SENSITIVE_CONTEXT');
});

test('credentials and DOM references are excluded from policy proposal', async () => {
  const captured = [];
  const c = candidate({ secret: 'SHOULD_NOT_LEAK', element: { isConnected: false, token: 'NOPE' } });
  const result = await engine('ALLOW', captured).evaluateCandidate({ candidate: c, rawContext: { ...context(), apiKey: 'secret', cookies: 'secret', password: 'secret' } });
  assert.equal(result.status, 'VERIFIED');
  const serialized = JSON.stringify(captured[0]);
  assert.doesNotMatch(serialized, /secret|SHOULD_NOT_LEAK|NOPE/i);
  assert.equal('element' in captured[0], false);
});
