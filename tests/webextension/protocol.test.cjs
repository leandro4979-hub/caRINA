const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function schema(name) {
  return JSON.parse(fs.readFileSync(path.resolve(__dirname, `../../extension/protocol/${name}`), 'utf8'));
}

test('content-originated action schema excludes authoritative browser identity', () => {
  const action = schema('action-proposal.schema.json');
  assert.equal(action.additionalProperties, false);
  for (const forbidden of ['tabId', 'frameId', 'host', 'origin', 'url', 'authorizationToken']) {
    assert.equal(Object.hasOwn(action.properties, forbidden), false);
  }
});

test('context sensitive signals use a closed vocabulary', () => {
  const context = schema('context-update.schema.json');
  assert.ok(Array.isArray(context.properties.sensitiveSignals.items.enum));
  assert.equal(context.properties.sensitiveSignals.uniqueItems, true);
});

test('policy result is a decision, not an execution capability', () => {
  const result = schema('policy-result.schema.json');
  assert.equal(Object.hasOwn(result.properties, 'authorizationToken'), false);
  assert.equal(Object.hasOwn(result.properties, 'expiresAt'), false);
});

test('execution authorization is a separate protocol type', () => {
  const auth = schema('execution-authorization.schema.json');
  assert.equal(auth.properties.type.const, 'EXECUTION_AUTHORIZATION');
  assert.ok(auth.required.includes('authorizationToken'));
  assert.ok(auth.required.includes('expiresAt'));
});
