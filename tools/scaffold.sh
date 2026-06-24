#!/usr/bin/env zsh
# Best-practice skeleton for a FE or BE folder. Idempotent: never overwrites existing files.
# Usage: zsh tools/scaffold.sh <fe|be> <target-dir> [stack]
set -euo pipefail

SIDE="${1:?usage: scaffold.sh <fe|be> <dir> [stack]}"
DIR="${2:?target dir required}"
STACK="${3:-}"

mkdir -p "$DIR"/{src,tests}
cd "$DIR"

write() { # write() <path> <<'EOF' ... ; skips if file exists
  local f="$1"
  if [ -e "$f" ]; then echo "  skip  $f (exists)"; cat >/dev/null; else cat > "$f"; echo "  +     $f"; fi
}

echo "Scaffolding $SIDE → $DIR (stack: ${STACK:-unspecified})"

write .editorconfig <<'EOF'
root = true
[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 2
EOF

write .gitignore <<'EOF'
node_modules/
dist/
build/
.next/
coverage/
.env
.env.*
!.env.example
__pycache__/
*.pyc
.venv/
.DS_Store
EOF

write .env.example <<'EOF'
# Copy to .env and fill in. Never commit real secrets.
# PORT=
# DATABASE_URL=
EOF

write README.md <<EOF
# $(basename "$DIR")

Scaffolded by the agent loop ($SIDE, stack: ${STACK:-unspecified}).

## Develop
\`\`\`zsh
# install deps, then run the framework's dev command, e.g.:
npm run dev
\`\`\`
EOF

if [ "$SIDE" = "be" ]; then
  case "$STACK" in
    *fastapi*|*python*)
      write Dockerfile <<'EOF'
# syntax=docker/dockerfile:1
# Multi-stage build for a FastAPI app — small, non-root, healthchecked.
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app

FROM base AS deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM base AS runtime
RUN useradd -m app
COPY --from=deps /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin
COPY . .
USER app
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/health').status==200 else 1)"
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
      ;;
    *node*|*express*|*nest*)
      write Dockerfile <<'EOF'
# syntax=docker/dockerfile:1
# Multi-stage build for a Node app — small, non-root, healthchecked.
FROM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM node:22-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build || true

FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app ./
RUN addgroup -S app && adduser -S app -G app
USER app
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:3000/health || exit 1
CMD ["node", "dist/main.js"]
EOF
      ;;
    *)
      write Dockerfile <<'EOF'
# syntax=docker/dockerfile:1
# Generic multi-stage placeholder — adjust base image + start command to your stack.
FROM debian:stable-slim AS runtime
WORKDIR /app
RUN useradd -m app || adduser -D app || true
COPY . .
USER app
EXPOSE 8080
CMD ["echo", "set your start command in the Dockerfile"]
EOF
      ;;
  esac

  write docker-compose.yml <<'EOF'
services:
  api:
    build: .
    env_file: .env
    ports:
      - "8000:8000"
    develop:
      watch:
        - action: sync
          path: ./src
          target: /app/src
    restart: unless-stopped
EOF

  write .dockerignore <<'EOF'
node_modules
.git
.env
.env.*
__pycache__
.venv
dist
build
coverage
EOF
fi

echo "Done. Next: run the framework generator in $DIR, e.g.:"
case "$SIDE-$STACK" in
  fe-*next*)    echo "  npx create-next-app@latest . --ts --eslint" ;;
  fe-*vite*)    echo "  npm create vite@latest . -- --template react-ts" ;;
  fe-*svelte*)  echo "  npm create svelte@latest ." ;;
  fe-*astro*)   echo "  npm create astro@latest ." ;;
  fe-*)         echo "  (pick a FE framework and init it here)" ;;
  be-*fastapi*) echo "  python -m venv .venv && .venv/bin/pip install fastapi uvicorn[standard] && echo 'fastapi\\nuvicorn[standard]' > requirements.txt" ;;
  be-*nest*)    echo "  npx @nestjs/cli new . " ;;
  be-*node*|be-*express*) echo "  npm init -y && npm i express" ;;
  be-*go*)      echo "  go mod init $(basename "$DIR")" ;;
  be-*)         echo "  (pick a BE framework and init it here)" ;;
esac
