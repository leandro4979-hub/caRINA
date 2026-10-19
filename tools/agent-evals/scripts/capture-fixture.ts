import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { randomUUID } from 'node:crypto';
import { GitHubReadTools } from '../src/lib/github.ts';
import { Runtime, redact } from '../src/lib/runtime.ts';
function arg(name:string){const i=process.argv.indexOf(name);return i<0?undefined:process.argv[i+1];}
try {
  const repo=arg('--repo')??process.env.GITHUB_REPOSITORY, out=arg('--out'),pr=Number(arg('--pr'));
  if(!repo||!out||!Number.isSafeInteger(pr)||pr<1)throw new Error('Usage: pnpm capture --repo owner/repo --pr 311 --out evals/fixtures/pr-311.json');
  const fixture=await new GitHubReadTools(repo,new Runtime(randomUUID())).get_pr_context(pr);
  await mkdir(dirname(out),{recursive:true});
  await writeFile(out,redact(JSON.stringify(fixture,null,2))+'\n',{flag:'wx',mode:0o600});
  console.log(`Captured PR ${pr}; complete=${fixture.complete}. Audit for private data before committing.`);
} catch(e){console.error(redact(String(e)));process.exitCode=1;}
