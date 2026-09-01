export async function verifyResult(plugin, candidate, context) {
  try {
    const passed = Boolean(await plugin.verify(candidate, context));
    return Object.freeze({ passed, reason: passed ? 'EXPECTED_STATE_OBSERVED' : 'EXPECTED_STATE_NOT_OBSERVED' });
  } catch {
    return Object.freeze({ passed: false, reason: 'VERIFICATION_ERROR' });
  }
}
