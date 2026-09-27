/**
 * Appends non-allow guardrail decisions to .agent/audit/<date>-guardrails.jsonl.
 * Records the rule and a truncated target only — never file contents.
 */

import { appendFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const AUDIT_DIR = '.agent/audit';
const MAX_TARGET_LENGTH = 300;

/**
 * @param {{ root: string, mode: string }} policy
 * @param {{ decision: string, rule: string | null }} result
 * @param {{ adapter: string, tool: string, target: string }} context
 */
export function recordDecision(policy, result, context) {
  if (result.decision === 'allow') return;
  const entry = {
    timestamp: new Date().toISOString(),
    adapter: context.adapter,
    tool: context.tool,
    mode: policy.mode,
    decision: result.decision,
    rule: result.rule,
    target: String(context.target ?? '').slice(0, MAX_TARGET_LENGTH),
  };
  try {
    const dir = join(policy.root, AUDIT_DIR);
    mkdirSync(dir, { recursive: true });
    const day = entry.timestamp.slice(0, 10);
    appendFileSync(join(dir, `${day}-guardrails.jsonl`), `${JSON.stringify(entry)}\n`);
  } catch (error) {
    process.stderr.write(`[guardrails] audit log write failed: ${error.message}\n`);
  }
}
