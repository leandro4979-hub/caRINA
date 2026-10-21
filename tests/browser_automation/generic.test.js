import test from 'node:test';
import assert from 'node:assert/strict';
import { registerPlugin, clearRegistry } from '../../src/plugins/registry.js';
import { genericPlugin } from '../../src/plugins/generic.js';
import { candidate, engine } from './helpers.js';

test.beforeEach(() => { clearRegistry(); registerPlugin(genericPlugin); });

test('generic text matching alone is not enough', async () => {
  const c = candidate({ text: 'Close', role: null, visible: true, enabled: true });
  const result = await engine('ALLOW').evaluateCandidate({ candidate: c, rawContext: { url: 'https://example.com', pageText: 'article', overlayVisible: false }, plugin: genericPlugin });
  assert.equal(result.status, 'DENIED');
});

test('stale candidates are denied', async () => {
  const c = candidate({ observedAt: Date.now() - 10_000 });
  const result = await engine('ALLOW').evaluateCandidate({ candidate: c, rawContext: { url: 'https://example.com', pageText: 'overlay', overlayVisible: true }, plugin: genericPlugin });
  assert.equal(result.reason, 'STALE_CANDIDATE');
});
