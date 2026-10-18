import { readFile } from 'node:fs/promises';
import { validateFixture, type Fixture, type Review } from './types.ts';
const policy = JSON.parse(await readFile(new URL('../.antigravity/review-rules.json', import.meta.url), 'utf8'));
export function review(fixture: Fixture): Review {
  validateFixture(fixture);
  const out: Review = { verdict: 'ship', findings: [], inspected: [], notInspected: [] };
  const rules = policy.rules.map((r: {category:string;pattern:string;flags:string}) => ({ ...r, regex: new RegExp(r.pattern,r.flags) }));
  const injection = rules.find((r: {category:string}) => r.category === 'security/prompt-injection');
  const instruction = [fixture.title,fixture.body,...fixture.files.map(f => f.patch ?? '')].find(t => injection.regex.test(t));
  if (instruction) return { verdict:'blocked', findings:[{category:injection.category,file:'PR input',evidence:instruction.match(injection.regex)![0]}], inspected:[],notInspected:fixture.files.map(f=>f.filename),reason:'AI-directed input detected; halted before code review.' };
  let used = 0;
  for (const file of fixture.files) {
    const size = Buffer.byteLength(file.patch ?? '');
    if (file.patch === null || used + size > policy.maxPatchBytes) {out.notInspected.push(file.filename);continue;}
    used += size; out.inspected.push(file.filename);
    if (/\.(md|txt)$|(^|\/)(tests?|__tests__)\//i.test(file.filename)) continue;
    const added = file.patch.split('\n').filter(l=>l.startsWith('+')&&!l.startsWith('+++')).map(l=>l.slice(1)).join('\n');
    for (const rule of rules.filter((r: {category:string})=>r.category!=='security/prompt-injection')) {
      const match = added.match(rule.regex);
      if (match) out.findings.push({category:rule.category,file:file.filename,evidence:match[0]});
    }
  }
  if (!fixture.complete || out.notInspected.length) {out.verdict='incomplete';out.reason='Missing or over-budget context; human review required.';}
  else if(out.findings.length) out.verdict='blocked';
  return out;
}
