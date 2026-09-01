const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const listeners = [];
let nativeHandler = async () => { throw new Error('native handler not configured'); };

global.crypto = require('node:crypto').webcrypto;
global.chrome = undefined;
global.browser = {
  runtime: {
    onMessage: { addListener(fn) { listeners.push(fn); } },
    sendNativeMessage: (...args) => nativeHandler(...args),
  },
};

const modulePath = require.resolve(path.resolve(__dirname, '../../extension/background/background.js'));
delete require.cache[modulePath];
require(modulePath);
const listener = listeners[0];

function setNativeHandler(handler) {
  nativeHandler = handler;
}

function proposal(overrides = {}) {
  return {
    type: 'ACTION_PROPOSAL',
    version: 1,
    nonce: '0123456789abcdef0123456789abcdef',
    candidateId: 'youtube_skip_v1',
    pluginId: 'youtube',
    intent: 'SkipInterruption',
    proposedAction: 'click',
    confidence: 0.98,
    evidenceCodes: ['VISIBLE', 'ENABLED', 'INTERACTIVE_ROLE', 'SUPPORTED_CONTROL_TEXT'],
    observedAt: Date.now(),
    ...overrides,
  };
}

const sender = {
  tab: { id: 7, url: 'https://www.youtube.com/watch?v=1' },
  frameId: 0,
  url: 'https://www.youtube.com/watch?v=1',
};

test('background test harness captured the top-level listener', () => {
  assert.equal(typeof listener, 'function');
});

test('background stamps authoritative sender metadata and accepts native DENY', async () => {
  let captured;
  setNativeHandler(async (request) => {
    captured = request;
    return {
      type: 'POLICY_RESULT', version: 1, requestId: request.requestId,
      nonce: request.nonce, candidateId: request.candidateId,
      decision: 'DENY', reasonCode: 'PHASE_1_DEFAULT_DENY',
    };
  });

  const result = await listener(proposal(), sender);
  assert.equal(captured.tabId, 7);
  assert.equal(captured.frameId, 0);
  assert.equal(captured.host, 'www.youtube.com');
  assert.equal(captured.origin, 'https://www.youtube.com');
  assert.equal(result.decision, 'DENY');
});

test('content-supplied authority fields are rejected as additional properties', async () => {
  let nativeCalls = 0;
  setNativeHandler(async () => { nativeCalls += 1; throw new Error('must not call native'); });
  const result = await listener(proposal({ tabId: 999 }), sender);
  assert.equal(result.decision, 'DENY');
  assert.equal(result.reasonCode, 'INVALID_ACTION_PROPOSAL');
  assert.equal(nativeCalls, 0);
});

test('invalid or non-youtube sender fails closed before native bridge', async () => {
  let nativeCalls = 0;
  setNativeHandler(async () => { nativeCalls += 1; });
  const result = await listener(proposal(), { tab: { id: 1 }, frameId: 0, url: 'https://evil.example/' });
  assert.equal(result.reasonCode, 'INVALID_MESSAGE_SENDER');
  assert.equal(nativeCalls, 0);
});

test('native bridge unavailable fails closed', async () => {
  setNativeHandler(async () => { throw new Error('xpc down'); });
  const result = await listener(proposal(), sender);
  assert.equal(result.decision, 'DENY');
  assert.equal(result.reasonCode, 'NATIVE_BRIDGE_UNAVAILABLE');
});

test('Phase 1 rejects native ALLOW and cannot create execution authorization', async () => {
  setNativeHandler(async (request) => ({
    type: 'POLICY_RESULT', version: 1, requestId: request.requestId,
    nonce: request.nonce, candidateId: request.candidateId,
    decision: 'ALLOW', reasonCode: 'TEST_ALLOW',
  }));

  const result = await listener(proposal(), sender);
  assert.equal(result.decision, 'DENY');
  assert.equal(result.reasonCode, 'PHASE_1_NON_DENY_REJECTED');
  assert.equal('authorizationToken' in result, false);
});

test('mismatched native response is rejected', async () => {
  setNativeHandler(async (request) => ({
    type: 'POLICY_RESULT', version: 1, requestId: request.requestId,
    nonce: request.nonce, candidateId: 'different', decision: 'DENY', reasonCode: 'PHASE_1_DEFAULT_DENY',
  }));

  const result = await listener(proposal(), sender);
  assert.equal(result.reasonCode, 'INVALID_NATIVE_RESPONSE');
});
