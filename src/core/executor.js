const ALLOWED_ACTIONS = new Set(['click']);

export async function executeCandidate(candidate) {
  if (!candidate || !ALLOWED_ACTIONS.has(candidate.proposedAction)) {
    throw new Error('Candidate action is not allowed');
  }
  if (!candidate.element || typeof candidate.element.click !== 'function') {
    throw new Error('Candidate target is not executable');
  }
  candidate.element.click();
}
