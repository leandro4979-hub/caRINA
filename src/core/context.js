const SENSITIVE_TERMS = Object.freeze([
  'payment', 'checkout', 'purchase', 'financial transfer', 'login', 'password',
  'passkey', '2fa', 'two-factor', 'captcha', 'account recovery', 'security settings',
  'permission escalation', 'credential', 'ssh', 'gpg', 'api key', 'token', 'wallet',
]);

export function extractContext(input = {}) {
  const url = input.url instanceof URL ? input.url : new URL(input.url ?? 'https://invalid.local/');
  const pageText = String(input.pageText ?? '').toLowerCase();
  const sensitiveSignals = SENSITIVE_TERMS.filter((term) => pageText.includes(term));

  return Object.freeze({
    host: url.hostname.toLowerCase(),
    pathname: url.pathname,
    pageType: input.pageType ?? 'generic',
    mediaPlaying: Boolean(input.mediaPlaying),
    overlayVisible: Boolean(input.overlayVisible),
    userActive: input.userActive !== false,
    document: input.document ?? null,
    sensitiveSignals: Object.freeze(sensitiveSignals),
  });
}
