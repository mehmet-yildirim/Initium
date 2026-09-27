/**
 * Minimal gitignore-style glob matching for guardrail path rules.
 *
 * - A pattern without "/" matches the basename anywhere (`*.pem`, `.env`).
 * - A pattern with "/" matches the path relative to the project root
 *   (`.github/workflows/**`, `**\/secrets/**`).
 * - `**` spans directories, `*` and `?` stay inside one segment.
 */

const REGEX_SPECIALS = /[.+^${}()|[\]\\]/g;

/** @param {string} pattern */
export function globToRegExp(pattern) {
  let source = '';
  for (let i = 0; i < pattern.length; i++) {
    const char = pattern[i];
    if (char === '*' && pattern[i + 1] === '*') {
      const isDirPrefix = pattern[i + 2] === '/';
      source += isDirPrefix ? '(?:.*/)?' : '.*';
      i += isDirPrefix ? 2 : 1;
    } else if (char === '*') {
      source += '[^/]*';
    } else if (char === '?') {
      source += '[^/]';
    } else {
      source += char.replace(REGEX_SPECIALS, '\\$&');
    }
  }
  return new RegExp(`^${source}$`);
}

/**
 * @param {string} relativePath POSIX path relative to the project root
 * @param {string} pattern
 */
export function matchesGlob(relativePath, pattern) {
  const normalized = pattern.replace(/^\.\//, '');
  if (!normalized.includes('/')) {
    const basename = relativePath.split('/').pop() ?? '';
    return globToRegExp(normalized).test(basename);
  }
  return globToRegExp(normalized).test(relativePath);
}

/** @param {string} relativePath @param {string[]} patterns */
export function matchesAny(relativePath, patterns) {
  return patterns.find((pattern) => matchesGlob(relativePath, pattern)) ?? null;
}
