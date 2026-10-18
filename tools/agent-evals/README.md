# Agent eval harness

EVAL-001 isolates the Clever AI Guardian scaffold from CARINA runtime code.
Requires Node 24.3+; no packages, API keys or pnpm are needed for CI.

```sh
cd tools/agent-evals
node scripts/build.ts
node --test tests/*.test.ts
python3 -m unittest discover -s tests -p "test_*.py"
node evals/runner.ts
node src/cli.ts evals/fixtures/clean-1.json
```

The build strips TypeScript annotations; it does not statically check types.
The 20 bundled cases are synthetic bootstrap regression inputs. They test a
small deterministic SQL/destructive-query/injection rule baseline, not an AI
reviewer, CARINA policy decisions, or production precision. Prompt edits
trigger this harness and CARINA's existing Swift tests, but natural-language
prompt effectiveness is not measured until a model adapter and audited real
PR corpus are added.

All fixture text is untrusted. The regex injection detector has known false
positives and coverage gaps; it is not an authorization boundary. Missing or
oversized context yields incomplete, never ship. The CLI writes a JSON review
artifact and call traces under `.guardian`; budget breaches return partial
results. GitHub capture is GET-only with a fixed API origin, redirect denial,
response caps, head/base consistency checks and environment-token redaction.
No review posting, auto-approval, shell tools or execution authority is added.

For explicitly authorized real-PR capture, set a repository-scoped read-only
GITHUB_TOKEN in the environment and run:

```sh
node scripts/capture-fixture.ts --repo OWNER/REPO --pr 311 --out evals/fixtures/pr-311.json
```

Capture refuses overwrite. Inspect captures for private data before committing;
redaction cannot guarantee anonymization. Add independently audited case
verdicts before using results as evidence of reviewer quality.

See [the integration contract](../../docs/AGENT_EVALS.md) for path coverage,
required-check activation and limitations.
