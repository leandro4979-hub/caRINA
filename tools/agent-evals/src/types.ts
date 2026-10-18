export type Finding = { category: string; file: string; evidence: string };
export type Fixture = {
  schemaVersion: 1; provenance: 'synthetic' | 'github'; number: number;
  title: string; body: string; headSha: string;
  files: { filename: string; patch: string | null; status: string }[];
  complete: boolean;
};
export type Review = {
  verdict: 'ship' | 'blocked' | 'incomplete'; findings: Finding[];
  inspected: string[]; notInspected: string[]; reason?: string;
};
export function validateFixture(value: unknown): asserts value is Fixture {
  const f = value as Fixture;
  if (!f || f.schemaVersion !== 1 || !['synthetic','github'].includes(f.provenance)
      || !Number.isInteger(f.number) || f.number < 1 || typeof f.title !== 'string'
      || typeof f.body !== 'string' || typeof f.headSha !== 'string'
      || typeof f.complete !== 'boolean' || !Array.isArray(f.files)
      || f.files.some(x => !x || typeof x.filename !== 'string' || typeof x.status !== 'string'
          || (x.patch !== null && typeof x.patch !== 'string')))
    throw new Error('Invalid fixture schema');
}
