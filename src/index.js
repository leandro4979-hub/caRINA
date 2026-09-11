import { DEFAULTS } from './config/defaults.js';
import { extractContext } from './core/context.js';
import { inferIntent } from './core/intent.js';
import { scoreCandidate } from './core/scorer.js';
import { classifySafety } from './core/safety.js';
import { buildPolicyProposal, evaluatePolicy, PolicyDecision } from './core/policy.js';
import { ActionQueue } from './core/queue.js';
import { executeCandidate } from './core/executor.js';
import { verifyResult } from './core/verifier.js';
import { EventBus } from './core/events.js';
import { StructuredLogger } from './core/logger.js';
import { getPluginForHost } from './plugins/registry.js';

export class CarinaBrowserAutomation {
  constructor({ policyEngine, queue = new ActionQueue(), events = new EventBus(), logger = new StructuredLogger(), config = {} } = {}) {
    this.policyEngine = policyEngine;
    this.queue = queue;
    this.events = events;
    this.logger = logger;
    this.config = Object.freeze({ ...DEFAULTS, ...config });
  }

  discover(rawContext) {
    const context = extractContext(rawContext);
    const plugin = getPluginForHost(context.host);
    if (!plugin || !plugin.detect(context)) return [];
    return plugin.candidates(context).map((candidate) => ({ candidate, plugin, rawContext }));
  }

  async evaluateCandidate({ candidate, rawContext, plugin: explicitPlugin }) {
    const context = extractContext(rawContext);
    const plugin = explicitPlugin ?? getPluginForHost(context.host);
    if (!plugin || !plugin.detect(context)) return { status: 'DENIED', reason: 'NO_PLUGIN' };

    const intent = inferIntent(candidate, context);
    const score = scoreCandidate(candidate, context, plugin.signals(context, candidate));
    const safety = classifySafety(candidate, context);

    this.logger.log('candidate_scored', { candidateId: candidate.id, pluginId: plugin.id, confidence: score.confidence, reasons: score.reasons });
    this.events.emit('buttonScored', { candidateId: candidate.id, confidence: score.confidence });

    if (safety.sensitive) return { status: 'DENIED', reason: 'SENSITIVE_CONTEXT' };
    if (!intent) return { status: 'DENIED', reason: 'UNSUPPORTED_INTENT' };
    if (score.confidence < this.config.minimumConfidence) return { status: 'DENIED', reason: 'LOW_CONFIDENCE' };
    if (!candidate.observedAt || Date.now() - candidate.observedAt > this.config.staleCandidateMs) {
      return { status: 'DENIED', reason: 'STALE_CANDIDATE' };
    }

    const proposal = buildPolicyProposal({ candidate, context, intent, score, safety, pluginId: plugin.id });
    this.logger.log('policy_proposed', proposal);
    this.events.emit('actionProposed', proposal);
    const decision = await evaluatePolicy(this.policyEngine, proposal);
    this.logger.log('policy_decision', { candidateId: candidate.id, state: decision.state, reason: decision.reason });

    if (decision.state === PolicyDecision.DENY) return { status: 'DENIED', reason: decision.reason ?? 'POLICY_DENY' };
    if (decision.state === PolicyDecision.APPROVAL_REQUIRED) return { status: 'APPROVAL_REQUIRED', reason: decision.reason ?? null };
    if (decision.state !== PolicyDecision.ALLOW) return { status: 'DENIED', reason: 'UNKNOWN_POLICY_STATE' };

    return this.queue.enqueue(candidate, async (actionId) => {
      candidate.intent = intent;
      await executeCandidate(candidate);
      this.logger.log('action_executed', { actionId, candidateId: candidate.id, pluginId: plugin.id, intent });
      this.events.emit('actionExecuted', { actionId, candidateId: candidate.id, intent });
      const verification = await verifyResult(plugin, candidate, context);
      this.logger.log('action_verified', { actionId, candidateId: candidate.id, verification });
      this.events.emit('actionVerified', { actionId, candidateId: candidate.id, verification });
      return {
        status: verification.passed ? 'VERIFIED' : 'FAILED_VERIFICATION',
        candidateId: candidate.id,
        plugin: plugin.id,
        intent,
        verification,
      };
    }, { maxTransientRetries: this.config.maxTransientRetries });
  }
}
