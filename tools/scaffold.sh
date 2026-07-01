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

scaffold_be_hex() {
  # Stack-agnostic hexagonal skeleton — docs/hexagonal-project-structure.md (Part B)
  mkdir -p "$DIR"/src/domain/{model,value-objects,services,errors}
  mkdir -p "$DIR"/src/application/{ports/{inbound,outbound},commands,queries,results,usecases,shared}
  mkdir -p "$DIR"/src/adapter/inbound/{handlers,controllers,dtos,schemas,filters,guards,mappers}
  mkdir -p "$DIR"/src/adapter/outbound/{mappers,repositories}
  mkdir -p "$DIR"/src/{configs,composition,common/tokens}
  mkdir -p "$DIR"/{environments,http,scripts,test,docs}
  write environments/.env.template <<'EOF'
# Copy to .env — never commit secrets
# PORT=
# DATABASE_URL=
EOF
  write docs/ARCHITECTURE.md <<'EOF'
# Architecture

Loom guidelines: blueprint `docs/hexagonal-project-structure.md` (all stacks).

Backend: domain → application (ports, commands, queries, results, usecases) → adapter.
Ports only in `application/ports/`. Mappers in `adapter/outbound/mappers/`.
Composition: `composition/` or framework modules / main entry.
EOF
}

scaffold_fe_layers() {
  # Layered FE skeleton — docs/hexagonal-project-structure.md (Part C)
  mkdir -p "$DIR"/src/{app,features,shared/{components,lib},infrastructure/{http,api},stores}
  mkdir -p "$DIR"/docs
  write docs/ARCHITECTURE.md <<'EOF'
# Architecture

Loom FE: blueprint `docs/hexagonal-project-structure.md` **Part C** (clean FE — not BE hex).

Pick C1 (features outside app/) or C2 (colocate in app/). TanStack Query for server state.
EOF
  write src/infrastructure/http/client.ts <<'EOF'
// HTTP client — set baseURL from env; used by infrastructure/api/*
export const apiBaseUrl = process.env.NEXT_PUBLIC_API_URL ?? process.env.VITE_API_URL ?? '';
EOF
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
  # Hex layout for every BE stack (Go, Python, Node, Django, …)
  scaffold_be_hex

  case "$STACK" in
    *go*|*golang*|*gin*|*echo*|*fiber*)
      mkdir -p "$DIR"/cmd/api
      mkdir -p "$DIR"/internal/domain/{model,value-objects,services,errors}
      mkdir -p "$DIR"/internal/application/{ports/{inbound,outbound},commands,queries,results,usecases,shared}
      mkdir -p "$DIR"/internal/adapter/inbound/http/{handlers,dto}
      mkdir -p "$DIR"/internal/adapter/outbound
      write cmd/api/main.go <<'EOF'
// Composition root — wire adapters → use cases → HTTP router
package main

func main() {}
EOF
      ;;
    *django*)
      mkdir -p "$DIR"/config
      write config/.gitkeep <<'EOF'
EOF
      ;;
  esac

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

if [ "$SIDE" = "fe" ]; then
  scaffold_fe_layers
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
  be-*django*)  echo "  django-admin startproject config . && see docs/hexagonal-project-structure.md § B4" ;;
  be-*go*)      echo "  go mod init $(basename "$DIR") && mkdir -p cmd/api internal" ;;
  be-*)         echo "  (pick a BE framework and init it here)" ;;
esac
