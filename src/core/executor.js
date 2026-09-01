export async function executeCandidate(candidate) {
  if (!candidate || typeof candidate.perform !== 'function') {
    throw new Error('Candidate is not executable');
  }
  await candidate.perform();
}
