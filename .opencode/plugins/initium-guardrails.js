/**
 * initium-guardrails.js — OpenCode plugin applying the Initium guardrail policy
 * (.initium/guardrails/) before bash, read, and write/edit tool calls.
 * Throwing from tool.execute.before blocks the call; OpenCode has no "ask" here,
 * so "ask" decisions are allowed interactively and denied in autonomous mode.
 */

import { recordDecision } from '../../.initium/guardrails/audit.mjs';
import { evaluate, loadPolicy } from '../../.initium/guardrails/policy.mjs';

const READ_TOOLS = new Set(['read', 'grep', 'glob', 'list']);
const WRITE_TOOLS = new Set(['write', 'edit', 'multiedit']);
const PATCH_FILE_LINE = /^\*\*\* (?:Add|Update|Delete) File: (.+)$/gm;

/** @param {string} tool @param {Record<string, any>} args */
function classify(tool, args) {
  if (tool === 'bash') return { kind: 'command', targets: [args.command] };
  const path = args.filePath ?? args.path;
  if (READ_TOOLS.has(tool)) return { kind: 'read', targets: [path] };
  if (WRITE_TOOLS.has(tool)) return { kind: 'write', targets: [path] };
  if (tool === 'patch' || tool === 'apply_patch') {
    const text = String(args.patchText ?? args.patch ?? '');
    return { kind: 'write', targets: [...text.matchAll(PATCH_FILE_LINE)].map((match) => match[1].trim()) };
  }
  return null;
}

export const InitiumGuardrails = async ({ directory, worktree }) => ({
  'tool.execute.before': async (input, output) => {
    const call = classify(input.tool, output.args ?? {});
    if (!call) return;
    const policy = loadPolicy({ root: worktree || directory });
    const outcome = evaluate(policy, call.kind, call.targets);
    if (outcome.decision === 'allow') return;
    const isAskAllowed = outcome.decision === 'ask';
    recordDecision(policy, isAskAllowed ? { ...outcome, decision: 'ask-allowed' } : outcome, {
      adapter: 'opencode', tool: input.tool, target: call.targets.filter(Boolean).join(' '),
    });
    if (isAskAllowed) return;
    throw new Error(`Initium guardrail (${outcome.rule}): ${outcome.reason}`);
  },
});
