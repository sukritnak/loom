#!/usr/bin/env zsh
# locale.sh — communication language for Loom (en | th | auto)
# Usage:
#   source tools/locale.sh
#   LOOM_LOCALE="$(pick_locale)"
#   ensure_locale_config "$control_dir" "$LOOM_LOCALE"
set -euo pipefail

pick_locale() {
  local preset="${1:-}" default_n="${2:-3}"
  case "$preset" in
    en|th|auto) echo "$preset"; return 0 ;;
  esac
  echo
  echo "Communication language / ภาษาในการสื่อสาร:"
  echo "  1) English"
  echo "  2) ไทย (Thai)"
  echo "  3) Auto — match your messages / ตามภาษาที่คุณพิมพ์ (default)"
  local pick v
  read -r "v?Choice [1-3] [${default_n}]: " || true
  pick="${v:-$default_n}"
  case "$pick" in
    1|en|english|English) echo en ;;
    2|th|thai|ไทย) echo th ;;
    *) echo auto ;;
  esac
}

read_locale_from_config() {
  local dest="$1"
  node -e "
const fs = require('fs');
const p = require('path').join(process.argv[1], 'loop.config.json');
try {
  const c = JSON.parse(fs.readFileSync(p, 'utf8'));
  const l = c.locale;
  if (l === 'en' || l === 'th' || l === 'auto') process.stdout.write(l);
} catch (e) { process.exit(1); }
" "$dest" 2>/dev/null || return 1
}

ensure_locale_config() {
  local dest="$1" locale="${2:-}" _locale
  [ -f "$dest/loop.config.json" ] || return 1
  [ -n "$locale" ] || locale="$(read_locale_from_config "$dest" 2>/dev/null || true)"
  [ -n "$locale" ] || locale="$(pick_locale)"
  _locale="$(LOOM_LOCALE="$locale" DEST="$dest" node -e "
const fs = require('fs');
const path = require('path');
const dest = process.env.DEST;
const locale = process.env.LOOM_LOCALE || 'auto';
const cfgPath = path.join(dest, 'loop.config.json');
const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
cfg.locale = locale;
fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2) + '\n');
const statePath = path.join(dest, 'STATE.md');
if (fs.existsSync(statePath)) {
  let s = fs.readFileSync(statePath, 'utf8');
  const line = '## Locale\\n' + locale + '   <!-- en | th | auto — also in loop.config.json -->';
  if (/^## Locale\\n/m.test(s)) {
    s = s.replace(/^## Locale\\n[^\n]*/m, line);
  } else {
    s = s.replace(/^(## Autonomy level\\n[^\n]*\n)/m, '\$1\n' + line + '\n');
  }
  fs.writeFileSync(statePath, s);
}
process.stdout.write(locale);
")"
  echo "✓ Locale → $_locale (loop.config.json + STATE.md)"
}

locale_label() {
  case "${1:-auto}" in
    en) echo "English" ;;
    th) echo "ไทย" ;;
    *) echo "Auto" ;;
  esac
}
