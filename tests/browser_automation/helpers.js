import { CarinaBrowserAutomation } from '../../src/index.js';

export function candidate(overrides = {}) {
  let clicked = 0;
  const element = {
    isConnected: false,
    click() { clicked += 1; },
  };
  return {
    id: 'candidate-1',
    text: 'Skip',
    ariaLabel: '',
    role: 'button',
    visible: true,
    enabled: true,
    observedAt: Date.now(),
    proposedAction: 'click',
    element,
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
