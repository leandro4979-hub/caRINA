export function observeDom(root, onMutation) {
  if (typeof MutationObserver === 'undefined') {
    throw new Error('MutationObserver unavailable in this runtime');
  }
  const observer = new MutationObserver((records) => onMutation(records));
  observer.observe(root, { childList: true, subtree: true, attributes: true });
  return () => observer.disconnect();
}
