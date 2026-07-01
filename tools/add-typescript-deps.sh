#!/usr/bin/env zsh
# Install Loom-recommended TypeScript packages (idempotent).
# Usage:
#   zsh add-typescript-deps.sh [project-dir] --profile ts-common|ts-be|ts-nest
#   zsh add-typescript-deps.sh ./api --profile ts-nest --husky
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/tools/typescript-deps.json"
DIR="."
PROFILE="ts-common"
HUSKY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="${2:?}"; shift 2 ;;
    --husky) HUSKY=1; shift ;;
    -h|--help)
      echo "usage: add-typescript-deps.sh [dir] --profile ts-common|ts-be|ts-nest [--husky]"
      exit 0 ;;
    *)
      if [ "$DIR" = "." ] && [ -d "$1" ]; then DIR="$1"; shift
      else echo "unknown arg: $1" >&2; exit 2; fi ;;
  esac
done

[ -f "$MANIFEST" ] || { echo "missing $MANIFEST" >&2; exit 1; }
cd "$DIR"
DIR="$(pwd)"

if [ ! -f package.json ]; then
  echo "  ! no package.json in $DIR — init framework first (nest, express, vite, …)" >&2
  exit 1
fi

resolve_profile() {
  node -e "
const fs = require('fs');
const m = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
const name = process.argv[2];
const seen = new Set();
const deps = {};
const dev = {};
function merge(p) {
  if (!p || seen.has(p)) return;
  seen.add(p);
  const row = m.profiles[p];
  if (!row) throw new Error('unknown profile: ' + p);
  if (row.extends) merge(row.extends);
  Object.assign(deps, row.dependencies || {});
  Object.assign(dev, row.devDependencies || {});
}
merge(name);
console.log(JSON.stringify({ dependencies: deps, devDependencies: dev }));
" "$MANIFEST" "$PROFILE"
}

PACKS="$(resolve_profile)"
DEPS=($(node -e "const p=JSON.parse(process.argv[1]); console.log(Object.keys(p.dependencies||{}).join(' '))" "$PACKS"))
DEVS=($(node -e "const p=JSON.parse(process.argv[1]); console.log(Object.keys(p.devDependencies||{}).join(' '))" "$PACKS"))

missing_deps() {
  node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const want = JSON.parse(process.argv[1]).dependencies || {};
const have = { ...pkg.dependencies, ...pkg.devDependencies };
const out = Object.keys(want).filter(k => !have[k]);
console.log(out.join(' '));
" "$PACKS"
}

missing_devs() {
  node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const want = JSON.parse(process.argv[1]).devDependencies || {};
const have = { ...pkg.dependencies, ...pkg.devDependencies };
const out = Object.keys(want).filter(k => !have[k]);
console.log(out.join(' '));
" "$PACKS"
}

MD="$(missing_deps)"
MDV="$(missing_devs)"

echo "== TypeScript deps ($PROFILE) → $DIR =="

if [ -n "$MD" ]; then
  echo "  + dependencies: $MD"
  npm install $MD
fi
if [ -n "$MDV" ]; then
  echo "  + devDependencies: $MDV"
  npm install -D $MDV
fi
if [ -z "$MD" ] && [ -z "$MDV" ]; then
  echo "  ✓ all packages present"
fi

# ponytail: merge scripts only when key missing
node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
pkg.scripts = pkg.scripts || {};
const add = (k, v) => { if (!pkg.scripts[k]) pkg.scripts[k] = v; };
add('lint', 'eslint \"src/**/*.ts\"');
add('lint:fix', 'eslint \"src/**/*.ts\" --fix');
add('format', 'prettier --write \"src/**/*.ts\"');
add('test', 'jest');
add('test:cov', 'jest --coverage');
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
"

if (( HUSKY )) || [ -d node_modules/husky ] || grep -q '"husky"' package.json 2>/dev/null; then
  if ! [ -d .husky ]; then
    echo "  + husky init"
    npx husky init 2>/dev/null || true
  fi
  if [ -d .husky ]; then
    write_hook() {
      local f="$1" body="$2"
      if [ ! -f "$f" ] || ! grep -q 'loom-typescript-deps' "$f" 2>/dev/null; then
        printf '%s\n' "$body" >"$f"
        chmod +x "$f" 2>/dev/null || true
        echo "  + $f"
      fi
    }
    write_hook .husky/pre-commit "$(cat <<'EOF'
#!/usr/bin/env sh
# loom-typescript-deps
npm run lint
npm run test:cov
EOF
)"
  fi
fi

echo "Done. Guide: $ROOT/docs/typescript-packages.md"
