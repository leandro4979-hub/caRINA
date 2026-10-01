const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('manifest is MV3, uses a service worker, and contains only Phase 1 permissions', () => {
  const manifest = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../extension/manifest.json'), 'utf8'));
  assert.equal(manifest.manifest_version, 3);
  assert.equal(manifest.background.service_worker, 'background/background.js');
  assert.deepEqual(manifest.permissions, ['nativeMessaging', 'activeTab']);
  assert.deepEqual(manifest.host_permissions, ['*://*.youtube.com/*']);
});
