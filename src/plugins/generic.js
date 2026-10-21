function toCandidate(element, index) {
  const text = String(element?.textContent ?? '').trim();
  const ariaLabel = String(element?.getAttribute?.('aria-label') ?? '').trim();
  return {
    id: element?.dataset?.carinaId ?? `generic-${index}-${text || ariaLabel}`,
    text,
    ariaLabel,
    role: element?.getAttribute?.('role') ?? (element?.tagName?.toLowerCase() === 'button' ? 'button' : null),
    visible: element?.hidden !== true,
    enabled: element?.disabled !== true,
    observedAt: Date.now(),
    proposedAction: 'click',
    element,
  };
}

export const genericPlugin = Object.freeze({
  id: 'generic',
  hosts: ['*'],
  detect() { return true; },
  candidates(context) {
    if (!context.document?.querySelectorAll) return [];
    return [...context.document.querySelectorAll('button, [role="button"], a')]
      .map(toCandidate)
      .filter((candidate) => /^(skip|continue|close|dismiss|not now|resume)$/i.test((candidate.text || candidate.ariaLabel).trim()));
  },
  signals() { return { siteSpecificMatch: false }; },
  verify(candidate) {
    const element = candidate.element;
    return Boolean(element && (element.isConnected === false || element.hidden === true || element.getAttribute?.('aria-hidden') === 'true'));
  },
});
