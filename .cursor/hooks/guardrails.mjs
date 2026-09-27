#!/usr/bin/env node
/**
 * guardrails.mjs — Cursor hook adapter for the Initium guardrail policy.
 * Wired in .cursor/hooks.json for beforeShellExecution, beforeReadFile, and preToolUse
 * (Write/Delete). Must always print a valid permission response.
 */

import { readFileSync } from 'node:fs';

const PATH_FIELDS = ['file_path', 'path', 'filePath', 'target_file', 'target_notebook'];
// preToolUse accepts "ask" in its schema but does not enforce it yet.
const ASK_UNSUPPORTED = new Set(['preToolUse', 'beforeReadFile']);

/** @param {Record<string, any>} payload */
function classify(payload) {
  const event = payload.hook_event_name ?? process.argv[2];
  if (event === 'beforeShellExecution') return { event, kind: 'command', targets: [payload.command] };
  if (event === 'beforeReadFile') return { event, kind: 'read', targets: [payload.file_path] };
  const input = typeof payload.tool_input === 'string' ? JSON.parse(payload.tool_input) : payload.tool_input ?? {};
  const targets = PATH_FIELDS.map((field) => input[field]);
  return { event: 'preToolUse', kind: 'write', targets };
}

function respond(permission, message) {
  const body = { permission };
  if (message) Object.assign(body, { user_message: message, agent_message: message });
  process.stdout.write(JSON.stringify(body));
}

async function main() {
  const payload = JSON.parse(readFileSync(0, 'utf8') || '{}');
  const call = classify(payload);
  const { evaluate, loadPolicy } = await import('../../.initium/guardrails/policy.mjs');
  const { recordDecision } = await import('../../.initium/guardrails/audit.mjs');
  const root = payload.workspace_roots?.[0] ?? payload.cwd ?? process.cwd();
  const policy = loadPolicy({ root });
  const outcome = evaluate(policy, call.kind, call.targets);
  const isAskDowngraded = outcome.decision === 'ask' && ASK_UNSUPPORTED.has(call.event);
  recordDecision(policy, isAskDowngraded ? { ...outcome, decision: 'ask-allowed' } : outcome, {
    adapter: 'cursor', tool: call.event, target: call.targets.filter(Boolean).join(' '),
  });
  if (outcome.decision === 'allow' || isAskDowngraded) return respond('allow');
  respond(outcome.decision, `Initium guardrail (${outcome.rule}): ${outcome.reason}`);
}

try {
  await main();
} catch (error) {
  process.stderr.write(`[guardrails] hook error: ${error.message}\n`);
  if (process.env.INITIUM_AGENT_MODE === 'autonomous') respond('deny', 'Initium guardrail hook failed; blocking in autonomous mode.');
  else respond('allow');
}
