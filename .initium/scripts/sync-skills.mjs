#!/usr/bin/env node
/**
 * sync-skills.mjs — Validate Agent Skills and regenerate Continue rule files.
 *
 * Source of truth: .claude/skills/<name>/SKILL.md (Agent Skills standard). Claude Code,
 * Cursor, and OpenCode all load this directory natively. Continue does not, so this
 * script writes .continue/rules/skills/<name>.md from each skill.
 *
 * Usage:
 *   node .initium/scripts/sync-skills.mjs          # validate + regenerate Continue rules
 *   node .initium/scripts/sync-skills.mjs --check  # validate + fail if Continue rules are stale
 */

import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..', '..');
const SKILLS_DIR = join(ROOT, '.claude', 'skills');
const CONTINUE_DIR = join(ROOT, '.continue', 'rules', 'skills');
const NAME_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const MAX_NAME_LENGTH = 64;
const MAX_DESCRIPTION_LENGTH = 1024;
const GENERATED_MARKER = '<!-- Generated from .claude/skills by .initium/scripts/sync-skills.mjs — edit the skill, not this file. -->';

const isCheckMode = process.argv.includes('--check');

function parseSkill(dirName) {
  const file = join(SKILLS_DIR, dirName, 'SKILL.md');
  if (!existsSync(file)) return { errors: [`${dirName}: missing SKILL.md`] };

  const text = readFileSync(file, 'utf8');
  const match = text.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) return { errors: [`${dirName}: SKILL.md has no YAML frontmatter`] };

  const [, frontmatter, body] = match;
  const name = frontmatter.match(/^name:\s*(.+)$/m)?.[1]?.trim() ?? '';
  const description = frontmatter.match(/^description:\s*(.+)$/m)?.[1]?.trim() ?? '';
  const paths = [...frontmatter.matchAll(/^\s+-\s+"?([^"\n]+)"?$/gm)].map((m) => m[1]);

  const errors = [];
  if (!NAME_PATTERN.test(name) || name.length > MAX_NAME_LENGTH) {
    errors.push(`${dirName}: invalid name "${name}" (lowercase, digits, single hyphens, max ${MAX_NAME_LENGTH})`);
  }
  if (name !== dirName) errors.push(`${dirName}: name "${name}" must match its folder name`);
  if (!description || description.length > MAX_DESCRIPTION_LENGTH) {
    errors.push(`${dirName}: description must be 1-${MAX_DESCRIPTION_LENGTH} characters`);
  }

  return { skill: { name, description, paths, body }, errors };
}

function renderContinueRule({ name, description, paths, body }) {
  const globs = paths.length ? `globs:\n${paths.map((p) => `  - "${p}"`).join('\n')}\n` : '';
  return `---\nname: ${name}\ndescription: ${description}\n${globs}alwaysApply: false\n---\n${GENERATED_MARKER}\n${body}`;
}

function main() {
  if (!existsSync(SKILLS_DIR)) {
    console.error(`Missing ${SKILLS_DIR}`);
    process.exit(1);
  }

  const dirNames = readdirSync(SKILLS_DIR, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();

  const parsed = dirNames.map(parseSkill);
  const errors = parsed.flatMap((result) => result.errors);
  if (errors.length) {
    errors.forEach((error) => console.error(`INVALID ${error}`));
    process.exit(1);
  }

  const skills = parsed.map((result) => result.skill);
  const expected = new Map(skills.map((skill) => [`${skill.name}.md`, renderContinueRule(skill)]));
  const existing = existsSync(CONTINUE_DIR) ? readdirSync(CONTINUE_DIR).filter((f) => f.endsWith('.md')) : [];

  if (isCheckMode) {
    const stale = [...expected].filter(([file, content]) => {
      const path = join(CONTINUE_DIR, file);
      return !existsSync(path) || readFileSync(path, 'utf8') !== content;
    }).map(([file]) => file);
    const orphaned = existing.filter((file) => !expected.has(file));
    [...stale, ...orphaned].forEach((file) => console.error(`Out of sync: .continue/rules/skills/${file}`));
    if (stale.length || orphaned.length) {
      console.error('Run: node .initium/scripts/sync-skills.mjs');
      process.exit(1);
    }
    console.log(`${skills.length} skill(s) valid; Continue rules in sync.`);
    return;
  }

  mkdirSync(CONTINUE_DIR, { recursive: true });
  existing.filter((file) => !expected.has(file)).forEach((file) => rmSync(join(CONTINUE_DIR, file)));
  expected.forEach((content, file) => writeFileSync(join(CONTINUE_DIR, file), content));
  console.log(`${skills.length} skill(s) valid; regenerated .continue/rules/skills/.`);
}

main();
