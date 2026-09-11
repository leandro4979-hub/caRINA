const BLOCKED_KEYS = /password|cookie|authorization|secret|private.?key|api.?key|token|credential|session/i;

function sanitize(value, depth = 0) {
  if (depth > 4) return '[TRUNCATED]';
  if (Array.isArray(value)) return value.slice(0, 50).map((item) => sanitize(item, depth + 1));
  if (value && typeof value === 'object') {
    const out = {};
    for (const [key, child] of Object.entries(value)) {
      out[key] = BLOCKED_KEYS.test(key) ? '[REDACTED]' : sanitize(child, depth + 1);
    }
    return out;
  }
  if (typeof value === 'string' && value.length > 500) return `${value.slice(0, 500)}…`;
  return value;
}

export class StructuredLogger {
  constructor(sink = () => {}) {
    this.sink = sink;
  }

  log(event, data = {}) {
    this.sink(Object.freeze({
      event,
      at: new Date().toISOString(),
      data: Object.freeze(sanitize(data)),
    }));
  }
}

export { sanitize as sanitizeLogData };
