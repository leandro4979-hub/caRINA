export const Intent = Object.freeze({
  SKIP_INTERRUPTION: 'SkipInterruption',
  CONTINUE_PLAYBACK: 'ContinuePlayback',
  CLOSE_OVERLAY: 'CloseOverlay',
  IGNORE_SENSITIVE_FLOW: 'IgnoreSensitiveFlow',
});

export function inferIntent(candidate, context) {
  const text = `${candidate.text ?? ''} ${candidate.ariaLabel ?? ''}`.trim().toLowerCase();
  if (context.sensitiveSignals.length > 0) return Intent.IGNORE_SENSITIVE_FLOW;
  if (/skip/.test(text)) return Intent.SKIP_INTERRUPTION;
  if (/resume|continue/.test(text) && context.mediaPlaying === false) return Intent.CONTINUE_PLAYBACK;
  if (/close|dismiss|not now/.test(text) && context.overlayVisible) return Intent.CLOSE_OVERLAY;
  return null;
}
