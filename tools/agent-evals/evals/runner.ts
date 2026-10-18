import { readFile, readdir, writeFile } from 'node:fs/promises';
import { resolve, sep } from 'node:path';
import { review } from '../src/reviewer.ts';
import { redact } from '../src/lib/runtime.ts';
const results: object[]=[];let failures=0;
try {
  const files=(await readdir('evals/cases')).filter(f=>f.endsWith('.case.json')).sort();
  if(!files.length)throw new Error('Empty eval corpus');
  const ids=new Set();
  for(const name of files){
    try {
      const c=JSON.parse(await readFile(`evals/cases/${name}`,'utf8'));
      if(typeof c.id!=='string'||ids.has(c.id)||!['ship','blocked','incomplete'].includes(c.expectedVerdict)
        ||!Array.isArray(c.mustFlag)||!Array.isArray(c.mustNotFlag)||![...c.mustFlag,...c.mustNotFlag].every(x=>typeof x==='string'))throw new Error('Invalid or duplicate eval case');
      ids.add(c.id);
      const path=resolve(c.fixture);if(!path.startsWith(resolve('evals/fixtures')+sep))throw new Error('Fixture outside corpus');
      const fixture=JSON.parse(await readFile(path,'utf8'));
      const actual=review(fixture),flags=actual.findings.map(f=>f.category);
      const errors=[...(actual.verdict===c.expectedVerdict?[]:[`verdict ${actual.verdict} != ${c.expectedVerdict}`]),
        ...c.mustFlag.filter((x:string)=>!flags.includes(x)).map((x:string)=>`missing ${x}`),
        ...c.mustNotFlag.filter((x:string)=>flags.includes(x)).map((x:string)=>`unexpected ${x}`)];
      if(errors.length)failures++;
      results.push({id:c.id,provenance:fixture.provenance,passed:!errors.length,errors,actual});
    } catch(e){failures++;results.push({id:name,passed:false,error:redact(String(e))});}
  }
} catch(e){failures++;results.push({passed:false,error:redact(String(e))});}
await writeFile('evals/report.json',redact(JSON.stringify({schemaVersion:1,mode:'offline-rule-baseline',cases:results.length,failures,results},null,2))+'\n');
console.log(`${results.length} eval cases; ${failures} failures`);if(failures)process.exitCode=1;
