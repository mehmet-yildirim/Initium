#!/usr/bin/env node
/**
 * check-update.mjs — Report whether a newer Initium release is available.
 *
 * Usage:
 *   node .initium/scripts/check-update.mjs            # human output; exit 10 if an update exists
 *   node .initium/scripts/check-update.mjs --force    # ignore the cached result
 *   node .initium/scripts/check-update.mjs --hook     # agent session-start hook: silent unless
 *                                                     # an update exists; never fails the session
 *
 * Reads agent.config.yaml → initium_sync (channel, notify_local, check_interval_hours) and caches
 * the result in .agent/state/initium-update.json so the network is queried at most once per interval.
 * Requires only git and Node.js 22+ (no npm dependencies).
 */

import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const ROOT = join(import.meta.dirname, '..', '..');
const INITIUM_JSON = join(ROOT, '.initium', 'initium.json');
const AGENT_CONFIG = join(ROOT, 'agent.config.yaml');
const CACHE_FILE = join(ROOT, '.agent', 'state', 'initium-update.json');
const EXIT_UPDATE_AVAILABLE = 10;
const GIT_TIMEOUT_MS = 5000;
const DEFAULT_INTERVAL_HOURS = 24;
const MS_PER_HOUR = 3_600_000;
const SEMVER_TAG = /^v(\d+)\.(\d+)\.(\d+)$/;

const args = new Set(process.argv.slice(2));
const isHook = args.has('--hook');
const isForced = args.has('--force');

/** Reads flat keys of one top-level section from a simple YAML file. */
function readYamlSection(file, section) {
  if (!existsSync(file)) return {};
  const values = {};
  let inSection = false;
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    if (new RegExp(`^${section}:`).test(line)) { inSection = true; continue; }
    if (inSection && /^[^\s#]/.test(line)) break;
    const match = inSection && line.match(/^\s+([\w-]+):\s*([^#\s]+)/);
    if (match) values[match[1]] = match[2].replace(/^["']|["']$/g, '');
  }
  return values;
}

function parseSemver(version) {
  const match = `v${String(version).replace(/^v/, '')}`.match(SEMVER_TAG);
  return match ? match.slice(1).map(Number) : null;
}

function isNewer(candidate, current) {
  for (let i = 0; i < 3; i++) {
    if (candidate[i] !== current[i]) return candidate[i] > current[i];
  }
  return false;
}

function git(...gitArgs) {
  return execFileSync('git', gitArgs, { encoding: 'utf8', timeout: GIT_TIMEOUT_MS, stdio: ['ignore', 'pipe', 'ignore'] });
}

/** Queries the upstream repository for the newest target on the configured channel. */
function fetchLatest(repository, channel) {
  if (channel === 'main') {
    const sha = git('ls-remote', repository, 'refs/heads/main').split(/\s+/)[0];
    return { ref: 'main', commit: sha, version: null };
  }
  const tags = git('ls-remote', '--tags', '--refs', '--sort=-v:refname', repository, 'v*')
    .split('\n')
    .map((line) => line.split(/\s+/)[1]?.replace('refs/tags/', ''))
    .filter((tag) => tag && SEMVER_TAG.test(tag));
  const newest = tags.map((tag) => ({ tag, semver: parseSemver(tag) }))
    .reduce((best, entry) => (!best || isNewer(entry.semver, best.semver) ? entry : best), null);
  return newest ? { ref: newest.tag, commit: null, version: newest.tag.slice(1) } : null;
}

function readCache(channel, intervalHours) {
  if (isForced || !existsSync(CACHE_FILE)) return null;
  try {
    const cache = JSON.parse(readFileSync(CACHE_FILE, 'utf8'));
    const isFresh = Date.now() - Date.parse(cache.checkedAt) < intervalHours * MS_PER_HOUR;
    return isFresh && cache.channel === channel ? cache : null;
  } catch {
    return null;
  }
}

function writeCache(result) {
  mkdirSync(dirname(CACHE_FILE), { recursive: true });
  writeFileSync(CACHE_FILE, `${JSON.stringify({ ...result, checkedAt: new Date().toISOString() }, null, 2)}\n`);
}

function isUpdateAvailable(latest, skeleton, channel) {
  if (!latest) return false;
  if (channel === 'main') return Boolean(latest.commit) && latest.commit !== skeleton.commit;
  const current = parseSemver(skeleton.version);
  return current ? isNewer(parseSemver(latest.version), current) : true;
}

function main() {
  if (!existsSync(INITIUM_JSON)) return 0;
  const { skeleton } = JSON.parse(readFileSync(INITIUM_JSON, 'utf8'));
  const settings = readYamlSection(AGENT_CONFIG, 'initium_sync');
  if (isHook && settings.notify_local === 'false') return 0;

  const channel = settings.channel === 'main' ? 'main' : 'tags';
  const intervalHours = Number(settings.check_interval_hours) || DEFAULT_INTERVAL_HOURS;

  let latest = readCache(channel, intervalHours)?.latest;
  if (latest === undefined) {
    latest = fetchLatest(skeleton.repository, channel);
    writeCache({ channel, latest });
  }

  const target = latest?.version ? `v${latest.version}` : `${latest?.ref} (${latest?.commit?.slice(0, 7)})`;
  if (!isUpdateAvailable(latest, skeleton, channel)) {
    if (isHook) return 0;
    console.log(latest
      ? `Initium is up to date (v${skeleton.version}, channel: ${channel}).`
      : 'No Initium release tags found yet — nothing to compare (use channel "main" to follow commits).');
    return 0;
  }

  if (isHook) {
    console.log(
      `Initium ${target} is available; this project is on v${skeleton.version}. ` +
      'Mention this to the user once and suggest running /sync-initium (or waiting for the weekly ' +
      'initium-sync pull request). Do not sync unless the user asks.',
    );
    return 0;
  }
  console.log(`Initium ${target} is available (current: v${skeleton.version}).`);
  console.log('Apply it with: bash .initium/scripts/sync.sh   (or /sync-initium)');
  return EXIT_UPDATE_AVAILABLE;
}

try {
  process.exitCode = main();
} catch (error) {
  // Offline or upstream unreachable: a session hook must never block the agent.
  if (!isHook) {
    console.error(`Could not check for Initium updates: ${error.message}`);
    process.exitCode = 1;
  }
}
