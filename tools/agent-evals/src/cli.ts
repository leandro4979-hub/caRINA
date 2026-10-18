import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { review } from './reviewer.ts';
import { Runtime, redact } from './lib/runtime.ts';
const runtime = new Runtime(randomUUID());
await mkdir('.guardian',{recursive:true});
try {
  const path = process.argv[2];if(!path)throw new Error('Usage: pnpm review evals/fixtures/clean-1.json');
  const fixture = await runtime.call('fixture.read',{path},async()=>JSON.parse(await readFile(path,'utf8')));
  const result = await runtime.call('review.offline',{},async()=>review(fixture));
  await writeFile('.guardian/review.json',redact(JSON.stringify({runId:runtime.runId,...result,toolCalls:runtime.calls,tokenSpend:0},null,2))+'\n');
  console.log(result.verdict);if(result.verdict!=='ship')process.exitCode=1;
} catch(e) {
  await writeFile('.guardian/review.json',JSON.stringify({runId:runtime.runId,verdict:'incomplete',reason:redact(String(e)),toolCalls:runtime.calls,inspected:[],notInspected:['unknown: execution interrupted']},null,2));
  console.error(redact(String(e)));process.exitCode=1;
}
