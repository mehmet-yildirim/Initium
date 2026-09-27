/**
 * audit-log.mjs — PostToolUse hook for Bash tool
 *
 * Records every bash command the agent runs into the daily audit log, tagged with
 * the guardrail verdict (.initium/guardrails/). Blocking happens earlier in the
 * PreToolUse hook (guardrails.mjs); a non-allow verdict here means a human approved it.
 */

import { appendFileSync, existsSync, mkdirSync, readFileSync } from 'node:fs';

import { checkCommand, loadPolicy } from '../../.initium/guardrails/policy.mjs';

const AUDIT_DIR = '.agent/audit';
const MAX_COMMAND_LENGTH = 500;
const today = new Date().toISOString().split('T')[0];
const auditFile = `${AUDIT_DIR}/${today}-commands.jsonl`;

let toolContext = {};
try {
  const raw = readFileSync(0, 'utf8').trim();
  if (raw) toolContext = JSON.parse(raw);
} catch (error) {
  process.stderr.write(`[audit-log] could not parse hook input: ${error.message}\n`);
}

const command = toolContext?.tool_input?.command ?? '';
const exitCode = toolContext?.tool_response?.exit_code ?? null;
const verdict = checkCommand(loadPolicy({ root: process.env.CLAUDE_PROJECT_DIR || process.cwd() }), command);

if (!existsSync(AUDIT_DIR)) {
  mkdirSync(AUDIT_DIR, { recursive: true });
}

if (verdict.decision !== 'allow') {
  process.stderr.write(
    `[audit-log] guardrail rule "${verdict.rule}" matched an executed command: ${command}\n` +
    `  ${verdict.reason}\n` +
    `  It ran after approval — review it and revert if unintentional.\n`
  );
}

const entry = {
  timestamp: new Date().toISOString(),
  hook: 'PostToolUse:Bash',
  command: command.slice(0, MAX_COMMAND_LENGTH),
  exitCode,
  guardrail: verdict.decision === 'allow' ? null : { decision: verdict.decision, rule: verdict.rule },
};
appendFileSync(auditFile, JSON.stringify(entry) + '\n');
