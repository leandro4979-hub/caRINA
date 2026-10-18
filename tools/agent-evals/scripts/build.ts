import { readdir, readFile, mkdir, writeFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { dirname } from 'node:path';
async function walk(dir:string):Promise<string[]> {const entries=await readdir(dir,{withFileTypes:true});return (await Promise.all(entries.map(e=>e.isDirectory()?walk(`${dir}/${e.name}`):[`${dir}/${e.name}`]))).flat();}
let count=0;
for(const dir of ['src','scripts','evals','tests'])for(const file of await walk(dir))if(file.endsWith('.ts')){
  const target=`dist/${file.replace(/\.ts$/,'.js')}`;await mkdir(dirname(target),{recursive:true});
  const js=stripTypeScriptTypes(await readFile(file,'utf8')).replace(/(from\s+['"][^'"]+)\.ts(['"])/g,'$1.js$2');
  await writeFile(target,js);count++;
}
await mkdir('dist/.antigravity',{recursive:true});await writeFile('dist/.antigravity/review-rules.json',await readFile('.antigravity/review-rules.json'));
console.log(`Transpiled ${count} TypeScript files. This build does not perform static type checking.`);
