/**
 * Secret-token detection for staged diffs. High-signal vendor formats only, so the
 * pre-commit hook can block without drowning users in false positives.
 */

export const ALLOW_MARKER = 'guardrails:allow';

export const SECRET_TOKEN_PATTERNS = [
  { name: 'private key', pattern: /-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----/ },
  { name: 'AWS access key', pattern: /\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/, ignore: /EXAMPLE/ },
  { name: 'GitHub token', pattern: /\b(?:ghp|gho|ghs|ghu|ghr)_[A-Za-z0-9]{36}\b|\bgithub_pat_[A-Za-z0-9_]{60,}/ },
  { name: 'Anthropic API key', pattern: /\bsk-ant-[A-Za-z0-9_-]{20,}/ },
  { name: 'OpenAI API key', pattern: /\bsk-proj-[A-Za-z0-9_-]{20,}/ },
  { name: 'Slack token', pattern: /\bxox[baprs]-[A-Za-z0-9-]{10,}/ },
  { name: 'Google API key', pattern: /\bAIza[0-9A-Za-z_-]{35}\b/ },
  { name: 'Stripe live key', pattern: /\b[sr]k_live_[0-9A-Za-z]{24,}\b/ },
];

/** @param {string} line @returns {string | null} name of the matched token type */
export function findSecretToken(line) {
  if (line.includes(ALLOW_MARKER)) return null;
  const hit = SECRET_TOKEN_PATTERNS.find(({ pattern, ignore }) => {
    const match = line.match(pattern);
    return match && !(ignore && ignore.test(match[0]));
  });
  return hit?.name ?? null;
}

/**
 * Added lines per file from a zero-context unified diff.
 * @param {string} diff
 * @returns {Array<{ file: string, line: number, text: string }>}
 */
export function parseAddedLines(diff) {
  const added = [];
  let file = null;
  let lineNumber = 0;
  for (const raw of diff.split('\n')) {
    if (raw.startsWith('+++ ')) {
      file = raw === '+++ /dev/null' ? null : raw.slice(4).replace(/^b\//, '');
    } else if (raw.startsWith('@@')) {
      lineNumber = Number(raw.match(/\+(\d+)/)?.[1] ?? 0);
    } else if (raw.startsWith('+') && file) {
      added.push({ file, line: lineNumber, text: raw.slice(1) });
      lineNumber++;
    }
  }
  return added;
}
