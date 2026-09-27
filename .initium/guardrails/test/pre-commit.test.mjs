import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, beforeEach, describe, it } from 'node:test';

const PROJECT_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const CONFIG = `safety:
  protected_paths:
    - "AGENTS.md"
  max_files_per_pr: 3
  max_lines_per_pr: 1000
`;

const sandbox = mkdtempSync(join(tmpdir(), 'initium-precommit-'));
after(() => rmSync(sandbox, { recursive: true, force: true }));
let repo;
let counter = 0;

function git(...args) {
  const run = spawnSync('git', args, { cwd: repo, encoding: 'utf8' });
  assert.equal(run.status, 0, run.stderr);
  return run.stdout;
}

/** Stages files and runs .githooks/pre-commit exactly as git would. */
function commitAttempt(files, env = {}) {
  for (const [path, content] of Object.entries(files)) {
    mkdirSync(dirname(join(repo, path)), { recursive: true });
    writeFileSync(join(repo, path), content);
    git('add', '--', path);
  }
  const cleanEnv = { ...process.env, INITIUM_AGENT_MODE: '', INITIUM_GUARDRAILS: '', ...env };
  return spawnSync('sh', ['.githooks/pre-commit'], { cwd: repo, encoding: 'utf8', env: cleanEnv });
}

beforeEach(() => {
  repo = join(sandbox, `repo-${counter++}`);
  mkdirSync(repo);
  git('init', '-q', '-b', 'main');
  git('config', 'user.email', 'test@example.com');
  git('config', 'user.name', 'Test');
  cpSync(join(PROJECT_ROOT, '.initium/guardrails'), join(repo, '.initium/guardrails'), { recursive: true });
  cpSync(join(PROJECT_ROOT, '.githooks'), join(repo, '.githooks'), { recursive: true });
  writeFileSync(join(repo, 'agent.config.yaml'), CONFIG);
  git('add', '.');
  git('commit', '-q', '-m', 'init');
  git('checkout', '-q', '-b', 'feat/x');
});

describe('pre-commit guardrail', () => {
  it('passes ordinary changes', () => {
    assert.equal(commitAttempt({ 'src/a.ts': 'export const a = 1;\n' }).status, 0);
  });

  it('blocks secret files in every mode', () => {
    const run = commitAttempt({ '.env': 'X=1\n' });
    assert.equal(run.status, 1);
    assert.match(run.stderr, /secret file/);
  });

  it('allows example env files', () => {
    assert.equal(commitAttempt({ '.env.example': 'X=\n' }).status, 0);
  });

  it('blocks secret tokens in added lines unless suppressed', () => {
    const token = 'ghp_' + 'aB3dE5gH7jK9'.repeat(3);
    const blocked = commitAttempt({ 'src/config.ts': `const t = "${token}";\n` });
    assert.equal(blocked.status, 1);
    assert.match(blocked.stderr, /src\/config\.ts:1: looks like a GitHub token/);
    const allowed = commitAttempt({ 'src/config.ts': `const t = "${token}"; // guardrails:allow\n` });
    assert.equal(allowed.status, 0);
  });

  it('blocks protected paths only in autonomous mode', () => {
    assert.equal(commitAttempt({ 'AGENTS.md': '# rules\n' }).status, 0);
    const run = commitAttempt({ 'AGENTS.md': '# changed\n' }, { INITIUM_AGENT_MODE: 'autonomous' });
    assert.equal(run.status, 1);
    assert.match(run.stderr, /protected path/);
  });

  it('warns interactively and blocks autonomously above the PR size limit', () => {
    const files = { 'a.txt': '1\n', 'b.txt': '2\n', 'c.txt': '3\n', 'd.txt': '4\n' };
    const interactive = commitAttempt(files);
    assert.equal(interactive.status, 0);
    assert.match(interactive.stderr, /warning: branch exceeds the PR size limit: 4 files/);
    assert.equal(commitAttempt({}, { INITIUM_AGENT_MODE: 'autonomous' }).status, 1);
  });

  it('lets humans downgrade blocks with INITIUM_GUARDRAILS=warn, but not agents', () => {
    assert.equal(commitAttempt({ '.env': 'X=1\n' }, { INITIUM_GUARDRAILS: 'warn' }).status, 0);
    assert.equal(commitAttempt({}, { INITIUM_GUARDRAILS: 'warn', INITIUM_AGENT_MODE: 'autonomous' }).status, 1);
  });

  it('chains a pre-existing .git/hooks/pre-commit', () => {
    const legacy = join(repo, '.git/hooks/pre-commit');
    writeFileSync(legacy, '#!/bin/sh\necho legacy-ran >&2\nexit 3\n');
    chmodSync(legacy, 0o755);
    const run = commitAttempt({ 'src/b.ts': 'export {};\n' });
    assert.equal(run.status, 3);
    assert.match(run.stderr, /legacy-ran/);
  });
});
