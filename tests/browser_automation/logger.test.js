import test from 'node:test';
import assert from 'node:assert/strict';
import { StructuredLogger } from '../../src/core/logger.js';

test('structured logging redacts secret-shaped keys', () => {
  const entries = [];
  const logger = new StructuredLogger((entry) => entries.push(entry));
  logger.log('test', { candidateId: 'c1', password: 'p', nested: { apiKey: 'k', ok: true } });
  const serialized = JSON.stringify(entries[0]);
  assert.doesNotMatch(serialized, /\"p\"|\"k\"/);
  assert.match(serialized, /REDACTED/);
});
