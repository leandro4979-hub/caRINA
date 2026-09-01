export function classifySafety(candidate, context) {
  const candidateText = `${candidate.text ?? ''} ${candidate.ariaLabel ?? ''}`.toLowerCase();
  const sensitive = context.sensitiveSignals.length > 0 || /password|checkout|pay|wallet|login|sign in|2fa|captcha|api key|token|ssh|gpg/.test(candidateText);
  return Object.freeze({
    sensitive,
    decision: sensitive ? 'DENY' : 'SAFE_TO_EVALUATE',
    reasons: Object.freeze(sensitive ? ['SENSITIVE_CONTEXT'] : []),
  });
}
