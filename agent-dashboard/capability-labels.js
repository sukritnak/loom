/** Fixed bubble labels for known skills/commands — edit here, never infer at runtime. */
const SKILLS = {
  ponytail: 'ponytail — บังคับโซลูชันที่เรียบที่สุดที่ยังถูก',
  'ponytail-review': 'ponytail-review — review โค้ดว่า over-engineer ไหม',
  'ponytail-audit': 'ponytail-audit — audit ทั้ง repo หา over-engineering',
  'qa-browser': 'qa-browser — เทส FE/UI บน browser จริง (browser-use)',
  solid: 'solid — TDD / SOLID ตาม skill',
  'loop-orch': 'loop-orch — นำ loop ทีม PM→Design→FE/BE→QA',
  'pm-skills': 'pm-skills — PRD, user stories, prioritize (pm-skills marketplace)',
  'ui-ux-pro-max': 'ui-ux-pro-max — design intelligence / UI spec',
  context7: 'context7 — ดึง docs library ล่าสุด',
  'context-mode': 'context-mode — index/search โค้ดและ docs ใน sandbox',
  scrutinize: 'scrutinize — outsider review ทั้ง flow',
  handoff: 'handoff — ส่งต่อ state ไป session/IDE อื่น',
};

const CMDS = [
  [/playwright/i, 'playwright — E2E / browser regression tests'],
  [/^npm test\b/i, 'npm test — unit/integration test suite'],
  [/^pnpm test\b/i, 'pnpm test — unit/integration test suite'],
  [/^yarn test\b/i, 'yarn test — unit/integration test suite'],
  [/npm run dev\b/i, 'npm run dev — FE/BE dev server'],
  [/pnpm run dev\b/i, 'pnpm run dev — dev server'],
  [/vitest/i, 'vitest — unit tests'],
  [/go test/i, 'go test — Go test suite'],
  [/docker compose up/i, 'docker compose — ยก local stack'],
  [/eslint/i, 'eslint — lint'],
  [/tsc\b/i, 'tsc — TypeScript typecheck'],
];

function skillLabel(name) {
  const k = String(name || '').trim();
  return k ? (SKILLS[k] || '') : '';
}

function cmdLabel(shell) {
  const c = String(shell || '').trim();
  if (!c) return '';
  for (const [re, label] of CMDS) {
    if (re.test(c)) return label;
  }
  return '';
}

module.exports = { SKILLS, CMDS, skillLabel, cmdLabel };
