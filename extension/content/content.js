/* global browser, chrome */

'use strict';

(() => {
  const runtime = globalThis.browser?.runtime ?? globalThis.chrome?.runtime;
  if (!runtime?.sendMessage) return;

  function randomHex32() {
    const bytes = new Uint8Array(16);
    crypto.getRandomValues(bytes);
    return [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
  }

  const proposal = Object.freeze({
    type: 'ACTION_PROPOSAL',
    version: 1,
    nonce: randomHex32(),
    candidateId: 'youtube_skip_v1',
    pluginId: 'youtube',
    intent: 'SkipInterruption',
    proposedAction: 'click',
    confidence: 0.98,
    evidenceCodes: Object.freeze(['VISIBLE', 'ENABLED', 'INTERACTIVE_ROLE', 'SUPPORTED_CONTROL_TEXT']),
    observedAt: Date.now(),
  });

  // Phase 1 intentionally keeps no element reference and contains no DOM executor.
  console.info('[CARINA Content] Dispatching synthetic ACTION_PROPOSAL.');

  Promise.resolve(runtime.sendMessage(proposal))
    .then((response) => {
      if (response?.type === 'POLICY_RESULT' && response?.decision === 'DENY') {
        console.info(`[CARINA Content] DENY confirmed: ${response.reasonCode}`);
        console.info('[CARINA Content] Phase 1 acceptance gate held; no DOM action exists.');
        return;
      }

      console.error('[CARINA Content] Fail-closed: invalid or non-DENY policy response.');
    })
    .catch((error) => {
      console.error('[CARINA Content] Fail-closed transport error:', String(error?.message ?? error));
    });
})();
