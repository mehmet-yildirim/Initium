/**
 * Best-effort shell command parsing for guardrail checks.
 *
 * This is defense in depth, not a shell interpreter: it splits commands into simple
 * commands, strips wrappers (sudo, env, VAR=value, xargs, ...), and unwraps nested
 * `sh -c "..."`, `eval "..."`, `$(...)` and backticks so each part is checked.
 */

const SEPARATORS = new Set([';', '&', '|', '\n']);
const WRAPPERS = new Set(['sudo', 'doas', 'env', 'command', 'exec', 'nohup', 'time', 'nice', 'ionice', 'xargs', 'builtin']);
const SHELLS = new Set(['sh', 'bash', 'zsh', 'dash', 'ksh', 'fish']);
const MAX_DEPTH = 4;

/**
 * Extracts `$(...)`, `<(...)` and backtick bodies (outermost level).
 * @param {string} text
 */
function extractSubstitutions(text) {
  const bodies = [];
  for (let i = 0; i < text.length; i++) {
    const isParenStart = (text[i] === '$' || text[i] === '<' || text[i] === '>') && text[i + 1] === '(';
    if (isParenStart) {
      let depth = 1;
      let j = i + 2;
      while (j < text.length && depth > 0) {
        if (text[j] === '(') depth++;
        if (text[j] === ')') depth--;
        j++;
      }
      bodies.push(text.slice(i + 2, j - 1));
      i = j - 1;
    } else if (text[i] === '`') {
      const end = text.indexOf('`', i + 1);
      if (end === -1) break;
      bodies.push(text.slice(i + 1, end));
      i = end;
    }
  }
  return bodies;
}

/**
 * Splits a command line into simple-command strings, respecting quotes.
 * @param {string} command
 */
export function splitSimpleCommands(command) {
  const parts = [];
  let current = '';
  let quote = null;
  for (let i = 0; i < command.length; i++) {
    const char = command[i];
    if (quote) {
      current += char;
      if (char === '\\' && quote === '"') current += command[++i] ?? '';
      else if (char === quote) quote = null;
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
      current += char;
    } else if (char === '\\') {
      current += char + (command[++i] ?? '');
    } else if (SEPARATORS.has(char) && !(char === '&' && command[i - 1] === '>') && !(char === '&' && command[i + 1] === '>')) {
      if (current.trim()) parts.push(current.trim());
      current = '';
    } else {
      current += char;
    }
  }
  if (current.trim()) parts.push(current.trim());
  return parts;
}

/**
 * Tokenizes one simple command; quotes are removed, redirections become own tokens.
 * @param {string} simpleCommand
 */
export function tokenize(simpleCommand) {
  const tokens = [];
  let current = '';
  let hasToken = false;
  let quote = null;
  const push = () => {
    if (hasToken) tokens.push(current);
    current = '';
    hasToken = false;
  };
  for (let i = 0; i < simpleCommand.length; i++) {
    const char = simpleCommand[i];
    if (quote) {
      if (char === quote) quote = null;
      else current += char;
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
      hasToken = true;
    } else if (char === '\\') {
      current += simpleCommand[++i] ?? '';
      hasToken = true;
    } else if (/\s/.test(char)) {
      push();
    } else if (char === '>' || char === '<') {
      if (/^\d*&?$/.test(current)) {
        current = '';
        hasToken = false;
      }
      push();
      let op = char;
      while (simpleCommand[i + 1] === '>' || simpleCommand[i + 1] === '&') op += simpleCommand[++i];
      tokens.push(op);
    } else {
      current += char;
      hasToken = true;
    }
  }
  push();
  return tokens;
}

/** @param {string[]} tokens */
function stripWrappers(tokens) {
  let index = 0;
  while (index < tokens.length) {
    const token = tokens[index];
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(token)) {
      index++;
    } else if (WRAPPERS.has(token)) {
      let next = index + 1;
      while (next < tokens.length && tokens[next].startsWith('-')) next++;
      if (next >= tokens.length) break;
      index = next;
    } else {
      break;
    }
  }
  return tokens.slice(index);
}

/** @param {string[]} tokens */
function nestedScript(tokens) {
  const [program, ...args] = tokens;
  if (program === 'eval') return args.join(' ');
  if (SHELLS.has(program)) {
    const flagIndex = args.findIndex((arg) => /^-[a-z]*c[a-z]*$/.test(arg));
    if (flagIndex !== -1 && args[flagIndex + 1]) return args[flagIndex + 1];
  }
  return null;
}

/**
 * Returns every simple command (as tokens, wrappers stripped) reachable from `command`.
 * @param {string} command
 * @param {number} [depth]
 * @returns {string[][]}
 */
export function analyzeCommand(command, depth = 0) {
  if (depth > MAX_DEPTH) return [];
  const commands = [];
  for (const body of extractSubstitutions(command)) {
    commands.push(...analyzeCommand(body, depth + 1));
  }
  for (const simple of splitSimpleCommands(command)) {
    const tokens = stripWrappers(tokenize(simple));
    if (tokens.length === 0) continue;
    commands.push(tokens);
    const nested = nestedScript(tokens);
    if (nested) commands.push(...analyzeCommand(nested, depth + 1));
  }
  return commands;
}

/** Collapses whitespace so substring rules match regardless of spacing. */
export function normalizeCommand(command) {
  return command.replace(/\s+/g, ' ').trim();
}
