/**
 * post-write.mjs — PostToolUse hook for Write tool
 *
 * Runs after every file write. Appends an entry to the agent audit log
 * and optionally triggers a fast lint check on the written file.
 *
 * Claude Code passes tool input/output via stdin as JSON.
 */

import { readFileSync, appendFileSync, existsSync, mkdirSync } from 'node:fs';
import { resolve, extname } from 'node:path';

const AUDIT_DIR = '.agent/audit';
const today = new Date().toISOString().split('T')[0];
const auditFile = `${AUDIT_DIR}/${today}-writes.jsonl`;

// Read tool context from stdin
let toolContext = {};
try {
  const raw = readFileSync('/dev/stdin', 'utf8').trim();
  if (raw) toolContext = JSON.parse(raw);
} catch {
  // stdin may not always be present; proceed silently
}

const filePath = toolContext?.tool_input?.file_path ?? 'unknown';
const ext = extname(filePath);

// Ensure audit dir exists
if (!existsSync(AUDIT_DIR)) {
  mkdirSync(AUDIT_DIR, { recursive: true });
}

// Write audit entry
const entry = {
  timestamp: new Date().toISOString(),
  hook: 'PostToolUse:Write',
  file: filePath,
  linesWritten: (toolContext?.tool_input?.content ?? '').split('\n').length,
};
appendFileSync(auditFile, JSON.stringify(entry) + '\n');

// Safety check: warn if writing to a protected path
const PROTECTED_PATTERNS = [
  /^agent\.config\.yaml$/,
  /^AGENTS\.md$/,
  /^CLAUDE\.md$/,
  /^\.github\/workflows\//,
  /\.env$/,
  /\.pem$/,
  /\.key$/,
];

const relative = filePath.replace(process.cwd() + '/', '');
for (const pattern of PROTECTED_PATTERNS) {
  if (pattern.test(relative)) {
    process.stderr.write(
      `[post-write] ⚠️  PROTECTED FILE written: ${relative}\n` +
      `  If this was unintentional, review the change before committing.\n`
    );
    break;
  }
}
