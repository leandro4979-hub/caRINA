import { Runtime, redact } from './runtime.ts';
import { validateFixture, type Fixture } from '../types.ts';
export class GitHubReadTools {
  readonly repo: string; readonly runtime: Runtime; readonly token: string;
  constructor(repo: string, runtime: Runtime, token = process.env.GITHUB_TOKEN) {
    if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(repo)) throw new Error('Use owner/repository');
    if (!token) throw new Error('GITHUB_TOKEN is required for fixture capture');
    this.repo=repo;this.runtime=runtime;this.token=token;
  }
  private async get(path: string): Promise<any> {
    return this.runtime.call('github.read', { path }, async (_,signal) => {
      // Fixed origin, GET only, no redirects, no shell or arbitrary URLs.
      const res = await fetch(`https://api.github.com/repos/${this.repo}/${path}`, {
        signal, redirect:'error', headers:{Accept:'application/vnd.github+json',Authorization:`Bearer ${this.token}`,'X-GitHub-Api-Version':'2022-11-28'}
      });
      if (!res.ok) throw new Error(`GitHub read failed: HTTP ${res.status}`);
      if (Number(res.headers.get('content-length') ?? 0) > 8_000_000) throw new Error('Response too large');
      const reader = res.body!.getReader(); const chunks: Uint8Array[] = []; let size = 0;
      try { while(true) {const {value,done}=await reader.read();if(done)break;size+=value.length;
        if(size>8_000_000)throw new Error('Response too large');chunks.push(value);}
      } finally {await reader.cancel();}
      return JSON.parse(redact(Buffer.concat(chunks).toString('utf8')));
    });
  }
  async list_review_queue() { return this.get('pulls?state=open&per_page=100'); }
  async get_pr_context(pr: number): Promise<Fixture> {
    if (!Number.isSafeInteger(pr)||pr<1)throw new Error('PR must be a positive integer');
    const before = await this.get(`pulls/${pr}`);
    const files: Fixture['files'] = [];
    for(let page=1;page<=30;page++) {
      const batch=await this.get(`pulls/${pr}/files?per_page=100&page=${page}`);
      files.push(...batch.map((f:any)=>({filename:f.filename,patch:f.patch??null,status:f.status})));
      if(batch.length<100)break;
    }
    const after=await this.get(`pulls/${pr}`);
    if(before.head.sha!==after.head.sha || before.base.sha!==after.base.sha)throw new Error('PR changed during capture; discard and capture again');
    const result:Fixture={schemaVersion:1,provenance:'github',number:pr,title:before.title,body:before.body??'',headSha:before.head.sha,files,
      complete: files.length===before.changed_files && files.every(f=>f.patch!==null)};
    validateFixture(result);return result;
  }
}
