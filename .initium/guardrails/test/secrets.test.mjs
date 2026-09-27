import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { findSecretToken, parseAddedLines } from '../secrets.mjs';

// Built at runtime so this file never contains a literal token.
const fake = (prefix, length, alphabet = 'aB3dE5gH7jK9mN1pQ2') => prefix + alphabet.repeat(10).slice(0, length);

describe('findSecretToken', () => {
  const secrets = [
    ['private key', `-----BEGIN ${'RSA '}PRIVATE KEY-----`],
    ['AWS access key', `aws_key = "${fake('AKIA', 16, 'ABCD2345WXYZ')}"`],
    ['GitHub token', `token: ${fake('ghp_', 36)}`],
    ['Anthropic API key', `ANTHROPIC_API_KEY=${fake('sk-ant-', 40)}`],
    ['OpenAI API key', fake('sk-proj-', 40)],
    ['Slack token', fake('xoxb-', 24, '1234567890')],
    ['Google API key', fake('AIza', 35)],
    ['Stripe live key', fake('sk_live_', 24)],
  ];
  for (const [name, line] of secrets) {
    it(`detects ${name}`, () => assert.equal(findSecretToken(line), name));
  }

  it('ignores documentation placeholders and suppressed lines', () => {
    assert.equal(findSecretToken(`key = "${'AKIA'}IOSFODNN7EXAMPLE"`), null);
    assert.equal(findSecretToken('ANTHROPIC_API_KEY=sk-ant-...'), null);
    assert.equal(findSecretToken(`${fake('ghp_', 36)} # guardrails:allow`), null);
    assert.equal(findSecretToken('const pattern = /\\bghp_[A-Za-z0-9]{36}\\b/;'), null);
  });
});

describe('parseAddedLines', () => {
  it('maps added lines to files and line numbers', () => {
    const diff = [
      'diff --git a/src/a.ts b/src/a.ts',
      '--- a/src/a.ts',
      '+++ b/src/a.ts',
      '@@ -3,0 +4,2 @@',
      '+first',
      '+second',
      'diff --git a/old.txt b/old.txt',
      '--- a/old.txt',
      '+++ /dev/null',
      '@@ -1 +0,0 @@',
      '-gone',
    ].join('\n');
    assert.deepEqual(parseAddedLines(diff), [
      { file: 'src/a.ts', line: 4, text: 'first' },
      { file: 'src/a.ts', line: 5, text: 'second' },
    ]);
  });
});
