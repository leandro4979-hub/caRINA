export const PolicyDecision = Object.freeze({
  DENY: 'DENY',
  APPROVAL_REQUIRED: 'APPROVAL_REQUIRED',
  ALLOW: 'ALLOW',
});

const KNOWN = new Set(Object.values(PolicyDecision));

export function buildPolicyProposal({ candidate, context, intent, score, safety, pluginId }) {
  return Object.freeze({
    candidateId: candidate.id,
    pluginId,
    intent,
    confidence: score.confidence,
    scoreReasons: score.reasons,
    host: context.host,
    pathname: context.pathname,
    mediaPlaying: context.mediaPlaying,
    overlayVisible: context.overlayVisible,
    sensitive: safety.sensitive,
  });
}

export async function evaluatePolicy(policyEngine, proposal) {
  if (!policyEngine || typeof policyEngine.decide !== 'function') {
    return Object.freeze({ state: PolicyDecision.DENY, reason: 'POLICY_ENGINE_UNAVAILABLE' });
  }
  const result = await policyEngine.decide(proposal);
  const state = result?.state;
  if (!KNOWN.has(state)) {
    return Object.freeze({ state: PolicyDecision.DENY, reason: 'UNKNOWN_POLICY_STATE' });
  }
  return Object.freeze({ state, reason: result?.reason ?? null });
}
