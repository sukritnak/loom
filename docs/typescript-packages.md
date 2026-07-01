# TypeScript packages (Loom standard)

For **any** TypeScript service (NestJS, Express, Next, Vite, …). Install after framework init:

```zsh
zsh "$(cat ~/.loop-base)/tools/add-typescript-deps.sh" <service-path> --profile <profile> --husky
```

| Profile | When |
|---------|------|
| **`ts-common`** | Every TS project (FE or BE) |
| **`ts-be`** | Node API (Express, Fastify, raw Node) |
| **`ts-nest`** | NestJS (`stack` contains `nest`) |

Manifest: `tools/typescript-deps.json` (idempotent — skips packages already in `package.json`).

---

## Recommended utilities (`ts-common`)

| Package | Types | Use for |
|---------|-------|---------|
| **radash** | built-in | `tryit`, `sleep`, object/array helpers — prefer over hand-rolled utils |
| **ts-pattern** | built-in | exhaustive `match` on unions — commands, results, domain events |
| **lodash** | `@types/lodash` | stable `get`/`groupBy`/`omit` when radash doesn't fit |
| **dayjs** | built-in | dates/timezones — not `new Date()` math in domain |
| **builder-pattern** | built-in | fluent builders for complex DTOs / test fixtures |

---

## BE / API (`ts-be` adds)

| Package | Types | Use for |
|---------|-------|---------|
| **class-validator** | built-in | inbound DTO validation (`adapter/inbound/dtos`) |
| **class-transformer** | built-in | `plainToInstance` / `expose` at HTTP boundary |
| **passport** | `@types/passport` | auth strategy host (Nest guard or Express middleware) |
| **passport-jwt** | `@types/passport-jwt` | JWT strategy |
| **keyv** + **@keyv/redis** | built-in | outbound cache port adapter (Redis) |
| **husky** | — | pre-commit: `lint` + `test:cov` (via `--husky` or auto when husky installed) |

---

## NestJS only (`ts-nest` adds)

| Package | Types | Use for |
|---------|-------|---------|
| **nestjs-pino** | built-in | structured logging module |
| **pino-http** | built-in | HTTP request logging (nestjs-pino peer) |

---

## Dev toolchain (`ts-common`)

| Package | Types | Use for |
|---------|-------|---------|
| **jest** | `@types/jest` | unit tests — use cases, domain, mappers |
| **prettier** | — | format |
| **eslint** + **eslint-config-prettier** + **eslint-plugin-prettier** | — | lint + Prettier integration |
| **eslint-plugin-simple-import-sort** | — | consistent import order |

Scripts added if missing: `lint`, `lint:fix`, `format`, `test`, `test:cov`.

---

## Agent rules

1. **New TS service** (`mode: new`) — after framework generator, run the matching profile + `--husky` on BE.
2. **Existing** — install only missing packages; never duplicate versions in docs vs `package.json`.
3. **FE** — `ts-common` only (no passport/keyv/nestjs-pino unless AC requires auth client libs).
4. Prefer **radash** / **ts-pattern** before new helper files; **class-validator** at trust boundaries only.
