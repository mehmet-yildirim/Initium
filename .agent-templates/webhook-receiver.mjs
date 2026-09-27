/**
 * webhook-receiver.mjs — Jira Server Webhook Receiver
 *
 * Listens for Jira Server webhook events and triggers the autonomous agent loop.
 * See .initium/docs/agent/jira-server-setup.md § 9 for full setup instructions.
 *
 * Usage:
 *   JIRA_WEBHOOK_SECRET=<secret> WEBHOOK_PORT=3001 node .agent-templates/webhook-receiver.mjs
 *
 * Copy this file to .agent/webhook-receiver.mjs for production use.
 * The .agent/ directory is in .gitignore — copy and customize per deployment.
 *
 * Issue summaries and comment bodies are attacker-controlled. They are never passed to a
 * shell or into the agent prompt: the agent is started with execFile (no shell), receives
 * only a validated issue key and an allow-listed command, and reads the issue itself.
 */

import { createServer } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { appendFileSync, mkdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
const PORT    = parseInt(process.env.WEBHOOK_PORT ?? '3001', 10);
const SECRET  = process.env.JIRA_WEBHOOK_SECRET;
const PATH    = process.env.WEBHOOK_PATH ?? '/jira-webhook';
const LOG_DIR = resolve('.agent/audit');

// IP allowlist: add Jira Server IP(s) here for extra safety
// Set to null to skip IP validation and rely on secret only
const ALLOWED_IPS = process.env.JIRA_SERVER_IP
  ? new Set(process.env.JIRA_SERVER_IP.split(',').map(s => s.trim()))
  : null;

// Max body size: 1 MB
const MAX_BODY_BYTES = 1_000_000;

const ISSUE_KEY_PATTERN = /^[A-Z][A-Z0-9_]{0,9}-\d{1,9}$/;
const PHASE_PATTERN = /^[a-z_]{1,32}$/;
const CLAUDE_BIN = process.env.CLAUDE_BIN ?? 'claude';
const LOOP_TIMEOUT_MS = 600_000;
const TRIAGE_TIMEOUT_MS = 300_000;

// Jira event types that trigger agent triage
const TRIGGER_EVENTS = new Set([
  'jira:issue_created',
  'jira:issue_updated',
]);

// Comment body that triggers agent resume (from escalation response)
const AGENT_COMMANDS = [
  'AGENT_RESUME',
  'AGENT_SKIP_TASK',
  'AGENT_REASSIGN',
  'AGENT_ABANDON',
  'AGENT_APPROVE_DESIGN',
  'AGENT_APPROVE_DEPLOY',
  'AGENT_REJECT',
];

// ---------------------------------------------------------------------------
// Startup validation
// ---------------------------------------------------------------------------
if (!SECRET) {
  console.error('[webhook-receiver] FATAL: JIRA_WEBHOOK_SECRET environment variable is not set.');
  console.error('  Generate a secret: node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"');
  process.exit(1);
}

if (!existsSync(LOG_DIR)) {
  mkdirSync(LOG_DIR, { recursive: true });
}

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------
function log(entry) {
  const line = JSON.stringify({
    timestamp: new Date().toISOString(),
    pid: process.pid,
    ...entry,
  });
  const today = new Date().toISOString().split('T')[0];
  appendFileSync(`${LOG_DIR}/${today}-webhooks.jsonl`, line + '\n');
  console.log(line);
}

// ---------------------------------------------------------------------------
// Secret validation (timing-safe comparison)
// ---------------------------------------------------------------------------
function validateSecret(headerValue) {
  if (!headerValue) return false;
  try {
    const expected = Buffer.from(SECRET, 'utf8');
    const received = Buffer.from(headerValue, 'utf8');
    if (expected.length !== received.length) return false;
    return timingSafeEqual(expected, received);
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Agent invocation — argv only, never a shell string
// ---------------------------------------------------------------------------
function runAgent(prompt, timeout) {
  execFileSync(CLAUDE_BIN, ['-p', prompt], {
    cwd: process.cwd(),
    env: process.env,
    stdio: 'inherit',
    timeout,
  });
}

// ---------------------------------------------------------------------------
// Agent command dispatcher — /loop resume reads the human response from the ticket
// ---------------------------------------------------------------------------
function dispatchCommand(command, issueKey, phase) {
  log({ event: 'dispatching_command', command, issueKey, phase });
  const context = phase ? `${command} phase=${phase}` : command;
  try {
    runAgent(`/loop resume ${issueKey} ${context}`, LOOP_TIMEOUT_MS);
    log({ event: 'command_dispatched', command, issueKey, status: 'success' });
  } catch (err) {
    log({ event: 'command_dispatch_error', command, issueKey, error: err.message });
  }
}

// ---------------------------------------------------------------------------
// Triage dispatcher — called when a new issue is created/updated
// ---------------------------------------------------------------------------
function dispatchTriage(issueKey) {
  log({ event: 'dispatching_triage', issueKey });
  try {
    runAgent(`/triage ${issueKey}`, TRIAGE_TIMEOUT_MS);
    log({ event: 'triage_dispatched', issueKey, status: 'success' });
  } catch (err) {
    log({ event: 'triage_dispatch_error', issueKey, error: err.message });
  }
}

// Returns { command, phase } for an allow-listed AGENT_* comment, otherwise null.
function parseAgentCommand(commentBody) {
  const firstLine = commentBody.trim().split('\n', 1)[0];
  const [token, ...rest] = firstLine.split(/\s+/);
  if (!AGENT_COMMANDS.includes(token)) return null;
  const phaseArg = rest.find((part) => part.startsWith('phase='));
  const phase = phaseArg?.slice('phase='.length);
  if (phase !== undefined && !PHASE_PATTERN.test(phase)) return null;
  return { command: token, phase };
}

// ---------------------------------------------------------------------------
// HTTP Server
// ---------------------------------------------------------------------------
const server = createServer((req, res) => {
  const clientIp = req.socket.remoteAddress?.replace('::ffff:', '');

  // ── Path check ──────────────────────────────────────────────────────────
  if (req.method !== 'POST' || req.url !== PATH) {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found');
    return;
  }

  // ── IP allowlist ─────────────────────────────────────────────────────────
  if (ALLOWED_IPS && !ALLOWED_IPS.has(clientIp)) {
    log({ event: 'webhook_rejected', reason: 'ip_not_allowed', clientIp });
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    res.end('Forbidden');
    return;
  }

  // ── Secret validation ────────────────────────────────────────────────────
  const secretHeader = req.headers['x-jira-secret'];
  if (!validateSecret(secretHeader)) {
    log({ event: 'webhook_rejected', reason: 'invalid_secret', clientIp });
    res.writeHead(401, { 'Content-Type': 'text/plain' });
    res.end('Unauthorized');
    return;
  }

  // ── Body collection ──────────────────────────────────────────────────────
  let body = '';
  let bodyBytes = 0;

  req.on('data', (chunk) => {
    bodyBytes += chunk.length;
    if (bodyBytes > MAX_BODY_BYTES) {
      log({ event: 'webhook_rejected', reason: 'body_too_large', clientIp });
      res.writeHead(413);
      res.end('Payload Too Large');
      req.destroy();
      return;
    }
    body += chunk;
  });

  req.on('end', () => {
    let payload;
    try {
      payload = JSON.parse(body);
    } catch {
      log({ event: 'webhook_rejected', reason: 'invalid_json', clientIp });
      res.writeHead(400);
      res.end('Bad Request');
      return;
    }

    const { webhookEvent, issue, comment } = payload;
    const rawKey = typeof issue?.key === 'string' ? issue.key : '';
    const issueKey = ISSUE_KEY_PATTERN.test(rawKey) ? rawKey : null;
    const issueStatus = issue?.fields?.status?.name ?? '';

    log({ event: 'webhook_received', webhookEvent, issueKey, issueStatus, clientIp });
    if (rawKey && !issueKey) {
      log({ event: 'webhook_rejected', reason: 'invalid_issue_key', clientIp });
    }

    // ── Respond immediately (Jira expects fast ack) ───────────────────────
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ received: true, issueKey, webhookEvent }));

    // ── Handle event async (after response sent) ─────────────────────────
    setImmediate(() => {
      // Issue created or updated → triage
      if (TRIGGER_EVENTS.has(webhookEvent) && issueKey) {
        // Skip issues already being processed by the agent
        const skipLabels = ['agent-accepted', 'agent-in-progress', 'agent-done', 'agent-rejected'];
        const labels = (issue?.fields?.labels ?? []).map(l => l.name ?? l);
        if (labels.some(l => skipLabels.includes(l))) {
          log({ event: 'webhook_skipped', reason: 'already_processed', issueKey, labels });
          return;
        }
        dispatchTriage(issueKey);
      }

      // Comment added → check for AGENT_* commands
      if (webhookEvent === 'comment_created' && issueKey && typeof comment?.body === 'string') {
        const parsed = parseAgentCommand(comment.body);
        if (parsed) {
          dispatchCommand(parsed.command, issueKey, parsed.phase);
        }
      }
    });
  });

  req.on('error', (err) => {
    log({ event: 'request_error', error: err.message, clientIp });
  });
});

server.on('error', (err) => {
  log({ event: 'server_error', error: err.message });
  process.exit(1);
});

server.listen(PORT, '0.0.0.0', () => {
  log({
    event: 'webhook_receiver_started',
    port: PORT,
    path: PATH,
    ipAllowlistEnabled: ALLOWED_IPS !== null,
    allowedIps: ALLOWED_IPS ? [...ALLOWED_IPS] : 'all',
  });
  console.log(`\nJira Server webhook receiver ready`);
  console.log(`  Listening : 0.0.0.0:${PORT}${PATH}`);
  console.log(`  Secret    : configured (${SECRET.length} chars)`);
  console.log(`  IP check  : ${ALLOWED_IPS ? [...ALLOWED_IPS].join(', ') : 'disabled'}`);
  console.log(`  Log dir   : ${LOG_DIR}\n`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  log({ event: 'webhook_receiver_stopping', reason: 'SIGTERM' });
  server.close(() => process.exit(0));
});
process.on('SIGINT', () => {
  log({ event: 'webhook_receiver_stopping', reason: 'SIGINT' });
  server.close(() => process.exit(0));
});
