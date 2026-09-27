#!/usr/bin/env node
/**
 * Git pre-commit guardrail — the last line of defense for every agent and human.
 *
 * - Secret files and secret-looking tokens in added lines: blocked in every mode.
 * - safety.protected_paths and guardrail files: blocked in autonomous mode.
 * - safety.max_files_per_pr / max_lines_per_pr (branch vs. base): warning when
 *   interactive, blocked in autonomous mode.
 *
 * INITIUM_GUARDRAILS=warn turns blocks into warnings for humans; it is ignored in
 * autonomous mode. Add "guardrails:allow" to a line to suppress a token false positive.
 */

import { execFileSync } from 'node:child_process';

import { matchesAny } from './glob.mjs';
import { GUARDRAIL_FILES, MODE, isSecretFile, loadPolicy } from './policy.mjs';
import { ALLOW_MARKER, findSecretToken, parseAddedLines } from './secrets.mjs';

const EXIT_BLOCK = 1;
const MAX_GIT_OUTPUT_BYTES = 64 * 1024 * 1024;
const BASE_CANDIDATES = ['origin/main', 'main', 'origin/master', 'master'];

function git(args, root) {
  return execFileSync('git', args, { cwd: root, encoding: 'utf8', maxBuffer: MAX_GIT_OUTPUT_BYTES, stdio: ['ignore', 'pipe', 'ignore'] });
}

function findBase(root) {
  const candidates = [process.env.INITIUM_BASE_BRANCH, ...BASE_CANDIDATES].filter(Boolean);
  for (const ref of candidates) {
    try {
      return git(['merge-base', 'HEAD', ref], root).trim();
    } catch {
      // Ref missing or unrelated history — try the next candidate.
    }
  }
  return null;
}

/** Files and lines the branch would change if this commit lands. */
function measureBranchSize(root) {
  const base = findBase(root);
  const numstat = git(['diff', '--cached', '--numstat', ...(base ? [base] : [])], root);
  let lines = 0;
  let files = 0;
  for (const row of numstat.split('\n').filter(Boolean)) {
    const [addedCount, deletedCount] = row.split('\t');
    files++;
    lines += (Number(addedCount) || 0) + (Number(deletedCount) || 0);
  }
  return { files, lines, base };
}

/** @param {ReturnType<typeof loadPolicy>} policy @param {string[]} stagedFiles */
function collectFindings(policy, stagedFiles) {
  const blocks = [];
  const warnings = [];
  const isAutonomous = policy.mode === MODE.AUTONOMOUS;
  for (const file of stagedFiles) {
    const secret = isSecretFile(policy, file);
    if (secret) blocks.push(`${file}: secret file (${secret}) must not be committed.`);
    const guarded = matchesAny(file, GUARDRAIL_FILES) ?? matchesAny(file, policy.protectedPaths);
    if (guarded && isAutonomous) blocks.push(`${file}: protected path (${guarded}) cannot be changed by an autonomous agent.`);
  }
  const diff = git(['diff', '--cached', '-U0', '--no-color', '--no-ext-diff', '--diff-filter=ACMR'], policy.root);
  for (const { file, line, text } of parseAddedLines(diff)) {
    const token = findSecretToken(text);
    if (token) blocks.push(`${file}:${line}: looks like a ${token}. Remove it, or add "${ALLOW_MARKER}" if it is a false positive.`);
  }
  const size = measureBranchSize(policy.root);
  const sizeIssues = [];
  if (policy.maxFilesPerPr && size.files > policy.maxFilesPerPr) sizeIssues.push(`${size.files} files (max ${policy.maxFilesPerPr})`);
  if (policy.maxLinesPerPr && size.lines > policy.maxLinesPerPr) sizeIssues.push(`${size.lines} lines (max ${policy.maxLinesPerPr})`);
  if (sizeIssues.length > 0) {
    const message = `branch exceeds the PR size limit: ${sizeIssues.join(', ')} vs ${size.base ? size.base.slice(0, 8) : 'staged changes'}. Split the work.`;
    (isAutonomous ? blocks : warnings).push(message);
  }
  return { blocks, warnings };
}

function report(prefix, messages) {
  for (const message of messages) process.stderr.write(`[guardrails] ${prefix}: ${message}\n`);
}

function main() {
  const root = git(['rev-parse', '--show-toplevel'], process.cwd()).trim();
  const policy = loadPolicy({ root });
  const staged = git(['diff', '--cached', '--name-only', '-z', '--diff-filter=ACMR'], root).split('\0').filter(Boolean);
  if (staged.length === 0) return 0;
  const { blocks, warnings } = collectFindings(policy, staged);
  report('warning', warnings);
  if (blocks.length === 0) return 0;
  const isHumanOverride = process.env.INITIUM_GUARDRAILS === 'warn' && policy.mode !== MODE.AUTONOMOUS;
  if (isHumanOverride) {
    report('override (INITIUM_GUARDRAILS=warn)', blocks);
    return 0;
  }
  report('blocked', blocks);
  process.stderr.write('[guardrails] Commit rejected. See .initium/docs/guardrails.md.\n');
  return EXIT_BLOCK;
}

try {
  process.exitCode = main();
} catch (error) {
  process.stderr.write(`[guardrails] pre-commit check failed: ${error.message}\n`);
  process.exitCode = process.env.INITIUM_AGENT_MODE === MODE.AUTONOMOUS ? EXIT_BLOCK : 0;
}
