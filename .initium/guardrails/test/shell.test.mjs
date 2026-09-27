import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { analyzeCommand, splitSimpleCommands, tokenize } from '../shell.mjs';

describe('splitSimpleCommands', () => {
  it('splits on operators outside quotes', () => {
    assert.deepEqual(splitSimpleCommands('a && b || c; d | e'), ['a', 'b', 'c', 'd', 'e']);
    assert.deepEqual(splitSimpleCommands('echo "a; b" && c'), ['echo "a; b"', 'c']);
  });

  it('keeps redirections that contain &', () => {
    assert.deepEqual(splitSimpleCommands('npm test 2>&1 &>/dev/null'), ['npm test 2>&1 &>/dev/null']);
  });
});

describe('tokenize', () => {
  it('removes quotes and separates redirections', () => {
    assert.deepEqual(tokenize('grep "a b" file>out.txt'), ['grep', 'a b', 'file', '>', 'out.txt']);
    assert.deepEqual(tokenize('cmd 2>>log'), ['cmd', '>>', 'log']);
  });
});

describe('analyzeCommand', () => {
  it('strips wrappers and assignments', () => {
    assert.deepEqual(analyzeCommand('sudo -E FOO=1 env BAR=2 rm -rf /'), [['rm', '-rf', '/']]);
  });

  it('keeps a bare wrapper as the command', () => {
    assert.deepEqual(analyzeCommand('env'), [['env']]);
  });

  it('unwraps nested shells, eval and substitutions', () => {
    const programs = (command) => analyzeCommand(command).map((tokens) => tokens[0]);
    assert.deepEqual(programs('bash -c "sh -c \'cat .env\'"'), ['bash', 'sh', 'cat']);
    assert.deepEqual(programs('echo $(cat .env) `whoami`'), ['cat', 'whoami', 'echo']);
    assert.deepEqual(programs('eval "rm -rf /"'), ['eval', 'rm']);
  });
});
