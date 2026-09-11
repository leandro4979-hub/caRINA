function isTransient(error) {
  return error?.transient === true;
}

export class ActionQueue {
  #seen = new Set();
  #cancelled = new Set();
  #tail = Promise.resolve();
  #sequence = 0;

  cancel(candidateId) {
    this.#cancelled.add(candidateId);
  }

  enqueue(candidate, task, { maxTransientRetries = 0 } = {}) {
    if (this.#seen.has(candidate.id)) return Promise.resolve({ status: 'DUPLICATE', candidateId: candidate.id });
    if (this.#cancelled.has(candidate.id)) return Promise.resolve({ status: 'CANCELLED', candidateId: candidate.id });
    this.#seen.add(candidate.id);
    const actionId = `browser-action-${++this.#sequence}`;

    const run = async () => {
      let attempt = 0;
      while (true) {
        if (this.#cancelled.has(candidate.id)) return { actionId, status: 'CANCELLED', candidateId: candidate.id };
        try {
          return { actionId, ...(await task(actionId, attempt)) };
        } catch (error) {
          if (!isTransient(error) || attempt >= maxTransientRetries) throw error;
          attempt += 1;
        }
      }
    };

    const result = this.#tail.then(run, run);
    this.#tail = result.catch(() => {});
    return result;
  }
}
