import { appendFile, mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';
export const LIMITS = { maxToolCalls: 60, maxWallClockMs: 12 * 60_000, maxConsecutiveErrors: 2 };
export function redact(text: string): string {
  const secrets = Object.entries(process.env).filter(([k,v]) => /TOKEN|SECRET|PASSWORD|API_KEY/i.test(k) && v && v.length >= 8).map(([,v]) => v!);
  for (const secret of secrets) text = text.split(secret).join('[REDACTED]');
  return text.replace(/(?:github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9_]+|AIza[A-Za-z0-9_-]{20,})/g, '[REDACTED]')
    .replace(/Bearer\s+[^\s"\\]+/gi, 'Bearer [REDACTED]');
}
export class Runtime {
  calls = 0; errors = 0; started = performance.now(); halted = false;
  readonly runId: string; readonly tracePath: string; readonly limits: typeof LIMITS;
  constructor(runId: string, tracePath = '.guardian/trace.jsonl', limits = LIMITS) { this.runId=runId; this.tracePath=tracePath; this.limits=limits; }
  async call<A, R>(tool: string, args: A, fn: (args: A, signal: AbortSignal) => Promise<R>): Promise<R> {
    const remaining = this.limits.maxWallClockMs - (performance.now() - this.started);
    if (this.halted || this.calls >= this.limits.maxToolCalls || this.errors >= this.limits.maxConsecutiveErrors || remaining <= 0) {
      this.halted = true; throw new Error('Circuit breaker: run budget exhausted');
    }
    this.calls++;
    const t0 = performance.now(); let ok = false, outputBytes = 0, error: string | undefined;
    const controller = new AbortController(); let timer: ReturnType<typeof setTimeout>;
    try {
      const deadline = new Promise<never>((_, reject) => {
        timer = setTimeout(() => { this.halted = true; controller.abort(); reject(new Error('Circuit breaker: wall-clock deadline')); }, remaining);
      });
      const result = await Promise.race([fn(args, controller.signal), deadline]);
      outputBytes = Buffer.byteLength(JSON.stringify(result) ?? '');
      ok = true; this.errors = 0; return result;
    } catch (e) {
      this.errors++; error = redact(e instanceof Error ? e.message : String(e)); throw new Error(error);
    } finally {
      clearTimeout(timer!);
      await mkdir(dirname(this.tracePath), { recursive: true });
      await appendFile(this.tracePath, JSON.stringify({ ts: new Date().toISOString(), runId: this.runId, tool,
        durationMs: Math.round(performance.now()-t0), ok,
        inputBytes: Buffer.byteLength(JSON.stringify(args) ?? ''), outputBytes, error })+'\n', { mode: 0o600 });
    }
  }
}
