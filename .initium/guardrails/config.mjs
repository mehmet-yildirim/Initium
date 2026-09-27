/**
 * Reads the `safety:` block of agent.config.yaml without a YAML dependency.
 * Supports exactly the shapes that block uses: scalar values and lists of scalars.
 */

import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const CONFIG_FILE = 'agent.config.yaml';
const SECTION = 'safety';

/** @param {string} line */
function stripComment(line) {
  let quote = null;
  for (let i = 0; i < line.length; i++) {
    const char = line[i];
    if (quote) {
      if (char === quote) quote = null;
    } else if (char === '"' || char === "'") {
      quote = char;
    } else if (char === '#' && (i === 0 || /\s/.test(line[i - 1]))) {
      return line.slice(0, i);
    }
  }
  return line;
}

/** @param {string} raw */
function parseScalar(raw) {
  const value = raw.trim();
  if (/^(["']).*\1$/.test(value)) return value.slice(1, -1);
  if (/^-?\d+(\.\d+)?$/.test(value)) return Number(value);
  if (value === 'true' || value === 'false') return value === 'true';
  return value;
}

/**
 * @param {string} text YAML document
 * @returns {Record<string, unknown>}
 */
export function parseSafetySection(text) {
  const result = {};
  let inSection = false;
  let currentKey = null;
  for (const rawLine of text.split(/\r?\n/)) {
    const line = stripComment(rawLine).replace(/\s+$/, '');
    if (!line.trim()) continue;
    const indent = line.length - line.trimStart().length;
    if (indent === 0) {
      inSection = line.startsWith(`${SECTION}:`);
      currentKey = null;
      continue;
    }
    if (!inSection) continue;
    const item = line.match(/^\s+-\s+(.*)$/);
    if (item && currentKey && Array.isArray(result[currentKey])) {
      result[currentKey].push(parseScalar(item[1]));
      continue;
    }
    const pair = line.match(/^\s+([A-Za-z0-9_]+):\s*(.*)$/);
    if (!pair) continue;
    currentKey = pair[1];
    result[currentKey] = pair[2] === '' ? [] : parseScalar(pair[2]);
  }
  return result;
}

/** @param {string} root */
export function readSafetyConfig(root) {
  const path = join(root, CONFIG_FILE);
  if (!existsSync(path)) return {};
  return parseSafetySection(readFileSync(path, 'utf8'));
}
