import test from 'node:test';
import assert from 'node:assert/strict';
import { registerPlugin, clearRegistry } from '../../src/plugins/registry.js';
import { youtubePlugin } from '../../src/plugins/youtube.js';
import { candidate, context, engine } from './helpers.js';

test.beforeEach(() => clearRegistry());

test('failed verification is reported as failure', async () => {
  const failing = { ...youtubePlugin, id: 'youtube-fail', verify: async () => false };
  registerPlugin(failing);
  const result = await engine('ALLOW').evaluateCandidate({ candidate: candidate(), rawContext: context(), plugin: failing });
  assert.equal(result.status, 'FAILED_VERIFICATION');
  assert.equal(result.verification.passed, false);
});
