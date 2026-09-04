# KPX — Build Checklist

Standing rules live in `conventions.md` and are not repeated here. A step may take 1–3 PRs;
the size rule wins. Tick a box only when its **Verify** line has actually been run.

**Progress:** rules ported 0 / 87 · steps done 0 / 25 planned

| | Phase | Steps | Rules | Proves |
|---|---|---|---|---|
| A | Foundation — the stack, no business logic | 1–13 | — | the tools work |
| B0 | Register a patient | 14–18 | 0 | the plumbing works, end to end |
| B1 | Appointments | 19–25 | 1–6 | the architecture works, under a cross-entity invariant |
| C+ | Remaining modules | 26+ | 7–87 | |

Two slices before the rest, deliberately: B0 debugs React, Ant Design, TanStack Query,
Fastify, Zod, Kysely and Playwright against a workflow carrying **no catalogue rules and no
cross-entity invariants**. B1 then adds a check-then-write rule to a stack already known to
work. Debugging both at once is what this ordering avoids.

Layout: `src/api/` and `src/ui/` alongside the existing `db/` and `Design/`. This supersedes
`backend-skeleton.md`, which placed the API at `api/`.

## Repo layout and the shared contract

**Two independent packages. There is no root `package.json`.**

```
src/api/   package.json  package-lock.json  tsconfig.json  node_modules/
src/ui/    package.json  package-lock.json  tsconfig.json  node_modules/
```

Not an npm workspace, deliberately. A workspace means one root lockfile, which two people —
or two agents — working in parallel rewrite simultaneously, producing a conflict in the file
that is worst to merge. The cost is some duplicated devDependency versions; the benefit is
that the two packages share no mutable file. When shared types are genuinely needed, add a
third package as a deliberate decision.

**Fixed now so nothing renegotiates it later:**

| | |
|---|---|
| Node | 22 LTS |
| API port | 3000 |
| UI dev port | 5173 |
| Vite proxy | `/api` → `http://localhost:3000`, no rewrite |
| Route prefix | **every** API route lives under `/api` |
| Health | `GET /api/health` → `{ status, foreignKeys, journalMode }` |

**Directory ownership.** `src/api/**` and `src/ui/**` are owned separately and never edited
together in one PR. `Design/**` and `db/**` are owned by neither and stay frozen during
implementation work.

---

# Phase A — Foundation

No business logic in this phase. Its only job is that every later step is copy-the-pattern.

## Step 1 — Backend skeleton at `src/api/`

- [ ] `package.json`, `tsconfig.json`, `.env.example`, `eslint.config.js` — all inside `src/api/`, none at the repo root
- [ ] Fastify, TypeScript, Vitest, tsx installed
- [ ] `src/app.ts` exports `buildApp()` returning a `FastifyInstance` — **never listens**, so tests can import it
- [ ] `src/main.ts` boots, listens on 3000, handles graceful shutdown
- [ ] `src/config.ts` parses and validates env once, typed
- [ ] `GET /api/health` → `{ status: "ok" }`
- [ ] Scripts: `dev`, `build`, `typecheck`, `lint`, `test`

**Verify:** `npm run dev` starts · `curl localhost:3000/api/health` → 200 · `npm run
typecheck` and `npm test` both pass.

## Step 2 — UI skeleton at `src/ui/`

- [ ] Vite + React + TypeScript
- [ ] **Ant Design** installed, `ConfigProvider` at the root with `viVN` wired but English for now
- [ ] React Router with an `AppLayout`: AntD `Layout` + `Sider` nav + `Content`
- [ ] Two placeholder pages so navigation is real
- [ ] TanStack Query provider wired (used from step 11)
- [ ] Vite dev proxy `/api` → `localhost:3000`

**Verify:** `npm run dev` serves a styled page, nav switches routes, no console errors.

## Step 3 — Database connection

- [ ] `db/connection.ts` — one long-lived `better-sqlite3` handle to `db/kpx.db`
- [ ] Pragmas set once at open: `foreign_keys = ON`, `journal_mode = WAL`, `busy_timeout = 5000`, `synchronous = NORMAL`
- [ ] `kysely-codegen` script → `db/schema.d.ts`, committed
- [ ] `/api/health` extended to report `foreignKeys` and `journalMode`

**Verify:** `/api/health` → `{ status:"ok", foreignKeys:true, journalMode:"wal" }`. Foreign keys
reporting `false` here means a third of enforcement is silently off.

## Step 4 — Transactions

- [ ] `db/tx.ts` exporting `read()` and `write()`; `write()` wraps `db.transaction`
- [ ] Header comment stating the allowed/forbidden list from `conventions.md` §3
- [ ] ESLint rule forbidding `await` anywhere inside a `write()` callback

**Verify:** a test writes two rows and throws between them → neither row persists. Add a
deliberate `await` inside a `write()` → **lint fails**. Remove it.

## Step 5 — Error layer  *(3 PRs)*

**5a — contract**
- [ ] `shared/errors/AppError.ts` — code + HTTP status + message key
- [ ] `shared/errors/handler.ts` — one response shape: `{ error: { code, message, field? } }`

**5b — translation**
- [ ] `shared/errors/translate.ts` — SQLite error → `AppError`

**5c — catalogue**
- [ ] `shared/errors/catalogue.ts` — the machine-readable source of truth: `code → { rule, en, vi }`, `vi` null for now
- [ ] `shared/errors/constraint-map.ts` — the 65 named `ck_*` constraints → code
- [ ] `Design/rule-catalogue.md` gets a header noting `catalogue.ts` is authoritative for runtime wording

**Verify:** force a named CHECK violation → 422 with the right **code**. Force a foreign-key
violation → 422, not a 500. Unknown SQLite error → 500 with no internals leaked.

## Step 6 — Acting user (stub)

- [ ] `context/actingUser.ts` reads `X-Acting-User`, verifies the row exists, attaches it
- [ ] Refuses to load unless `ALLOW_STUB_AUTH=true`
- [ ] Marked `// TODO(auth):`

**Verify:** no header → 401 · unknown id → 401 · `ALLOW_STUB_AUTH` unset → the app refuses
to boot rather than starting insecurely.

## Step 7 — Test harness

- [ ] `test/helpers/db.ts` builds a fresh seeded database per test file
- [ ] `test/helpers/api.ts` wraps `buildApp()` + `fastify.inject()`
- [ ] Helpers inject `FixedClock` and `SeqIds` by default (step 9)
- [ ] Teardown removes temp files

**Verify:** two test files each insert the same id and both pass — proving isolation.

## Step 8 — `shared/money.ts`

- [ ] Integer đồng: add, subtract, `applyBasisPoints`, named rounding policies, format
- [ ] **No floating-point rates** — 15% is `1500`, not `0.15` (`conventions.md` §5)
- [ ] Table-driven tests including rounding and negative (credit) amounts

**Verify:** `npm test` green, runtime in milliseconds, no database touched.

## Step 9 — `shared/clock.ts` and `shared/ids.ts`

- [ ] `Clock` interface; `SystemClock` for production, `FixedClock(iso)` for tests
- [ ] `shared/time.ts` — `Instant` / `LocalDate` / `LocalTime` and the `Asia/Ho_Chi_Minh` constant (`conventions.md` §4)
- [ ] ESLint ban on constructing a `Date` from a `YYYY-MM-DD` string outside `time.ts`
- [ ] `Ids` interface; `UuidIds` for production, `SeqIds(prefix)` for tests
- [ ] Resolved by Fastify, **passed to use cases as plain deps** — no `modules/` file imports a Fastify type (`conventions.md` §2)
- [ ] ESLint rule banning `new Date()` and `Date.now()` inside `modules/` and `shared/` — except in `clock.ts`

**Verify:** a test with `FixedClock('2026-09-04T10:00:00Z')` reads that exact time from a
use case. Add a bare `new Date()` in a module → **lint fails**.

## Step 10 — The dependency boundary

- [ ] ESLint `no-restricted-imports` on `shared/` and `modules/*/domain/`: no Kysely, Fastify, `better-sqlite3`, `node:*`, or cross-module imports
- [ ] `shared/` additionally may not import `modules/`

**Verify:** add `import Database from 'better-sqlite3'` to `shared/money.ts` → lint fails.
Remove it.

## Step 11 — UI ↔ API

- [ ] `src/ui/api/client.ts` — fetch wrapper unwrapping `{ error: { code, message } }`
- [ ] Errors surfaced through AntD `message` / `Alert`, keyed on `code`
- [ ] Health page displaying the backend status

**Verify:** stop the API → the UI shows a readable error, not a blank screen or a raw stack.

## Step 12 — Playwright

- [ ] Installed and configured to start both dev servers
- [ ] One smoke test: load the app, see the nav

**Verify:** `npm run e2e` passes from a clean checkout.

## Step 13 — CI

- [ ] GitHub Actions: `typecheck`, `lint`, `test`, `e2e` on push
- [ ] `db/build.sh` runs in CI so tests use a freshly built database

**Verify:** push a branch, see all four jobs green.

---

# Phase B0 — Register a patient

**No catalogue rules, and no cross-entity invariants.** It does carry ordinary local
validation — required fields, `national_id` unique when present, provisional until verified
— and that is welcome: it exercises the error path. What it has none of is a rule that must
read *other rows* to decide, which is the class that can be subtly wrong.

Not a single-table insert either: §1 and §2 split the person from the care relationship, so
registering a walk-in writes `app_user` **and** `patient_profile` in one transaction. That
gives step 15 a genuine rollback test.

## Step 14 — Workflow doc

- [ ] `Design/workflows/register-patient.md`, status `Draft`
- [ ] R-rules: required identity fields; `national_id` unique when present; provisional vs verified on arrival
- [ ] E-examples: walk-in verified on arrival · online booker left provisional · duplicate `national_id` rejected

**Verify:** a reader can predict the API's behaviour from the doc alone.

## Step 15 — The use case

- [ ] `modules/people/register-patient.ts` — one `write()`: insert `app_user`, then `patient_profile`
- [ ] `modules/people/people.repository.ts`
- [ ] `register-patient.test.ts`, including a forced mid-transaction failure leaving **no orphan `app_user`**

**Verify:** both rows land together, or neither does.

## Step 16 — The routes  *(2 PRs)*

**16a — write**
- [ ] `register-patient.http.ts` — zod request/response schemas, mapping to `RegisterPatientInput`
- [ ] `people.routes.ts` registers `POST /api/patients`, unpacks deps, calls the use case
- [ ] `register-patient.ts` imports no zod and no Fastify type

**16b — read**
- [ ] `get-patients.ts` + `get-patients.http.ts` + `GET /api/patients?q=` for the list screen

**Verify:** `fastify.inject()` tests for 201, 400 on a bad body, 409 on a duplicate
`national_id`, and a list response carrying ids.

## Step 17 — The UI  *(2 PRs)*

**17a — list**
- [ ] Patient list: AntD `Table` with search, via TanStack Query

**17b — form**
- [ ] Register form: AntD `Form`, field-level errors from `error.field`

**Verify:** by hand — register someone, see them in the list, submit a duplicate and read the
error against the right field.

## Step 18 — E2E, then review

- [ ] Playwright: open form → register → appears in list
- [ ] `/code-review`, findings resolved
- [ ] `Design/workflows/register-patient.md` → `Stable`

**Verify:** `npm run e2e` green. **Stop and walk the screen through with whoever will use
it before starting B1.**

---

# Phase B1 — Appointments

The stack is now known to work, so this slice adds the thing that actually needs proving:
rule 2 is a check-then-write invariant that reads other rows, which is the class of rule the
removed triggers used to hold.

**What this phase does and does not prove.** It proves the invariant holds under the
supported deployment model — one application process writing `db/kpx.db`
(`conventions.md` §3). It is **not** a distributed-concurrency guarantee, and no test here
can be. A second writer process would break it silently.

## Step 19 — Workflow doc

- [ ] `Design/workflows/booking.md`, status `Draft`
- [ ] R-rules restating catalogue rules 1–6, each naming its **code**
- [ ] E-examples: a free slot · an overlapping chair · an overlapping doctor · a departed doctor
- [ ] Decide the clinic-hours gap flagged in §5 — booking needs doctor free, chair free, **and clinic open**, and the third has no entity yet

**Verify:** a reader can predict the API's behaviour from the doc alone.

## Step 20 — Read: the day sheet

- [ ] `modules/scheduling/get-day-sheet.ts`
- [ ] Returns **ids alongside labels** — `v_day_sheet` omits `appointment_id`, so the view cannot back this endpoint
- [ ] `GET /api/appointments?date=` with a zod response schema

**Verify:** rows each carry `appointmentId`.

## Step 21 — Book an appointment  *(rule 2)*

- [ ] `modules/scheduling/book-appointment.ts` — one sync function inside `write()`
- [ ] `modules/scheduling/domain/chair-overlap.ts` — the pure overlap predicate
- [ ] Rule 2 → `CHAIR_DOUBLE_BOOKED`
- [ ] `POST /api/appointments`

**Verify:** book into a free chair → 201. Book an overlapping time in the same chair →
**409 `CHAIR_DOUBLE_BOOKED`**. The overlap predicate is unit-tested exhaustively with no
database: touching ends, containment, identical ranges, zero-length.

## Step 22 — The remaining booking rules  *(rules 1, 4, 5, 6)*

- [ ] Rule 1 — chair is not Available
- [ ] Rules 4, 5 — doctor / assistant not bookable (OnLeave, Departed)
- [ ] Rule 6 — doctor double-booked

**Verify:** one test per rule asserting its **code**. Rules ported: 6 / 87.

## Step 23 — Reschedule  *(rule 3)*

- [ ] `modules/scheduling/reschedule-appointment.ts` — its own use case, **not** a `PATCH` on the time column
- [ ] Rule 3 — chair overlap re-checked on move

**Verify:** move to a free slot → 200; move into a conflict → 409; the appointment id is
unchanged in both cases.

## Step 24 — Catalogue coverage

- [ ] `modules/scheduling/scheduling.catalogue.test.ts` — every code the module can emit exists in `shared/errors/catalogue.ts` with non-empty `en` and a `rule` number in 1–6
- [ ] Update the coverage count from `catalogue.ts`, not from the Markdown

**Verify:** change the wording of `CHAIR_DOUBLE_BOOKED` in `catalogue.ts` → **no test
fails**, because no test asserts wording. Delete the entry → this test fails and the rule
tests still pass. That separation is the whole point.

## Step 25 — Booking UI, E2E, then review

- [ ] Day sheet: AntD `Table`, date picker, chair and doctor columns
- [ ] Booking form: AntD `Form` + `DatePicker`/`TimePicker` + `Select`
- [ ] Playwright: book → appears in list; attempt an overlap → error visible
- [ ] `/code-review`, findings resolved
- [ ] `Design/workflows/booking.md` → `Stable`

**Verify:** `npm run e2e` green. **Stop and review with a real user before Phase C.**

---

# Phase C onward

Expanded into numbered steps only when reached — distant detail would be invented, not
planned. Order follows `rule-catalogue.md`, which is also foreign-key order.

- [ ] **Phase C — Clinic setup and staff** · 0 rules · chairs, chair types, service catalog, staff records. Pure CRUD on a proven stack
- [ ] **Phase D — Treatment planning** · rules 7–14 · append-only decision chain; `treatment_procedure.status` becomes a view
- [ ] **Phase E — Clinical record** · rules 15–19 · odontogram: 52 teeth × conditions × planned work
- [ ] **Phase F — Billing** · rules 21–34 · **blocked by `open-questions.md`**, and the first phase requiring idempotency keys (`conventions.md` §7)
- [ ] **Phase G — Inventory** · rules 35–42 · FEFO and expiry; `quantity_on_hand` becomes a view
- [ ] **Phase H — Payroll & commission** · rules 43–72 · the largest by far. Splits into attendance (48–52) · entries (53–61) · settlement (44–47, 62–65) · approval and locking (43, 66–71)
- [ ] **Phase I — Notifications** · rules 73–87 · needs the outbox from `conventions.md` §3: rows written inside the causing transaction, dispatched after commit
- [ ] **Phase J — Hardening** · real auth replacing the stub · Vietnamese by filling `vi` in `catalogue.ts` · the golden-ledger regression test · the parallel run against the clinic's current process

## Domain files, and the phase that first needs each

Pure, dependency-free, and therefore writable at any time — none is blocked by phase order.

| File | Rules | Needed by |
|---|---|---|
| `shared/money.ts` | — | Step 8 |
| `shared/clock.ts`, `shared/ids.ts` | — | Step 9 |
| `scheduling/domain/chair-overlap.ts` | 2, 3, 6 | Step 21 |
| `catalog/domain/price-resolution.ts` | — | Phase D |
| `billing/domain/invoice-totals.ts` | 25, 29, 31 | Phase F |
| `billing/domain/payment-settlement.ts` | 33 | Phase F |
| `inventory/domain/fefo.ts` | 39, 40 | Phase G |
| `payroll/domain/wage-resolution.ts` | 48 | Phase H |
| `payroll/domain/commission-amount.ts` | 53–56, 61 | Phase H |
| `payroll/domain/payroll-arithmetic.ts` | 66–69 | Phase H |
