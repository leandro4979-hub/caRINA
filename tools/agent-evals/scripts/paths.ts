export function requiresEvals(paths: string[]): boolean {
  return paths.some(p => /(^|\/)AGENTS\.md$/.test(p)
    || /(^|\/)\.antigravity\//.test(p)
    || /(^|\/)(?:tools?|schemas?|tool-schemas)\//.test(p)
    || /schema/i.test(p)
    || /^(?:src|evals|scripts|tests|\.github|CARINAApprovalBoundary|CarinaMacApp)\//.test(p)
    || /^docs\/(?:AGENT_|SECURITY_REQUIREMENTS|AGENT_EVALS)/.test(p)
    || /^(?:package\.json|pnpm-lock\.yaml|\.nvmrc)$/.test(p));
}
