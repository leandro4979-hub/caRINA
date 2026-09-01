import test from 'node:test';
import assert from 'node:assert/strict';
import { registerPlugin, clearRegistry } from '../../src/plugins/registry.js';
import { youtubePlugin } from '../../src/plugins/youtube.js';
import { candidate, context, engine } from './helpers.js';

test.beforeEach(() => { clearRegistry(); registerPlugin(youtubePlugin); });

test('DENY never executes or retries', async () => {
  const c = candidate();
  let policyCalls = 0;
  const app = engine('DENY');
  app.policyEngine = { decide: async () => { policyCalls += 1; return { state: 'DENY' }; } };
  const result = await app.evaluateCandidate({ candidate: c, rawContext: context() });
  assert.equal(result.status, 'DENIED');
  assert.equal(policyCalls, 1);
  assert.equal(c.clicks(), 0);
});

test('duplicate action protection executes candidate at most once', async () => {
  const c = candidate();
  const app = engine('ALLOW');
  const first = await app.evaluateCandidate({ candidate: c, rawContext: context() });
  const second = await app.evaluateCandidate({ candidate: c, rawContext: context() });
  assert.equal(first.status, 'VERIFIED');
  assert.equal(second.status, 'DUPLICATE');
  assert.equal(c.clicks(), 1);
});

test('bounded retry applies only after ALLOW to transient execution races', async () => {
  let attempts = 0;
  const c = candidate({ perform: async () => {
    attempts += 1;
    if (attempts === 1) { const error = new Error('detached'); error.transient = true; throw error; }
  } });
  const result = await engine('ALLOW').evaluateCandidate({ candidate: c, rawContext: context() });
  assert.equal(result.status, 'VERIFIED');
  assert.equal(attempts, 2);
});
