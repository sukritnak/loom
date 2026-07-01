# Loom Architecture Guidelines

Team standard for **backend** (hexagonal — strict) and **frontend** (clean layered — **not** a hexagonal clone).  
BE and FE share principles (dependency inward, thin edges, testable core) but **different folder names and enforcement**.

| Area | Doc part | Strictness |
|------|----------|------------|
| Backend (all stacks) | **Part B** | High — hexagonal layout required on `mode: new` |
| Frontend | **Part C** | Pragmatic — clean/feature-first; adapt to Next/Vite/Nuxt |
| BE ↔ FE contract | **Part D** | Types, errors, API alignment |
| Handoff / editor switch | **Part E** | Required every agent return |

**Agents:** `loom-full-stack` SR-reviews · `loom-be` → Part B · `loom-fe` → Part C · **handoff** on every step end

---

# Part A — Shared principles (not shared folder names)

## Backend glossary (Part B only)

| Term | Meaning | Location |
|------|---------|----------|
| **Port** | Interface contract | `application/ports/` only |
| **Adapter** | Implementation / mapper | `adapter/inbound|outbound/` |
| **Use case** | Orchestrates domain + ports | `application/usecases/` |
| **Command / Query / Result** | Use-case I/O | `application/commands|queries|results/` |
| **Body / Response** | HTTP transport | `adapter/inbound/dtos/` |
| **Composition root** | DI wiring | modules / `main` |

**BE golden rules:** ports never under `adapter/` · use cases never import HTTP/ORM types.

## Frontend vocabulary (Part C — different words)

| Concept | FE location | Notes |
|---------|-------------|-------|
| **View** | `components/` | Props in, events out — no `fetch` |
| **Feature hook** | `hooks/` or `api/` | TanStack Query wrappers — server state |
| **API module** | `infrastructure/api/` | Raw HTTP functions |
| **View-model types** | `types/` | UI shapes — not necessarily BE `Result` names |
| **Providers** | `app/providers.tsx` | Query client, theme — composition root |

**FE golden rules:** server truth stays on BE · server **data** via Query cache · no business rules only in client store.

Do **not** force FE to use `ports/`, `commands/`, or `usecases/` folders unless the team chooses that naming voluntarily.

## Dependency flow (backend)

```
HTTP Body → inbound adapter → Command/Query → use case → domain
                                              → outbound port ← outbound adapter → DB/API
                         ← Result ←
              Response Body
```

## Stack picker (`loop.config.json` → `stack`)

| `stack` value (examples) | Runtime | See section |
|--------------------------|---------|-------------|
| `nest`, `node`, `express` | Node/TS | [B1 NestJS/Node](#b1-nestjs--node-reference-tree) · TS packages → [typescript-packages.md](typescript-packages.md) |
| `go`, `golang`, `fiber`, `gin`, `echo` | Go | [B2 Go](#b2-go) |
| `fastapi`, `python` | Python | [B3 FastAPI](#b3-fastapi) |
| `django` | Python | [B4 Django](#b4-django) |
| `nextjs`, `vite`, `react`, `nuxt`, `svelte` | JS/TS FE | [Part C — Frontend](#part-c--frontend) |
| other | — | Apply Part A layers; map folders to idiomatic layout |

---

# Part B — Backend (hexagonal)

## Logical layers (every BE stack)

```
domain/           — entities, value objects, domain errors (no framework imports)
application/      — ports, commands, queries, results, use cases
adapter/inbound/  — HTTP handlers, CLI, workers; maps Body ↔ Command/Query/Result
adapter/outbound/ — repositories, gateways, queues; mappers; ORM models
composition/      — wire ports → adapters (Nest modules, Go main, FastAPI deps, Django apps)
```

**Slice order (new entity):** domain model → outbound port → command/query/result → inbound port → use case → inbound adapter → outbound adapter.

## Naming (language-agnostic)

| Kind | Pattern |
|------|---------|
| Inbound port | `CreateProductPort` / `create_product_port.py` |
| Outbound port | `ProductRepositoryPort` |
| Use case | `CreateProductUseCase` / `create_product.py` |
| Command / Query / Result | `CreateProductCommand`, `ListProductsQuery`, `CreateProductResult` |
| HTTP body (adapter only) | `CreateProductBody`, Pydantic `CreateProductRequest` |
| Outbound adapter | `ProductRepositoryPostgres`, `product_repository_mongo.go` |

## Errors & transactions

- **Errors:** `domain/errors` → map to HTTP in inbound adapter (404/400/401/500, no stack leak).
- **Transactions:** use case calls `UnitOfWorkPort.run(...)`; repositories receive the active unit — controllers don't open transactions.

## Testing

| Layer | Focus |
|-------|--------|
| Domain | pure rules, no mocks |
| Use case | fake outbound ports |
| Outbound adapter | contract tests per port |
| Inbound adapter | Body ↔ Command, error → status |
| E2E | HTTP through real stack |

## Anti-patterns (backend)

Port interfaces under `adapter/` · use case imports HTTP/ORM · business logic in controllers/views · DB rows returned from use cases · adapters calling adapters around use cases.

---

## B1 NestJS / Node (reference tree)

```
src/
├── domain/{model,value-objects,services,errors}/
├── application/
│   ├── ports/{inbound,outbound}/
│   ├── commands/ · queries/ · results/
│   └── usecases/
├── adapter/
│   ├── inbound/{controllers,dtos,filters,guards,mappers}/
│   └── outbound/{mappers,repositories}/
├── configs/ · common/tokens/
├── app.module.ts                    # composition root
```

**Composition:** `ApplicationModule` (use cases) · `AdapterModule` (controllers) · `{db}.repositories.ts` (port → impl).

---

## B2 Go

Idiomatic Go uses `internal/` and explicit constructors — same boundaries.

```
cmd/api/main.go                      # composition root — wire all deps
internal/
├── domain/
│   ├── product.go                   # entity + domain errors
│   └── errors.go
├── application/
│   ├── ports/
│   │   ├── inbound/create_product.go    # interface CreateProductUseCase
│   │   └── outbound/product_repository.go
│   ├── commands/create_product.go
│   ├── queries/list_products.go
│   ├── results/create_product.go
│   └── usecases/create_product.go       # struct + Execute(cmd) (result, error)
└── adapter/
    ├── inbound/http/
    │   ├── router.go
    │   ├── handlers/product_handler.go
    │   └── dto/create_product_body.go   # JSON tags — maps to Command
    └── outbound/postgres/
        ├── product_repository.go        # implements ProductRepository
        └── product_mapper.go
```

**Notes:** ports are Go `interface` in `application/ports/`. Use case struct holds outbound interfaces. `main.go` builds adapters → inject into use cases → pass to handlers. Prefer `pgx`/`sqlc` over ORM in adapter. Table-driven tests for use cases with fakes.

---

## B3 FastAPI

```
src/
├── main.py                            # FastAPI app + lifespan (composition)
├── domain/
│   ├── models/product.py
│   └── errors/product_not_found.py
├── application/
│   ├── ports/inbound/ · outbound/
│   ├── commands/ · queries/ · results/
│   └── usecases/create_product.py
└── adapter/
    ├── inbound/api/
    │   ├── routers/products.py        # Depends(use_case)
    │   ├── schemas/create_product_body.py   # Pydantic — HTTP only
    │   └── exception_handlers.py
    └── outbound/
        ├── mappers/product_mapper.py
        └── repositories/product_repository_postgres.py
```

**Notes:** Pydantic schemas = **Body/Response** (adapter), not Command/Result — map in router. Use `Depends()` factory in `composition/deps.py` for wiring. Async use cases OK; keep domain sync when possible.

---

## B4 Django

Django is opinionated — treat **views/serializers as inbound adapters**, **ORM as outbound adapter**, business logic in **use cases**.

```
src/   (or project root app)
├── domain/
│   ├── models/product.py              # pure dataclasses — NOT django.db.models
│   └── errors/
├── application/
│   ├── ports/ · commands/ · queries/ · results/
│   └── usecases/
├── adapter/
│   ├── inbound/
│   │   ├── api/views/product_views.py
│   │   ├── api/serializers/create_product_body.py
│   │   └── urls.py
│   └── outbound/
│       ├── mappers/
│       └── repositories/product_repository_orm.py   # Django ORM here only
├── config/                            # settings, wsgi, asgi
└── manage.py
```

**Notes:** do **not** put business rules in `models.Model.save()` or fat views. Optional: Django REST Framework viewsets call use cases. Migrations stay with ORM adapter / Django apps as infrastructure concern.

---

## Backend bootstrap checklist

- [ ] `domain/`, `application/`, `adapter/` (names per stack section above)
- [ ] `application/ports/inbound/` + `outbound/` — no ports in adapter
- [ ] `commands/`, `queries/`, `results/`
- [ ] `adapter/outbound/mappers/` — not `ports/`
- [ ] Composition root wired (modules / `main` / `deps`)
- [ ] `.env.template` + secrets gitignored
- [ ] Health endpoint + error mapping

---

# Part C — Frontend (clean architecture, not hexagonal)

> **FE does not mirror Part B folder-for-folder.** Goal: **clean, colocated, testable** UI — inspired by clean/hex ideas (thin edges, thick boundaries) using idiomatic React/Vue/Svelte patterns.  
> Sources: [Next.js colocation](https://nextjs.org/docs/app/getting-started/project-structure), [TanStack Query custom hooks](https://tanstack.com/query/latest/docs/framework/react/overview).

## Clean FE layers (conceptual)

```
Presentation     components/          UI only
Application      hooks/ · queries/      feature hooks, mutations, orchestration
Infrastructure   infrastructure/api/    fetch functions (no JSX)
Domain (light)   types/                 view-models, zod schemas for forms
```

Dependency direction: **components → hooks → api → http client** (never the reverse).

## Two valid layouts (pick one per project — record in STATE.md)

### C1 — Routes in `app/`, features outside (recommended for medium+ apps)

```
src/
├── app/                         # Next App Router — routing only (+ layouts)
│   ├── providers.tsx            # QueryClientProvider, theme
│   └── (routes)/…/page.tsx      # thin — compose feature components
├── features/products/
│   ├── components/
│   ├── hooks/useProducts.ts     # useQuery / useMutation wrappers
│   ├── api/products.ts          # or re-export from infrastructure
│   └── types/product.ts
├── infrastructure/http/client.ts
├── shared/ui/ · shared/lib/
└── stores/ui.ts                 # optional Zustand — UI chrome only
```

### C2 — Colocation inside `app/` (recommended for small apps / Next-native)

Per [Next.js colocation](https://nextjs.org/docs/app/getting-started/project-structure): non-route files beside `page.tsx` stay private to the segment.

```
app/products/
├── page.tsx
├── _components/ProductList.tsx   # private folder or underscore convention
├── _hooks/useProducts.ts
└── _lib/products.api.ts
```

Use C2 until features spill across routes — then extract to C1 `features/`.

## TanStack Query patterns (standard)

- **One custom hook per query/mutation** — `useProducts`, `useCreateProduct` (not bare `useQuery` in components).
- **Query keys** colocated: `features/products/queries/keys.ts` or top of hook file.
- **API functions** in `infrastructure/api/` or `features/*/api/` — hooks call these, components call hooks.
- **Mutations** invalidate related query keys in `onSuccess` — no manual cache duplication in Zustand.

```tsx
// features/products/hooks/useProducts.ts
export function useProducts(filters: ProductFilters) {
  return useQuery({
    queryKey: productKeys.list(filters),
    queryFn: () => productsApi.list(filters),
  })
}
```

## State management (decision guide)

| Bucket | Tool |
|--------|------|
| Server state | **TanStack Query** (default) |
| URL state | `searchParams` / **nuqs** |
| Local UI | `useState` |
| Cross-feature UI | **Zustand** (sparingly) |
| Theme / locale | Context |
| Complex forms | **React Hook Form + Zod** |
| Redux | Legacy or explicit AC only |

## Component rules

- **Smart vs dumb:** pages/containers wire hooks; leaf components receive data + callbacks.
- **No `fetch` in components** — hooks or server actions only.
- **Error / loading / empty** — every data view handles all three.
- **Accessibility** — semantic HTML, labels, focus on interactive flows.

## SR review checks (FE — fullstack / fe)

| Check | Pass when |
|-------|-----------|
| Layering | No fetch in presentation; hooks own data |
| Server state | Query for API data; not duplicated in global store |
| Colocation | Feature code grouped; no god `utils/` dump |
| Boundaries | No BE-only business rules added on client |
| Naming | Consistent with `STATE.md` → Project context |

**Fail** only on maintainability/security/contract issues — not on missing BE-style `ports/` folders.

## FE anti-patterns

- God component with fetch + business logic + markup
- API list in Zustand when Query should own it
- Copy-paste query keys across features
- `shared/` becoming a junk drawer (promote to `features/` or delete)

## FE bootstrap checklist (`mode: new`)

- [ ] Pick C1 or C2; record in `STATE.md`
- [ ] Query provider in `providers.tsx`
- [ ] `infrastructure/http/client.ts` (base URL from env)
- [ ] One sample feature with hook + dumb component + loading/error/empty
- [ ] State choices documented
- [ ] No secrets in client bundle

`loom-fe` implements Part C — **not** Part B hex folders.

---

# Part D — API surface alignment (BE ↔ FE)

| BE | FE |
|----|-----|
| `CreateProductResult` | `types/product.ts` view-model |
| HTTP 404 + error body | hook maps to "not found" UI |
| `admin` vs `public` routes | `features/admin/` vs `features/shop/` |
| OpenAPI / Swagger | generate `infrastructure/api` types when available |

---

# Part E — Handoff & editor continuity

Every agent **must** leave enough context for the next agent, session, or editor (Cursor ↔ Claude Code ↔ Hermes).

## When to hand off

- End of any orch delegation (build, review, QA, fix round)
- User switches editor or starts a new chat
- Session near context limit — **compact early**, don't wait

## Two layers (use both)

| Layer | Where | Purpose |
|-------|-------|---------|
| **Durable** | `STATE.md` in control folder | Loop memory — orch reads first every run |
| **Step snapshot** | Agent return body + optional handoff doc | What just happened this step |

## Compact handoff block (required in every agent return)

```markdown
## Handoff summary
- **Goal:** (one line from STATE.md)
- **Done this step:** (bullets — what changed or was reviewed)
- **Files:** (paths touched)
- **Verified:** (commands run, or "not run — why")
- **Open / blockers:** (IDs, owners)
- **Next:** (single next action + owner: fe|be|fullstack|qa|orch|human)
- **Editor:** (cursor|claude|hermes — if switching, note what the other side must run)
```

Orch merges into `STATE.md` → `## Last handoff` and updates `## Next action`, `## Status board`.

## STATE.md updates (required)

At minimum before returning: `## Status board`, `## Next action`, `## Last handoff` (overwrite), relevant AC checkboxes if verified.

## Editor switch checklist

1. `git status` — know what's uncommitted
2. `STATE.md` current (goal, round, blockers, dev URLs)
3. `zsh tools/refresh.sh` on new machine or after pull (syncs agents)
4. **handoff** skill — optional `HANDOFF.md` in control folder for long notes
5. New editor: `Use loom-orch` or read `STATE.md` + `## Last handoff`

## Dashboard

Mirror the handoff summary: `zsh "$B/tools/dash.sh" report <id> …` before chat-only summaries.

---

*Document version: Loom blueprint — BE Part B strict; FE Part C pragmatic; Part E mandatory for all agents.*
