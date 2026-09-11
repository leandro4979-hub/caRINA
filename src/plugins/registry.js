const activePlugins = new Map();

function normalizeHosts(hosts) {
  const values = Array.isArray(hosts) ? hosts : [hosts];
  if (values.length === 0 || values.some((host) => typeof host !== 'string' || host.trim() === '')) {
    throw new Error("Plugin validation failed: 'hosts' must contain non-empty strings");
  }
  return Object.freeze(values.map((host) => host.trim().toLowerCase()));
}

export function registerPlugin(plugin) {
  if (!plugin || typeof plugin !== 'object') {
    throw new Error('Plugin validation failed: plugin must be an object');
  }
  if (typeof plugin.id !== 'string' || plugin.id.trim() === '') {
    throw new Error("Plugin validation failed: Missing or invalid field 'id'");
  }
  for (const field of ['detect', 'candidates', 'signals', 'verify']) {
    if (typeof plugin[field] !== 'function') {
      throw new Error(`Plugin validation failed: Missing or invalid field '${field}'`);
    }
  }
  if (activePlugins.has(plugin.id)) {
    throw new Error(`Plugin validation failed: duplicate id '${plugin.id}'`);
  }

  const registered = Object.freeze({
    id: plugin.id.trim(),
    hosts: normalizeHosts(plugin.hosts),
    detect: plugin.detect,
    candidates: plugin.candidates,
    signals: plugin.signals,
    verify: plugin.verify,
  });

  activePlugins.set(registered.id, registered);
  return registered;
}

export function getPluginForHost(hostname) {
  if (typeof hostname !== 'string' || hostname.trim() === '') return null;
  const normalized = hostname.trim().toLowerCase();
  let fallback = null;

  for (const plugin of activePlugins.values()) {
    if (plugin.hosts.includes('*')) {
      fallback ??= plugin;
      continue;
    }
    if (plugin.hosts.some((host) => normalized === host || normalized.endsWith(`.${host}`))) {
      return plugin;
    }
  }
  return fallback;
}

export function getRegisteredPlugins() {
  return Object.freeze([...activePlugins.values()]);
}

export function clearRegistry() {
  activePlugins.clear();
}
