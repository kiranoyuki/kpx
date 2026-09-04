# KPX Backend Skeleton

## Context

The database is finished and clean: 9 modules, 43 tables, 37 views, all seeded and
committed (`f0ff49d`). The 56 triggers were deliberately removed — **business logic now
belongs to the API** (`Design/api-plan.md`), and every rule they enforced is captured in
`Design/rule-catalogue.md` (87 rules, each with the message the user should see).

That means the database currently **accepts bad data**: double-booked chairs, commission
on your own treatment, edits to the decision log. Closing that gap is the API's job.

This plan covers **the skeleton only** — the structure, the boot path, and the handful of
cross-cutting pieces every command will depend on. It does **not** port any of the 87
rules; that follows module by module once the shape is agreed.

**Profile that drives the design:** single clinic, very low DAU, correctness on edge
cases matters far more than throughput. Monolithic.

**Decided:** the API lives at `api/` alongside `db/` and `Design/` in this repo — schema
and the code that depends on it stay versioned together. Scope is the boot path **plus one
proven vertical slice**, so the assumptions everything else rests on are demonstrated
before 87 rules are built on them.

---

## The property that shapes everything

`better-sqlite3` is **synchronous**. Node is single-threaded. So while a synchronous
function runs, no other request handler can run — which means:

```ts
db.transaction(() => {
  if (chairIsTaken(chairId, at)) throw new Conflict('CHAIR_DOUBLE_BOOKED')
  insertAppointment(...)
})()
```

…is **genuinely atomic against other requests in this process.** The check-then-act race
that the triggers used to prevent is closed by the driver's synchrony, with no mutex.

This holds under two conditions, which the skeleton enforces rather than assumes:

1. **No `await` inside a transaction.** One `await` splits the sync block and reopens the
   race. This is the single most important rule in the codebase and gets an ESLint rule.
2. **One writer process.** Documented in the deploy notes, not just here.

---

## Structure

Vertical slices, one per database module, so a rule's schema, catalogue entry, and code
sit at the same coordinate.

```
api/
  package.json  tsconfig.json  .env.example  eslint.config.js
  src/
    main.ts                    # boot: build app, listen, graceful shutdown
    app.ts                     # buildApp() -> FastifyInstance, never listens (testable)
    config.ts                  # env parsed + validated once, typed

    db/
      connection.ts            # better-sqlite3 handle + pragmas, opened once
      schema.d.ts              # GENERATED from kpx.db by kysely-codegen
      tx.ts                    # read() / write() helpers; write() = transaction

    errors/
      AppError.ts              # code + http status + user message
      constraint-map.ts        # 65 named ck_* -> code + message
      translate.ts             # SQLite error -> AppError
      handler.ts               # Fastify error handler, single response shape

    context/
      actingUser.ts            # STUB until auth lands (X-Acting-User header)

    plugins/
      db.ts  context.ts  errors.ts   # fastify-plugin wrappers

    modules/
      people/ scheduling/ planning/ clinical/
      billing/ inventory/ payroll/ notifications/
        *.routes.ts            # HTTP shape only
        *.commands.ts          # writes: one sync transaction each
        *.queries.ts           # reads
        *.schemas.ts           # zod, request + response

  test/
    helpers/db.ts              # build a fresh seeded db per test file
```

`db/` and `Design/` stay where they are. The API reads `db/kpx.db`; `db/build.sh` remains
the only thing that creates it.

---

## The cross-cutting pieces

### 1. `db/connection.ts` — pragmas set once, not per request

```ts
db.pragma('foreign_keys = ON')   // OFF by default; a third of enforcement vanishes without it
db.pragma('journal_mode = WAL')
db.pragma('busy_timeout = 5000')
db.pragma('synchronous = NORMAL')
```

A single long-lived connection. This is why the pragma cannot be forgotten the way it can
with a pool.

### 2. `db/tx.ts` — the only way writes happen

`write(fn)` wraps `db.transaction`. Commands are written as sync functions and called
through it; nothing else opens a transaction. Enforced by lint, not convention.

### 3. `errors/` — the layer that replaces trigger messages

Two sources of failure, one response shape:

| Source | Example | Becomes |
|---|---|---|
| Command logic (the 87 ported rules) | `no commission on your own treatment` | 409 + code + message |
| A surviving DB constraint | `CHECK constraint failed: ck_pay_net` | 422 via `constraint-map.ts` |

**65 named `ck_*` constraints are mappable.** The other 111 CHECKs are unnamed and return
a fragment of their own SQL — but they are all enum/range/format shape checks that Zod
rejects at the boundary first, so they are a last-resort fallback, not a normal path.

Response shape, fixed now so nothing drifts:

```json
{ "error": { "code": "CHAIR_DOUBLE_BOOKED",
             "message": "chair double-booked: another appointment overlaps this chair",
             "field": "chairId" } }
```

Messages come verbatim from `Design/rule-catalogue.md`, so the catalogue stays the single
source. Vietnamese is a later key on the same codes.

### 4. `context/actingUser.ts` — the auth-shaped hole

Auth is parked by decision. Every command still needs an acting user because the schema
carries `created_by`, `set_by`, `decided_by`, `approved_by` throughout — that is the audit
trail. The stub reads `X-Acting-User`, verifies the row exists, and attaches it. **It
refuses to load unless `ALLOW_STUB_AUTH=true`**, so it cannot reach production silently.
When auth lands, only this file changes.

---

## Query layer: Kysely

The user asked for a thin ORM/query layer. **Kysely**, with types generated from the
existing database:

```bash
kysely-codegen --dialect sqlite --url db/kpx.db --out src/db/schema.d.ts
```

The reason over Drizzle: Drizzle wants the schema defined in TypeScript, which would make
a second source of truth competing with `db/modules/*.sql`. Kysely only needs a *type
description*, which is generated **from** the SQL. The `.sql` files stay authoritative,
and a schema change that the code hasn't caught up with becomes a compile error.

Raw SQL stays available (`sql` template tag) for the views and anything awkward.

---

## Reads: a finding that changes the earlier plan

`Design/api-plan.md` claims "the 37 views are already the read model." **That is wrong,
and worth correcting before building on it.** The views were written to be read by a human
in DBeaver: **16 of 37 carry no id column at all.**

`v_day_sheet` — the main receptionist screen — returns patient and doctor *names* with no
`appointment_id`. A client cannot click a row to check someone in.

Not a skeleton blocker, but it settles the approach: **the API does not expose views
directly.** Read endpoints are their own queries in `*.queries.ts`, returning ids
alongside labels. The views remain what they are — an excellent reporting and verification
layer, and the reference for what each query should say.

---

## Proving the skeleton

One vertical slice, end to end, exercising every cross-cutting piece:

| | |
|---|---|
| `GET /health` | db reachable, pragmas confirmed on |
| `GET /appointments?date=` | reads, Zod response, ids present |
| `POST /appointments` | write path, transaction, acting user, **one ported rule** |

The one rule ported is `CHAIR_DOUBLE_BOOKED` — chosen because it is the race the triggers
used to prevent, so it proves the sync-transaction property with a concrete test: two
overlapping bookings, second refused.

Everything else stays unported until the shape is agreed.

---

## Verification

```bash
cd api
npm install
npm run db:types          # regenerate schema.d.ts from db/kpx.db
npm run typecheck
npm run test
npm run dev
```

Then, against a running server:

1. `GET /health` → `{ status: "ok", foreignKeys: true, journalMode: "wal" }`
2. `GET /appointments?date=2026-09-03` → rows **with** `appointmentId`
3. `POST /appointments` with a free chair → 201
4. The same again, overlapping → **409 `CHAIR_DOUBLE_BOOKED`**
5. `POST` with `chairId: "nope"` → 422 from the foreign key, proving translation
6. No `X-Acting-User` → 401 from the stub

Test 4 is the one that matters: it demonstrates the property the whole design rests on.

---

## Risks

| Risk | Handling |
|---|---|
| `better-sqlite3` native build on **Node 25.8** (very new) | If prebuilds are missing, build from source; fallback is Node's built-in `node:sqlite`, also synchronous, same design holds |
| An `await` slipped inside a transaction silently reopens every race | ESLint rule + a comment at the top of `tx.ts`; the single highest-value guardrail here |
| A second writer process breaks the atomicity property | Deploy notes state single-writer; revisit if it ever changes |
| Rules stay unported longer than expected, DB accepts bad data meanwhile | Catalogue is checklist; port order follows module order 1→9 |

---

## Out of scope

Authentication · the other 86 rules · the read endpoints beyond the one slice ·
authorization matrix · Vietnamese messages · deployment
