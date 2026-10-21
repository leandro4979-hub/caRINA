/* global browser, chrome */

'use strict';

const runtime = globalThis.browser?.runtime ?? globalThis.chrome?.runtime;

const INTENTS = new Set(['SkipInterruption', 'ContinuePlayback', 'CloseOverlay']);
const EVIDENCE_CODES = new Set([
  'VISIBLE', 'ENABLED', 'INTERACTIVE_ROLE', 'SUPPORTED_CONTROL_TEXT',
  'MEDIA_PLAYING', 'OVERLAY_VISIBLE', 'PLUGIN_SITE_SIGNAL',
]);

const HEX32 = /^[a-f0-9]{32}$/;
const CANDIDATE_ID = /^[A-Za-z0-9._:-]{1,128}$/;
const PLUGIN_ID = /^[a-z0-9._-]{1,64}$/;
const REASON_CODE = /^[A-Z0-9_]{1,64}$/;
const ALLOWED_HOSTS = new Set(['youtube.com', 'www.youtube.com', 'm.youtube.com']);

function denyFor(message, reasonCode) {
  return Object.freeze({
    type: 'POLICY_RESULT',
    version: 1,
    requestId: HEX32.test(message?.requestId ?? '') ? message.requestId : '00000000000000000000000000000000',
    nonce: HEX32.test(message?.nonce ?? '') ? message.nonce : '00000000000000000000000000000000',
    candidateId: CANDIDATE_ID.test(message?.candidateId ?? '') ? message.candidateId : 'unknown',
    decision: 'DENY',
    reasonCode,
  });
}

function hasExactKeys(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  return actual.length === expected.length && actual.every((key, index) => key === expected[index]);
}

function isActionProposal(message) {
  const keys = ['type', 'version', 'nonce', 'candidateId', 'pluginId', 'intent', 'proposedAction', 'confidence', 'evidenceCodes', 'observedAt'];
  return hasExactKeys(message, keys)
    && message.type === 'ACTION_PROPOSAL'
    && message.version === 1
    && HEX32.test(message.nonce)
    && CANDIDATE_ID.test(message.candidateId)
    && PLUGIN_ID.test(message.pluginId)
    && INTENTS.has(message.intent)
    && message.proposedAction === 'click'
    && typeof message.confidence === 'number'
    && Number.isFinite(message.confidence)
    && message.confidence >= 0
    && message.confidence <= 1
    && Array.isArray(message.evidenceCodes)
    && message.evidenceCodes.length <= 16
    && new Set(message.evidenceCodes).size === message.evidenceCodes.length
    && message.evidenceCodes.every((code) => EVIDENCE_CODES.has(code))
    && Number.isSafeInteger(message.observedAt)
    && message.observedAt >= 0;
}

function senderMetadata(sender) {
  const tabId = sender?.tab?.id;
  const frameId = sender?.frameId;
  const rawUrl = sender?.url ?? sender?.tab?.url;
  if (!Number.isInteger(tabId) || tabId < 0 || !Number.isInteger(frameId) || frameId < 0 || typeof rawUrl !== 'string') return null;

  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    return null;
  }

  if (url.protocol !== 'https:' || !ALLOWED_HOSTS.has(url.hostname.toLowerCase())) return null;

  return Object.freeze({
    tabId,
    frameId,
    origin: url.origin,
    host: url.hostname.toLowerCase(),
  });
}

function randomHex32() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function buildPolicyRequest(proposal, sender) {
  const metadata = senderMetadata(sender);
  if (!metadata) return null;

  return Object.freeze({
    type: 'POLICY_REQUEST',
    version: 1,
    requestId: randomHex32(),
    nonce: proposal.nonce,
    candidateId: proposal.candidateId,
    pluginId: proposal.pluginId,
    intent: proposal.intent,
    proposedAction: proposal.proposedAction,
    tabId: metadata.tabId,
    frameId: metadata.frameId,
    origin: metadata.origin,
    host: metadata.host,
    confidence: proposal.confidence,
    observedAt: proposal.observedAt,
    receivedAt: Date.now(),
  });
}

function isPolicyResult(response, request) {
  const keys = ['type', 'version', 'requestId', 'nonce', 'candidateId', 'decision', 'reasonCode'];
  return hasExactKeys(response, keys)
    && response.type === 'POLICY_RESULT'
    && response.version === 1
    && response.requestId === request.requestId
    && response.nonce === request.nonce
    && response.candidateId === request.candidateId
    && ['ALLOW', 'DENY', 'APPROVAL_REQUIRED'].includes(response.decision)
    && REASON_CODE.test(response.reasonCode);
}

async function handleActionProposal(message, sender) {
  if (!isActionProposal(message)) return denyFor(message, 'INVALID_ACTION_PROPOSAL');

  const policyRequest = buildPolicyRequest(message, sender);
  if (!policyRequest) return denyFor(message, 'INVALID_MESSAGE_SENDER');

  let nativeResponse;
  try {
    // Safari accepts the one-argument form in current releases; the application id is not authoritative.
    nativeResponse = await runtime.sendNativeMessage(policyRequest);
  } catch {
    return denyFor(policyRequest, 'NATIVE_BRIDGE_UNAVAILABLE');
  }

  if (!isPolicyResult(nativeResponse, policyRequest)) return denyFor(policyRequest, 'INVALID_NATIVE_RESPONSE');

  // Phase 1 is DENY-only. No execution authorization is minted in this milestone.
  if (nativeResponse.decision !== 'DENY') return denyFor(policyRequest, 'PHASE_1_NON_DENY_REJECTED');

  return Object.freeze({ ...nativeResponse });
}

runtime.onMessage.addListener((message, sender) => {
  if (message?.type !== 'ACTION_PROPOSAL') return Promise.resolve(denyFor(message, 'UNSUPPORTED_MESSAGE_TYPE'));
  return handleActionProposal(message, sender);
});

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { isActionProposal, senderMetadata, buildPolicyRequest, isPolicyResult, handleActionProposal, denyFor };
}
