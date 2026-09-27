/**
 * Best-effort shell command parsing for guardrail checks.
 *
 * This is defense in depth, not a shell interpreter: it splits commands into simple
 * commands, strips wrappers (sudo, env, VAR=value, xargs, ...), and unwraps nested
 * `sh -c "..."`, `eval "..."`, `$(...)`, backticks, and heredocs fed to a shell so each
 * part is checked. Heredocs written by `cat`/`tee` are data and are not analyzed.
 */

const WRAPPERS = new Set(['sudo', 'doas', 'env', 'command', 'exec', 'nohup', 'time', 'nice', 'ionice', 'xargs', 'builtin']);
const KEYWORDS = new Set(['{', '!', 'if', 'elif', 'then', 'else', 'while', 'until', 'do']);
const SHELLS = new Set(['sh', 'bash', 'zsh', 'dash', 'ksh', 'fish']);
const DATA_SINKS = new Set(['cat', 'tee']);
const HEREDOC_MARKER = /(?<!<)<<(-?)[ \t]*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\2/g;
const MAX_DEPTH = 4;

/**
 * Extracts `$(...)`, `<(...)`, `>(...)` and backtick bodies (outermost level);
 * single-quoted text is literal and skipped.
 * @param {string} text
 */
function extractSubstitutions(text) {
  const bodies = [];
  let inDouble = false;
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (char === '\\') {
      i++;
    } else if (char === '"') {
      inDouble = !inDouble;
    } else if (char === "'" && !inDouble) {
      const end = text.indexOf("'", i + 1);
      if (end === -1) break;
      i = end;
    } else if ((char === '$' || char === '<' || char === '>') && text[i + 1] === '(') {
      let depth = 1;
      let j = i + 2;
      while (j < text.length && depth > 0) {
        if (text[j] === '(') depth++;
        if (text[j] === ')') depth--;
        j++;
      }
      bodies.push(text.slice(i + 2, j - 1));
      i = j - 1;
    } else if (char === '`') {
      const end = text.indexOf('`', i + 1);
      if (end === -1) break;
      bodies.push(text.slice(i + 1, end));
      i = end;
    }
  }
  return bodies;
}

/**
 * Removes heredoc bodies from a command line.
 * @param {string} command
 * @returns {{ script: string, heredocs: Array<{ owner: string, rest: string, body: string }> }}
 */
export function extractHeredocs(command) {
  const lines = command.split('\n');
  const kept = [];
  const heredocs = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    kept.push(line);
    for (const match of line.matchAll(HEREDOC_MARKER)) {
      const [marker, dash, , delimiter] = match;
      const body = [];
      while (++i < lines.length) {
        const candidate = dash ? lines[i].replace(/^\t+/, '') : lines[i];
        if (candidate === delimiter) break;
        body.push(lines[i]);
      }
      heredocs.push({ owner: line.slice(0, match.index), rest: line.slice(match.index + marker.length), body: body.join('\n') });
    }
  }
  return { script: kept.join('\n'), heredocs };
}

/**
 * Splits a command line into simple commands with the operator that precedes each one.
 * Quotes, substitutions, and backticks stay intact; subshell parentheses separate.
 * @param {string} command
 * @returns {Array<{ text: string, op: string | null }>}
 */
export function splitCommandList(command) {
  const parts = [];
  let current = '';
  let quote = null;
  let depth = 0;
  let op = null;
  const flush = (nextOp) => {
    if (current.trim()) parts.push({ text: current.trim(), op });
    current = '';
    op = nextOp;
  };
  for (let i = 0; i < command.length; i++) {
    const char = command[i];
    const next = command[i + 1];
    if (quote) {
      current += char;
      if (char === '\\' && quote === '"') current += command[++i] ?? '';
      else if (char === quote) quote = null;
    } else if (char === '"' || char === "'") {
      quote = char;
      current += char;
    } else if (char === '\\') {
      current += char + (command[++i] ?? '');
    } else if ((char === '$' || char === '<' || char === '>') && next === '(') {
      depth++;
      current += char + next;
      i++;
    } else if (depth > 0) {
      if (char === '(') depth++;
      if (char === ')') depth--;
      current += char;
    } else if (char === '`') {
      const end = command.indexOf('`', i + 1);
      const stop = end === -1 ? command.length - 1 : end;
      current += command.slice(i, stop + 1);
      i = stop;
    } else if (char === '(' || char === ')') {
      flush(null);
    } else if (char === '|') {
      const isOr = next === '|';
      if (isOr || next === '&') i++;
      flush(isOr ? '||' : '|');
    } else if (char === '&' && command[i - 1] !== '>' && next !== '>') {
      const isAnd = next === '&';
      if (isAnd) i++;
      flush(isAnd ? '&&' : '&');
    } else if (char === ';' || char === '\n') {
      flush(char);
    } else {
      current += char;
    }
  }
  flush(null);
  return parts;
}

/** @param {string} command */
export function splitSimpleCommands(command) {
  return splitCommandList(command).map((part) => part.text);
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
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(token) || KEYWORDS.has(token)) {
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
 * A heredoc fed to a shell is a script; one written by cat/tee is data; anything else
 * (psql, python, ...) is returned as `[program, body]` so text rules still see it.
 */
function analyzeHeredoc({ owner, rest, body }, depth) {
  const ownerText = owner.split(/[;&|(`\n]/).pop() ?? '';
  const [program = 'heredoc'] = stripWrappers(tokenize(ownerText));
  const downstream = rest.split('|').slice(1).map((part) => stripWrappers(tokenize(part))[0]);
  if (SHELLS.has(program) || downstream.some((next) => SHELLS.has(next))) return analyzeCommand(body, depth + 1);
  const isData = DATA_SINKS.has(program) && downstream.length === 0;
  return isData ? [] : [[program, body]];
}

/**
 * Returns every simple command (as tokens, wrappers stripped) reachable from `command`.
 * Each token array carries non-enumerable `source` (the simple command text) and
 * `upstream` (earlier commands of the same pipeline).
 * @param {string} command
 * @param {number} [depth]
 * @returns {string[][]}
 */
export function analyzeCommand(command, depth = 0) {
  if (depth > MAX_DEPTH) return [];
  const { script, heredocs } = extractHeredocs(command);
  const commands = [];
  for (const heredoc of heredocs) commands.push(...analyzeHeredoc(heredoc, depth));
  for (const body of extractSubstitutions(script)) commands.push(...analyzeCommand(body, depth + 1));
  let pipeline = [];
  for (const { text, op } of splitCommandList(script)) {
    if (op !== '|') pipeline = [];
    const tokens = stripWrappers(tokenize(text));
    if (tokens.length === 0) continue;
    Object.defineProperties(tokens, { source: { value: text }, upstream: { value: [...pipeline] } });
    commands.push(tokens);
    pipeline.push(tokens);
    const nested = nestedScript(tokens);
    if (nested) commands.push(...analyzeCommand(nested, depth + 1));
  }
  return commands;
}

/** Collapses whitespace so substring rules match regardless of spacing. */
export function normalizeCommand(command) {
  return command.replace(/\s+/g, ' ').trim();
}
