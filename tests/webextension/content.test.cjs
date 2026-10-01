const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('Phase 1 content script has no DOM execution primitive', () => {
  const source = fs.readFileSync(path.resolve(__dirname, '../../extension/content/content.js'), 'utf8');
  assert.doesNotMatch(source, /\.click\s*\(/);
  assert.doesNotMatch(source, /executeCandidate|EXECUTION_AUTHORIZATION|authorizationToken/);
  assert.match(source, /crypto\.getRandomValues/);
});
