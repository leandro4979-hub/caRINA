import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const schemaPath = path.resolve(here, '../../schemas/phase2-execution-contracts.v1.json');
const schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));

const authorization = schema.$defs.executionAuthorization;
const executionResult = schema.$defs.executionResult;
const verificationResult = schema.$defs.verificationResult;

function required(definition, field) {
  return definition.required.includes(field);
}

function property(definition, field) {
  return definition.properties[field];
}

test('Phase 2 schema is Draft 2020-12 and defines all three contracts', () => {
  assert.equal(schema.$schema, 'https://json-schema.org/draft/2020-12/schema');
  assert.ok(authorization);
  assert.ok(executionResult);
  assert.ok(verificationResult);
});

test('execution authorization is bound to identity, context, lifetime, and authority', () => {
  for (const field of [
    'authorizationId', 'requestId', 'nonce', 'candidateId', 'pluginId',
    'intent', 'action', 'tabId', 'frameId', 'origin', 'issuedAt',
    'expiresAt', 'executionFingerprint', 'authorityBinding',
  ]) assert.equal(required(authorization, field), true, field);

  assert.equal(property(authorization, 'executionFingerprint').$ref, '#/$defs/sha256');
  assert.equal(property(authorization, 'authorityBinding').$ref, '#/$defs/sha256');
});

test('execution result is context-bound and cannot claim semantic success', () => {
  for (const field of [
    'authorizationId', 'requestId', 'candidateId', 'action',
    'tabId', 'frameId', 'origin', 'executionState', 'startedAt', 'completedAt',
  ]) assert.equal(required(executionResult, field), true, field);

  assert.equal(property(executionResult, 'executionState').type, 'string');
  assert.deepEqual(property(executionResult, 'executionState').enum, [
    'ATTEMPTED', 'DISPATCHED', 'FAILED',
  ]);
  assert.equal('success' in executionResult.properties, false);
  assert.equal('policyApproved' in executionResult.properties, false);
  assert.equal('actionCompleted' in executionResult.properties, false);
});

test('verification result is context-bound and evidence is allowlisted', () => {
  for (const field of [
    'authorizationId', 'requestId', 'candidateId',
    'tabId', 'frameId', 'origin', 'observedAt', 'evidence',
  ]) assert.equal(required(verificationResult, field), true, field);

  assert.equal('success' in verificationResult.properties, false);
  assert.equal('verdict' in verificationResult.properties, false);

  const codes = schema.$defs.verificationEvidence.properties.code.enum;
  assert.deepEqual(codes, [
    'VISIBLE', 'ENABLED', 'INTERACTIVE_ROLE', 'SUPPORTED_CONTROL_TEXT',
    'MEDIA_PLAYING', 'OVERLAY_VISIBLE', 'PLUGIN_SITE_SIGNAL',
  ]);
});

test('all Phase 2 contract objects reject undeclared properties', () => {
  for (const definition of [authorization, executionResult, verificationResult, schema.$defs.verificationEvidence]) {
    assert.equal(definition.additionalProperties, false);
  }
});

test('Phase 2 schema does not enable Phase 1 execution', () => {
  assert.match(
    fs.readFileSync(path.resolve(here, '../../docs/phase2-execution-contracts.md'), 'utf8'),
    /does not enable browser execution/i,
  );
});
