export class EventBus {
  #handlers = new Map();

  on(event, handler) {
    if (typeof handler !== 'function') throw new TypeError('handler must be a function');
    const handlers = this.#handlers.get(event) ?? new Set();
    handlers.add(handler);
    this.#handlers.set(event, handlers);
    return () => handlers.delete(handler);
  }

  emit(event, payload) {
    for (const handler of this.#handlers.get(event) ?? []) handler(payload);
  }
}
