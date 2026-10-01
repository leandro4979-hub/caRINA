import test from 'node:test';
import assert from 'node:assert/strict';
import { registerPlugin, getPluginForHost, clearRegistry } from '../../src/plugins/registry.js';
import { youtubePlugin } from '../../src/plugins/youtube.js';
import { genericPlugin } from '../../src/plugins/generic.js';

test.beforeEach(() => clearRegistry());

test('plugin registry strips execution authority and freezes facade', () => {
  const registered = registerPlugin({ ...youtubePlugin, execute() { throw new Error('must never run'); } });
  assert.equal('execute' in registered, false);
  assert.equal(Object.isFrozen(registered), true);
});

test('plugin candidate contract contains no executable closure', () => {
  const node = {
    textContent: 'Skip', hidden: false, disabled: false, dataset: {}, tagName: 'BUTTON',
    getAttribute() { return null; }, click() {},
  };
  const plugin = registerPlugin(youtubePlugin);
  const [found] = plugin.candidates({ document: { querySelectorAll: () => [node] } });
  assert.equal(found.proposedAction, 'click');
  assert.equal('perform' in found, false);
});

test('registry rejects invalid methods and duplicate IDs', () => {
  assert.throws(() => registerPlugin({ id: 'bad', hosts: ['example.com'], detect: 'yes' }), /invalid field/);
  registerPlugin(youtubePlugin);
  assert.throws(() => registerPlugin(youtubePlugin), /duplicate id/);
});

test('site-specific plugin wins over generic fallback', () => {
  registerPlugin(genericPlugin);
  registerPlugin(youtubePlugin);
  assert.equal(getPluginForHost('www.youtube.com').id, 'youtube');
  assert.equal(getPluginForHost('example.com').id, 'generic');
});

test('registry exposes only evidence hooks', () => {
  const registered = registerPlugin(youtubePlugin);
  assert.deepEqual(Object.keys(registered).sort(), ['candidates', 'detect', 'hosts', 'id', 'signals', 'verify'].sort());
});
