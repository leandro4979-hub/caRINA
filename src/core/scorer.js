export function scoreCandidate(candidate, context, pluginSignals = {}) {
  let score = 0;
  const reasons = [];

  if (candidate.visible) { score += 0.25; reasons.push('VISIBLE'); }
  if (candidate.enabled) { score += 0.15; reasons.push('ENABLED'); }
  if (['button', 'link'].includes(candidate.role)) { score += 0.2; reasons.push('INTERACTIVE_ROLE'); }
  if (/skip|continue|resume|close|dismiss|not now/i.test(`${candidate.text ?? ''} ${candidate.ariaLabel ?? ''}`)) {
    score += 0.2; reasons.push('SUPPORTED_CONTROL_TEXT');
  }
  if (context.mediaPlaying || context.overlayVisible) { score += 0.1; reasons.push('RELEVANT_PAGE_STATE'); }
  if (pluginSignals.siteSpecificMatch === true) { score += 0.1; reasons.push('PLUGIN_SITE_SIGNAL'); }

  return Object.freeze({ confidence: Math.min(1, score), reasons: Object.freeze(reasons) });
}
