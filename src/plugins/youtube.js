function controlFromElement(element, index) {
  const text = String(element?.textContent ?? '').trim();
  const ariaLabel = String(element?.getAttribute?.('aria-label') ?? '').trim();
  return {
    id: element?.dataset?.carinaId ?? `youtube-${index}-${text || ariaLabel}`,
    text,
    ariaLabel,
    role: element?.getAttribute?.('role') ?? (element?.tagName?.toLowerCase() === 'button' ? 'button' : null),
    visible: element?.hidden !== true,
    enabled: element?.disabled !== true,
    observedAt: Date.now(),
    perform: () => element.click(),
    element,
  };
}

export const youtubePlugin = Object.freeze({
  id: 'youtube',
  hosts: ['youtube.com'],
  detect(context) {
    return context.host === 'youtube.com' || context.host.endsWith('.youtube.com');
  },
  candidates(context) {
    if (!context.document?.querySelectorAll) return [];
    return [...context.document.querySelectorAll('button, [role="button"]')]
      .map(controlFromElement)
      .filter((candidate) => /skip|continue|resume|close|dismiss|not now/i.test(`${candidate.text} ${candidate.ariaLabel}`));
  },
  signals(_context, candidate) {
    return { siteSpecificMatch: /skip|continue|resume|close|dismiss/i.test(`${candidate.text} ${candidate.ariaLabel}`) };
  },
  verify(candidate, context) {
    if (candidate.intent === 'ContinuePlayback' && context.document?.querySelector) {
      const video = context.document.querySelector('video');
      if (video) return video.paused === false;
    }
    const element = candidate.element;
    if (!element) return false;
    return element.isConnected === false || element.hidden === true || element.getAttribute?.('aria-hidden') === 'true';
  },
});
