#!/usr/bin/env node
/**
 * guardrails.mjs — Claude Code PreToolUse hook.
 * Applies the Initium guardrail policy (.initium/guardrails/) before Bash, file reads,
 * and file writes. Allowed calls produce no output so normal permission rules still apply.
 */

import { readFileSync } from 'node:fs';

const EXIT_BLOCK = 2;
const READ_TOOLS = new Set(['Read', 'Grep', 'Glob', 'LS']);
const WRITE_TOOLS = new Set(['Write', 'Edit', 'MultiEdit', 'NotebookEdit']);

/** @param {string} toolName @param {Record<string, unknown>} input */
function classify(toolName, input) {
  if (toolName === 'Bash') return { kind: 'command', targets: [input.command] };
  const path = input.file_path ?? input.notebook_path ?? input.path;
  if (READ_TOOLS.has(toolName)) return { kind: 'read', targets: [path] };
  if (WRITE_TOOLS.has(toolName)) return { kind: 'write', targets: [path] };
  return null;
}

async function main() {
  const payload = JSON.parse(readFileSync(0, 'utf8') || '{}');
  const call = classify(payload.tool_name ?? '', payload.tool_input ?? {});
  if (!call) return;
  const { evaluate, loadPolicy } = await import('../../.initium/guardrails/policy.mjs');
  const { recordDecision } = await import('../../.initium/guardrails/audit.mjs');
  const policy = loadPolicy({ root: process.env.CLAUDE_PROJECT_DIR || payload.cwd || process.cwd() });
  const outcome = evaluate(policy, call.kind, call.targets);
  if (outcome.decision === 'allow') return;
  recordDecision(policy, outcome, { adapter: 'claude-code', tool: payload.tool_name, target: call.targets.join(' ') });
  const response = {
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: outcome.decision,
      permissionDecisionReason: `Initium guardrail (${outcome.rule}): ${outcome.reason}`,
    },
  };
  process.stdout.write(JSON.stringify(response));
}

try {
  await main();
} catch (error) {
  // Fail closed only when nobody is watching; interactive sessions keep working.
  process.stderr.write(`[guardrails] hook error: ${error.message}\n`);
  if (process.env.INITIUM_AGENT_MODE === 'autonomous') process.exit(EXIT_BLOCK);
}
