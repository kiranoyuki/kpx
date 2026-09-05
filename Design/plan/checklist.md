# KPX — Build Checklist

Standing rules live in `conventions.md` and are not repeated here. A step may take 1–3 PRs;
the size rule wins. Tick a box only when its **Verify** line has actually been run.

**Progress:** rules ported 0 / 89 · steps done 0 / 25 planned

| | Phase | Steps | Rules | Proves |
|---|---|---|---|---|
| A | Foundation — the stack, no business logic | 1–13 | — | the tools work |
| B0 | Register a patient | 14–18 | 0 | the plumbing works, end to end |
| B1 | Appointments | 19–25 | 1–6 | the architecture works, under a cross-entity invariant |
| C | Clinic setup and staff | 26+ | 0 | |
| P | Patient app — the second front end | P1–P6 | 88–89 | one API serves two audiences |
| D+ | Remaining modules | | 7–87 | |

Two slices before the rest, deliberately: B0 debugs React, Ant Design, TanStack Query,
Fastify, Zod, Kysely and Playwright against a workflow carrying **no catalogue rules and no
cross-entity invariants**. B1 then adds a check-then-write rule to a stack already known to
work. Debugging both at once is what this ordering avoids.

Layout: `src/api/`, `src/ui-clinic/` and `src/ui-patient/` alongside the existing `db/` and
`Design/`. This supersedes `backend-skeleton.md`, which placed the API at `api/`.

## Repo layout and the shared contract

**Three independent packages. There is no root `package.json`.**

```
src/api/          package.json  package-lock.json  tsconfig.json  node_modules/
src/ui-clinic/    package.json  package-lock.json  tsconfig.json  node_modules/
src/ui-patient/   package.json  package-lock.json  tsconfig.json  node_modules/   ← Phase P
```

**Why two front ends.** Patients book and follow their own treatment on a public app;
receptionists and staff run the clinic on an internal one. They share the API — one database,
one set of rules, so a self-booked slot and a front-desk slot cannot conflict — and share
nothing else. The domain model has said this from the start: `v_portal_access` returns
`patient_portal` and `staff_portal` as separate answers, derived from which profile a person
holds rather than from their `role`.

Not an npm workspace, deliberately. A workspace means one root lockfile, which two people —
or two agents — working in parallel rewrite simultaneously, producing a conflict in the file
that is worst to merge. The cost is some duplicated devDependency versions; the benefit is
that the packages share no mutable file. That argument gets stronger with three packages, not
weaker. When shared types are genuinely needed, add a fourth package as a deliberate decision.

**The two UI packages share no code by default.** The step 11 fetch wrapper is about fifty
lines; `ui-patient` gets its own copy when Phase P arrives. Error codes travel in the response
body, so neither app needs a shared constants file. Revisit only if the duplication grows past
a page.

**Fixed now so nothing renegotiates it later:**

| | |
|---|---|
| Node | 22 LTS |
| API port | 3000 |
| `ui-clinic` dev port | 5173 |
| `ui-patient` dev port | 5174 |
| Vite proxy (both UIs) | `/api` → `http://localhost:3000`, no rewrite |
| API base in both UIs | relative `/api` — never an absolute origin |
| Route prefix | every API route lives under `/api`, in one of the three groups below |
| Health | `GET /api/health` → `{ status, foreignKeys, journalMode }` |

### Three route groups, one per audience

| Group | Principal | Notes |
|---|---|---|
| `/api/clinic/*` | staff — required | everything the internal app calls |
| `/api/public/*` | anonymous | rate-limited; the only unauthenticated writes in the system |
| `/api/patient/*` | authenticated patient | **not registered until Phase J** — see `conventions.md` §15 |
| `/api/health` | none | unchanged |

The group is what makes authorization structural rather than a per-route habit: a
patient-facing endpoint cannot be reached with staff semantics because it lives in a
different group behind a different principal resolver. Fixing the prefixes now costs a line;
retrofitting them after Phase C is a churn PR touching every route file for no behaviour
change.

**Directory ownership.** `src/api/**`, `src/ui-clinic/**` and `src/ui-patient/**` are owned
separately and never edited together in one PR. `Design/**` and `db/**` are owned by neither
and stay frozen during implementation work — with exactly one scheduled exception, step P1,
which adds `db/modules/1001_booking_request_schema.sql`.

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

## Step 2 — Clinic UI skeleton at `src/ui-clinic/`

- [ ] Vite + React + TypeScript
- [ ] **Ant Design** installed, `ConfigProvider` at the root with `viVN` wired but English for now
- [ ] React Router with an `AppLayout`: AntD `Layout` + `Sider` nav + `Content` —
      the internal-tool shape, which is why the patient app cannot reuse it
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

## Step 6 — The principal (stub)

Not "the acting user" — a **principal**, because three kinds of caller now exist and the
route group decides which one is required (`conventions.md` §15).

- [ ] `context/principal.ts` resolves `{ kind: 'staff' | 'patient' | 'anonymous', userId? }`
- [ ] `/api/clinic/*` requires `kind === 'staff'`, else 401
- [ ] `/api/public/*` reads no auth header at all — anonymous is the expected principal there
- [ ] `/api/patient/*` is **not registered**; it arrives with real auth in Phase J
- [ ] Staff is verified against **`v_portal_access.staff_portal = 'yes'`**, not merely "an
      `app_user` row exists" — the weaker check would let a **Departed** doctor's id still act
- [ ] Reads `X-Acting-User`; refuses to load unless `ALLOW_STUB_AUTH=true`
- [ ] Marked `// TODO(auth):`

**Verify:** clinic route, no header → 401 · clinic route, unknown id → 401 · clinic route, a
**Departed** staff id → 401 · public route, no header → 200 · `ALLOW_STUB_AUTH` unset → the
app refuses to boot rather than starting insecurely.

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

## Step 11 — Clinic UI ↔ API

- [ ] `src/ui-clinic/api/client.ts` — fetch wrapper unwrapping `{ error: { code, message } }`
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
- [ ] Jobs run **per package** — once `src/ui-patient/` exists it joins as its own matrix
      entry, with its own `e2e` run. No job spans two packages

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
- [ ] `people.routes.ts` registers `POST /api/clinic/patients`, unpacks deps, calls the use case
- [ ] `register-patient.ts` imports no zod and no Fastify type

**16b — read**
- [ ] `get-patients.ts` + `get-patients.http.ts` + `GET /api/clinic/patients?q=` for the list screen

**Verify:** `fastify.inject()` tests for 201, 400 on a bad body, 409 on a duplicate
`national_id`, and a list response carrying ids.

## Step 17 — The clinic UI  *(2 PRs)*

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
- [ ] `GET /api/clinic/appointments?date=` with a zod response schema

**Verify:** rows each carry `appointmentId`.

## Step 21 — Book an appointment  *(rule 2)*

- [ ] `modules/scheduling/book-appointment.ts` — one sync function inside `write()`
- [ ] `modules/scheduling/domain/chair-overlap.ts` — the pure overlap predicate
- [ ] Rule 2 → `CHAIR_DOUBLE_BOOKED`
- [ ] `POST /api/clinic/appointments`

**Verify:** book into a free chair → 201. Book an overlapping time in the same chair →
**409 `CHAIR_DOUBLE_BOOKED`**. The overlap predicate is unit-tested exhaustively with no
database: touching ends, containment, identical ranges, zero-length.

## Step 22 — The remaining booking rules  *(rules 1, 4, 5, 6)*

- [ ] Rule 1 — chair is not Available
- [ ] Rules 4, 5 — doctor / assistant not bookable (OnLeave, Departed)
- [ ] Rule 6 — doctor double-booked

**Verify:** one test per rule asserting its **code**. Rules ported: 6 / 89.

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

## Step 25 — Booking UI (`ui-clinic`), E2E, then review

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
- [ ] **Phase P — Patient app** · rules 88–89 · the second front end and the public API surface. Expanded below, because it is the one phase whose shape is already decided
- [ ] **Phase D — Treatment planning** · rules 7–14 · append-only decision chain; `treatment_procedure.status` becomes a view
- [ ] **Phase E — Clinical record** · rules 15–19 · odontogram: 52 teeth × conditions × planned work
- [ ] **Phase F — Billing** · rules 21–34 · **blocked by `open-questions.md`**, and the first phase requiring idempotency keys (`conventions.md` §7)
- [ ] **Phase G — Inventory** · rules 35–42 · FEFO and expiry; `quantity_on_hand` becomes a view
- [ ] **Phase H — Payroll & commission** · rules 43–72 · the largest by far. Splits into attendance (48–52) · entries (53–61) · settlement (44–47, 62–65) · approval and locking (43, 66–71)
- [ ] **Phase I — Notifications** · rules 73–87 · needs the outbox from `conventions.md` §3: rows written inside the causing transaction, dispatched after commit
- [ ] **Phase J — Hardening** · real auth replacing the stub · **Phase P2, the authenticated patient portal** · Vietnamese by filling `vi` in `catalogue.ts` · the golden-ledger regression test · the parallel run against the clinic's current process

---

# Phase P — Patient app

Placed after C because the patient app is a second front end onto a clinic that must already
work: services, staff and chairs have to exist before a stranger can ask for an appointment.

**What ships here is the public half only.** Services, address, contact, request an
appointment, check that request's status. No login, no records — the authenticated portal is
Phase P2, and it is blocked twice over: by Phase E for anything to show, and by Phase J for
an auth mechanism safe to expose on the internet. `X-Acting-User` never faces the public
internet.

**Booking is a request, not a booking.** A patient submits a preferred time; a receptionist
reviews it and books the actual appointment through the step 21 use case, where rules 1–6
already apply. The patient app never picks a doctor or a chair.

Why a `booking_request` table rather than a chairless `appointment` row: `appointment.chair_id`
is nullable, and its own schema comment says why that is dangerous — *"an appointment with no
chair consumes no capacity, so a booking flow that skips it can quietly overbook the clinic"*
(`db/modules/0301_scheduling_schema.sql`). A chairless placeholder is precisely that flow, and
rule 2 never fires on it. A separate entity keeps `appointment` meaning *a slot actually
reserved*.

Steps are lettered so they do not collide with the unassigned 26+ numbering.

## Step P1 — Schema module 10: `booking_request`

The one scheduled exception to the `db/**` freeze.

- [ ] `db/modules/1001_booking_request_schema.sql` — depends on modules 1, 2, 3; no cycle
- [ ] `status` in `Pending | Booked | Declined | Withdrawn`; `appointment_id` set on booking;
      `reference_code` unique, and the only thing the patient quotes
- [ ] CHECKs: Booked implies an `appointment_id` · Declined implies a reason ·
      `handled_by` and `handled_at` are set together
- [ ] `db/modules/1009_booking_request_seed.sql` — a pending request, a booked one, a
      declined one, and one whose phone already matches an existing `app_user`

**Verify:** `db/build.sh` clean · `PRAGMA foreign_key_check` zero rows · one negative test
per constraint, per `build-plan.md`.

## Step P2 — Workflow doc

- [ ] `Design/workflows/online-booking-request.md`, status `Draft`
- [ ] R-rules: a request may only be handled once (88) · booking a request writes the
      appointment and the request's new status in **one** transaction (89) · declining needs
      a reason
- [ ] E-examples: submitted then booked · submitted then declined · a second attempt to book
      an already-booked request · a request whose phone matches an existing patient

**Verify:** a reader can predict the API's behaviour from the doc alone.

## Step P3 — Public API  *(2 PRs)*

**P3a — reads**
- [ ] `GET /api/public/services` — names and categories from `service_category`
- [ ] `GET /api/public/booking-requests/:reference` — **status only**, no patient data

**P3b — write**
- [ ] `POST /api/public/booking-requests` — the only unauthenticated write in the system
- [ ] Rate-limited, `// TODO(step-J):` for verification (`open-questions.md`)

**Verify:** submit with no auth header → 201 with a reference · look the reference up → its
status and nothing else · a wrong reference → 404, not a 403 that confirms it exists.

## Step P4 — Clinic API  *(rules 88, 89)*

- [ ] `GET /api/clinic/booking-requests?status=Pending` — the reception queue
- [ ] `modules/scheduling/book-from-request.ts` — one `write()`: insert the appointment via
      the step 21 path, then mark the request `Booked` with its `appointment_id`
- [ ] `modules/scheduling/decline-request.ts`
- [ ] Rule 88 → `BOOKING_REQUEST_ALREADY_HANDLED`
- [ ] **Rollback test** (`conventions.md` §11) — this command writes twice: force a failure
      after the appointment insert and assert **neither** the appointment nor the status change
      persists

**Verify:** booking a Pending request → 200, and the appointment carries the booking rules ·
booking it twice → 409 `BOOKING_REQUEST_ALREADY_HANDLED` · booking into a taken chair → 409
`CHAIR_DOUBLE_BOOKED`, and the request stays Pending.

## Step P5 — `src/ui-patient/` skeleton and the public screens  *(2 PRs)*

**P5a — skeleton**
- [ ] Vite + React + TypeScript + AntD, dev port 5174, proxy `/api` → 3000
- [ ] A **public-marketing layout — no `Sider`**. Copying `ui-clinic`'s `AppLayout` is the
      mistake this phase exists to avoid
- [ ] Its own copy of the fetch wrapper

**P5b — screens**
- [ ] Services · address · contact — patient requirements 2, 3, 4
- [ ] Booking request form, and the "check my request" lookup — requirement 1

**Verify:** by hand on a phone-width viewport. Stop the API → a readable error, not a blank page.

## Step P6 — Clinic queue screen, E2E, then review

- [ ] Pending-requests table in `ui-clinic`, with Book and Decline
- [ ] Playwright, across both apps: submit on the patient app → appears in the clinic queue →
      reception books it → the reference now reads Booked
- [ ] `/code-review` **and `/security-review`** — this is the first publicly reachable surface
- [ ] `Design/workflows/online-booking-request.md` → `Stable`

**Verify:** both e2e suites green. Rules ported: 8 / 89. **Stop and walk the patient app
through with someone who has never seen the clinic app.**

---

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
| `scheduling/domain/request-transition.ts` | 88 | Step P4 |
