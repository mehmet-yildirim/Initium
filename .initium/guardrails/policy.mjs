/**
 * Initium guardrail policy — one decision engine for every agent adapter
 * (Claude Code, Cursor, OpenCode) and the git pre-commit hook.
 *
 * Rules = built-in baseline (always on) + `safety:` in agent.config.yaml.
 * Mode  = "autonomous" when INITIUM_AGENT_MODE=autonomous (Docker agent, webhook,
 *         systemd units), otherwise "interactive". Autonomous mode turns "ask" into "deny".
 */

import { existsSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { isAbsolute, join, relative, resolve, sep } from 'node:path';

import { readSafetyConfig } from './config.mjs';
import { matchesAny } from './glob.mjs';
import { analyzeCommand, normalizeCommand } from './shell.mjs';

export const DECISION = Object.freeze({ ALLOW: 'allow', ASK: 'ask', DENY: 'deny' });
export const MODE = Object.freeze({ AUTONOMOUS: 'autonomous', INTERACTIVE: 'interactive' });

const ALLOW_RESULT = Object.freeze({ decision: DECISION.ALLOW, rule: null, reason: null });

/** Files whose contents must never reach a model or a commit. */
export const SECRET_FILE_PATTERNS = [
  '.env', '.env.*', '*.pem', '*.key', '*.p12', '*.pfx', '*.jks', '*.keystore',
  'id_rsa', 'id_rsa.*', 'id_ed25519', 'id_ed25519.*', 'id_ecdsa', 'id_ecdsa.*',
  '**/.ssh/**', '**/.aws/credentials', '**/.docker/config.json', '.netrc', '.pgpass',
  '**/secrets/**', 'service-account*.json', '*-service-account.json',
  '*.tfvars', 'kubeconfig', '*.kubeconfig',
];
const SECRET_FILE_EXCEPTIONS = [
  '.env.example', '.env.sample', '.env.template', '.env.dist', '*.pub', '*.tfvars.example',
];

/** Guardrail and policy files: agents may not edit them unattended. */
export const GUARDRAIL_FILES = [
  '.initium/guardrails/**', '.githooks/**', '.claude/settings.json', '.claude/hooks/guardrails.mjs',
  '.cursor/hooks.json', '.cursor/hooks/**', '.opencode/plugins/initium-guardrails.js', 'agent.config.yaml',
];

const HOME_PREFIX = /^(~|\$HOME|\$\{HOME\})(?=\/|$)/;
const SAFE_DEVICES = /^\/dev\/(null|stdout|stderr|tty|fd\/\d+)$/;
const PROTECTED_BRANCHES = /^(\+?(refs\/heads\/)?)(main|master|develop|release\/.+)$/;
const INTERPRETERS = new Set(['sh', 'bash', 'zsh', 'dash', 'ksh', 'fish', 'python', 'python3', 'node', 'perl', 'ruby']);
const DOWNLOADERS = new Set(['curl', 'wget']);
const DOWNLOAD_SUBSTITUTION = /(\$\(|`|<\()\s*(curl|wget)\b/;
const DROP_DATABASE = /\bDROP\s+DATABASE\b/i;
const SECRET_ENV_ECHO = /\$\{?[A-Za-z_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|PRIVATE_KEY|CREDENTIALS?)[A-Za-z_]*\}?/i;
// Commit, PR, and release text is prose, not a command — text rules skip it.
const MESSAGE_PROGRAMS = new Set(['git', 'gh', 'glab']);
const MESSAGE_FLAG = /^(-[a-zA-Z]*[mbt]|--message|--body|--title|--notes|--subject)$/;
const MESSAGE_ASSIGNMENT = /^--(message|body|title|notes|subject)=/;
const READERS = new Set([
  'cat', 'less', 'more', 'head', 'tail', 'bat', 'grep', 'egrep', 'fgrep', 'rg', 'ag', 'awk', 'sed',
  'nl', 'od', 'xxd', 'hexdump', 'strings', 'base64', 'source', '.', 'diff', 'cmp', 'vim', 'vi',
  'nano', 'code', 'cp', 'scp', 'rsync', 'curl', 'wget', 'tar', 'zip', 'gpg', 'openssl', 'jq', 'yq',
]);
const WRITERS = new Set(['rm', 'mv', 'cp', 'tee', 'truncate', 'chmod', 'chown', 'ln', 'unlink', 'shred']);

/**
 * @param {{ root?: string, env?: Record<string, string | undefined> }} [options]
 */
export function loadPolicy({ root = process.cwd(), env = process.env } = {}) {
  const safety = readSafetyConfig(root);
  const list = (value) => (Array.isArray(value) ? value.map(String) : []);
  return {
    root: resolve(root),
    mode: env.INITIUM_AGENT_MODE === MODE.AUTONOMOUS ? MODE.AUTONOMOUS : MODE.INTERACTIVE,
    protectedPaths: list(safety.protected_paths),
    forbiddenFilePatterns: list(safety.forbidden_file_patterns),
    forbiddenCommands: list(safety.forbidden_commands),
    maxFilesPerPr: Number(safety.max_files_per_pr) || null,
    maxLinesPerPr: Number(safety.max_lines_per_pr) || null,
    killSwitchFile: typeof safety.kill_switch_file === 'string' ? safety.kill_switch_file : '.agent/STOP',
  };
}

function result(decision, rule, reason) {
  return { decision, rule, reason };
}

/** "ask" becomes "deny" when nobody is watching. */
function escalate(policy, rule, reason) {
  const decision = policy.mode === MODE.AUTONOMOUS ? DECISION.DENY : DECISION.ASK;
  return result(decision, rule, reason);
}

/** @param {ReturnType<typeof loadPolicy>} policy @param {string} filePath */
export function toProjectPath(policy, filePath) {
  const expanded = filePath.replace(HOME_PREFIX, homedir());
  const absolute = isAbsolute(expanded) ? resolve(expanded) : resolve(policy.root, expanded);
  const rel = relative(policy.root, absolute);
  const isInside = rel !== '' && !rel.startsWith('..') && !isAbsolute(rel);
  return { absolute, relative: (isInside ? rel : absolute).split(sep).join('/'), isInside };
}

/** @param {ReturnType<typeof loadPolicy>} policy @param {string} filePath */
export function isSecretFile(policy, filePath) {
  const { relative: rel } = toProjectPath(policy, filePath);
  if (matchesAny(rel, SECRET_FILE_EXCEPTIONS)) return null;
  return matchesAny(rel, SECRET_FILE_PATTERNS) ?? matchesAny(rel, policy.forbiddenFilePatterns);
}

function isKillSwitchActive(policy) {
  return policy.mode === MODE.AUTONOMOUS && existsSync(join(policy.root, policy.killSwitchFile));
}

/** @param {ReturnType<typeof loadPolicy>} policy @param {string} filePath */
export function checkRead(policy, filePath) {
  const secret = isSecretFile(policy, filePath);
  if (secret) return result(DECISION.DENY, 'secret-file', `Reading secret files is blocked (${secret}).`);
  return ALLOW_RESULT;
}

/** @param {ReturnType<typeof loadPolicy>} policy @param {string} filePath */
export function checkWrite(policy, filePath) {
  if (isKillSwitchActive(policy)) {
    return result(DECISION.DENY, 'kill-switch', `${policy.killSwitchFile} exists — the agent is stopped.`);
  }
  const target = toProjectPath(policy, filePath);
  if (target.isInside && /^\.git(\/|$)/.test(target.relative)) {
    return result(DECISION.DENY, 'git-internals', 'Writing inside .git/ is blocked.');
  }
  const secret = isSecretFile(policy, filePath);
  if (secret) return escalate(policy, 'secret-file', `Overwriting a secret file (${secret}) can destroy credentials.`);
  if (!target.isInside) {
    if (SAFE_DEVICES.test(target.absolute)) return ALLOW_RESULT;
    const isTemp = target.absolute.startsWith(resolve(tmpdir())) || target.absolute.startsWith('/tmp/');
    if (isTemp || policy.mode === MODE.INTERACTIVE) return ALLOW_RESULT;
    return result(DECISION.DENY, 'outside-project', `Writing outside the project is blocked: ${target.absolute}`);
  }
  const guardrail = matchesAny(target.relative, GUARDRAIL_FILES);
  if (guardrail) return escalate(policy, 'guardrail-file', `${target.relative} defines guardrails or agent policy.`);
  const protectedPath = matchesAny(target.relative, policy.protectedPaths);
  if (protectedPath) return escalate(policy, 'protected-path', `${target.relative} matches safety.protected_paths (${protectedPath}).`);
  return ALLOW_RESULT;
}

/** @param {string[]} tokens */
function isCatastrophicRm(tokens) {
  if (tokens[0] !== 'rm') return false;
  const flags = tokens.filter((token) => token.startsWith('-')).join('');
  const isRecursive = /-[a-zA-Z]*[rR]|--recursive/.test(flags);
  if (!isRecursive) return false;
  if (tokens.includes('--no-preserve-root')) return true;
  const dangerous = new Set(['/', '/*', '~', '~/', '~/*', '$HOME', '${HOME}', '$HOME/', '.', './', '*', './*', '..', '../', '../*']);
  return tokens.slice(1).some((token) => !token.startsWith('-') && dangerous.has(token));
}

const GIT_OPTIONS_WITH_VALUE = new Set(['-c', '-C', '--git-dir', '--work-tree', '--namespace']);

/**
 * Splits `git [global options] <subcommand> [args]`.
 * @param {string[]} tokens
 * @returns {{ subcommand: string | null, rest: string[] }}
 */
function parseGit(tokens) {
  if (tokens[0] !== 'git') return { subcommand: null, rest: [] };
  let index = 1;
  while (index < tokens.length && tokens[index].startsWith('-')) {
    index += GIT_OPTIONS_WITH_VALUE.has(tokens[index]) ? 2 : 1;
  }
  return { subcommand: tokens[index] ?? null, rest: tokens.slice(index + 1) };
}

/** @param {string[]} tokens */
function isForcePushToProtected(tokens) {
  const { subcommand, rest: args } = parseGit(tokens);
  if (subcommand !== 'push') return false;
  if (args.includes('--mirror')) return true;
  const isForce = args.some((arg) => arg.startsWith('--force') || /^-[a-zA-Z]*f/.test(arg) || arg.startsWith('+'));
  const isDelete = args.includes('--delete') || args.includes('-d') || args.some((arg) => arg.startsWith(':'));
  const refs = args.filter((arg) => !arg.startsWith('-')).slice(1).map((ref) => ref.split(':').pop() ?? ref);
  const touchesProtected = refs.some((ref) => PROTECTED_BRANCHES.test(ref));
  if (isDelete) return touchesProtected;
  if (!isForce) return false;
  return refs.length === 0 || touchesProtected;
}

/** @param {string[]} tokens */
function isGuardrailBypass(tokens) {
  if (tokens[0] !== 'git') return false;
  // Git config keys are case-insensitive; covers `git config` and `git -c key=value`.
  if (tokens.some((arg) => /^core\.hookspath(=|$)/i.test(arg))) return true;
  const { subcommand, rest } = parseGit(tokens);
  if (['commit', 'push', 'merge', 'am', 'rebase'].includes(subcommand) && rest.includes('--no-verify')) return true;
  return subcommand === 'commit' && rest.some((arg) => /^-[a-zA-Z]*n[a-zA-Z]*$/.test(arg));
}

/** @param {string[]} tokens */
function isSystemDestruction(tokens) {
  const [program, ...args] = tokens;
  if (/^mkfs(\.|$)/.test(program ?? '')) return true;
  if (program === 'dd' && args.some((arg) => /^of=\/dev\//.test(arg))) return true;
  return (program === 'chmod' || program === 'chown') && args.includes('-R') && args.includes('/');
}

/** @param {string[]} tokens */
function isEnvironmentDump(tokens) {
  const [program, ...args] = tokens;
  if (program === 'printenv' || (program === 'env' && args.length === 0) || (program === 'set' && args.length === 0)) return true;
  if (program === 'export' && args.includes('-p')) return true;
  return args.some((arg) => /^\/proc\/[^/]+\/environ$/.test(arg));
}

/** @param {string[] & { upstream?: string[][], source?: string }} tokens */
function isRemoteScript(tokens) {
  if (!INTERPRETERS.has(tokens[0])) return false;
  if ((tokens.upstream ?? []).some((earlier) => DOWNLOADERS.has(earlier[0]))) return true;
  return DOWNLOAD_SUBSTITUTION.test(tokens.source ?? '');
}

/** @param {string[]} tokens */
function isSecretEcho(tokens) {
  return (tokens[0] === 'echo' || tokens[0] === 'printf') && tokens.slice(1).some((arg) => SECRET_ENV_ECHO.test(arg));
}

/**
 * Command text for substring rules, without commit/PR message arguments.
 * @param {string[]} tokens
 */
function commandText(tokens) {
  if (!MESSAGE_PROGRAMS.has(tokens[0])) return tokens.join(' ');
  return tokens
    .filter((token, index) => !MESSAGE_FLAG.test(tokens[index - 1] ?? '') && !MESSAGE_ASSIGNMENT.test(token))
    .join(' ');
}

/** Baseline rules that apply in every mode. */
function checkBaselineTokens(tokens) {
  if (isCatastrophicRm(tokens)) return result(DECISION.DENY, 'destructive-rm', 'Recursive delete of the root, home, or project directory is blocked.');
  if (isForcePushToProtected(tokens)) return result(DECISION.DENY, 'force-push', 'Force-pushing, deleting, or mirroring protected branches is blocked.');
  if (isGuardrailBypass(tokens)) return result(DECISION.DENY, 'guardrail-bypass', 'Skipping git hooks (--no-verify, core.hooksPath) is blocked.');
  if (isSystemDestruction(tokens)) return result(DECISION.DENY, 'system-destruction', 'Formatting disks or rewriting / permissions is blocked.');
  if (isRemoteScript(tokens)) return result(DECISION.DENY, 'remote-script', 'Piping a download into an interpreter is blocked.');
  if (DROP_DATABASE.test(commandText(tokens))) return result(DECISION.DENY, 'drop-database', 'DROP DATABASE is blocked.');
  return null;
}

/** "Needs a human" rules; null when none applies. */
function checkEscalationTokens(policy, tokens) {
  if (isEnvironmentDump(tokens)) return escalate(policy, 'environment-dump', 'Dumping the environment exposes tokens to the model.');
  if (isSecretEcho(tokens)) return escalate(policy, 'secret-env', 'Printing secret environment variables is blocked.');
  const text = normalizeCommand(commandText(tokens)).toLowerCase();
  const forbidden = policy.forbiddenCommands.find((entry) => text.includes(normalizeCommand(entry).toLowerCase()));
  if (forbidden) return escalate(policy, 'forbidden-command', `Matches safety.forbidden_commands ("${forbidden}").`);
  return checkFileTokens(policy, tokens);
}

/** @param {ReturnType<typeof loadPolicy>} policy @param {string[]} tokens */
function checkFileTokens(policy, tokens) {
  const [program, ...args] = tokens;
  const redirectTargets = args.filter((_, index) => /^>>?&?$/.test(args[index - 1] ?? ''));
  const readTargets = args.filter((_, index) => args[index - 1] === '<');
  const candidates = args.filter((arg) => !arg.startsWith('-') && !/^[<>]/.test(arg));
  const isCopyLike = ['cp', 'scp', 'rsync', 'tar', 'zip'].includes(program);
  const sources = isCopyLike ? candidates.slice(0, -1) : candidates;
  const readPaths = [...readTargets, ...(READERS.has(program) ? sources : [])];
  for (const path of readPaths) {
    const read = checkRead(policy, path);
    if (read.decision !== DECISION.ALLOW) return read;
  }
  const isInPlaceEdit = program === 'sed' && args.some((arg) => /^-[a-zA-Z]*i/.test(arg));
  const writePaths = [...redirectTargets];
  if (WRITERS.has(program) || isInPlaceEdit) writePaths.push(...(isCopyLike || program === 'mv' ? candidates.slice(-1) : candidates));
  if (program === 'mv' || program === 'rm' || program === 'shred' || program === 'unlink') writePaths.push(...candidates);
  for (const path of writePaths) {
    const write = checkWrite(policy, path);
    if (write.decision !== DECISION.ALLOW) return write;
  }
  return null;
}

/**
 * Adapter entry point: most restrictive decision across all targets of one tool call.
 * @param {ReturnType<typeof loadPolicy>} policy
 * @param {'command' | 'read' | 'write'} kind
 * @param {string[]} targets
 */
export function evaluate(policy, kind, targets) {
  const check = { command: checkCommand, read: checkRead, write: checkWrite }[kind];
  let strictest = ALLOW_RESULT;
  for (const target of targets.filter((value) => typeof value === 'string' && value !== '')) {
    const outcome = check(policy, target);
    if (outcome.decision === DECISION.DENY) return outcome;
    if (outcome.decision === DECISION.ASK) strictest = outcome;
  }
  return strictest;
}

/** @param {ReturnType<typeof loadPolicy>} policy @param {string} command */
export function checkCommand(policy, command) {
  if (isKillSwitchActive(policy)) {
    return result(DECISION.DENY, 'kill-switch', `${policy.killSwitchFile} exists — the agent is stopped.`);
  }
  let firstAsk = null;
  for (const tokens of analyzeCommand(command)) {
    const baseline = checkBaselineTokens(tokens);
    if (baseline) return baseline;
    const escalation = checkEscalationTokens(policy, tokens);
    if (escalation?.decision === DECISION.DENY) return escalation;
    firstAsk ??= escalation;
  }
  return firstAsk ?? ALLOW_RESULT;
}
