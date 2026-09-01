import { CarinaBrowserAutomation } from '../../src/index.js';

export function candidate(overrides = {}) {
  let clicked = 0;
  return {
    id: 'candidate-1', text: 'Skip', ariaLabel: '', role: 'button', visible: true, enabled: true,
    observedAt: Date.now(),
    perform: async () => { clicked += 1; },
    element: { isConnected: false },
    clicks: () => clicked,
    ...overrides,
  };
}

export function engine(state = 'ALLOW', captured = [], options = {}) {
  return new CarinaBrowserAutomation({
    policyEngine: { decide: async (proposal) => { captured.push(proposal); return { state }; } },
    ...options,
  });
}

export function context(overrides = {}) {
  return { url: 'https://www.youtube.com/watch?v=1', pageText: 'watch video', mediaPlaying: true, overlayVisible: false, ...overrides };
}
