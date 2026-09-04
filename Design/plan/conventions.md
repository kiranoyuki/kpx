# KPX — Standing Conventions

Rules that apply to every step. Referred to by `checklist.md`; not repeated there.

---

## 1. PR scope

**One reviewable concern = one PR.** A checklist step may take 1–3 PRs; the size rule wins
over keeping a step in one piece.

| | |
|---|---|
| Size | 100–300 meaningful changed lines, excluding generated `schema.d.ts` and lockfiles |
| Content | One concern. One reason to review it |
| Test | "What became possible or safer after this merge?" must have a one-sentence answer |
| Reviewable in | Under 15 minutes |

Sub-PRs are lettered against their step: `05a`, `05b`, `05c`.

Before merge: `/code-review`. On any step touching money or auth: `/security-review` too.

## 2. Structure — the use case is the unit

Files are named after the use case, not the module. A module never accumulates a
`scheduling.commands.ts` that grows to forty functions.

```
src/api/
  shared/
    money.ts  clock.ts  ids.ts  errors/
  modules/
    scheduling/
      book-appointment.ts          use case: plain input → plain output
      book-appointment.http.ts     zod schemas + mapping to BookAppointmentInput
      book-appointment.test.ts
      reschedule-appointment.ts
      reschedule-appointment.http.ts
      reschedule-appointment.test.ts
      get-day-sheet.ts             query
      scheduling.repository.ts     shared SQL for the module
      scheduling.routes.ts         registers each .http.ts against a path
      domain/
        booking-window.ts          pure rules, if the module has any
```

Flat files, not a folder per use case — one folder per use case costs more than it returns
at this size. Revisit if a module passes ~15 use cases.

**Zod lives in `.http.ts`, never in the use-case file.** A use case that imports Zod knows
about an HTTP validation library, which is exactly the coupling the boundary exists to
prevent. `book-appointment.ts` must be callable from a test, a script or a future queue
consumer without Zod coming along:

```ts
bookAppointment({ input: { patientId, doctorId, chairId, startsAt }, repo, clock, ids })
```

A Zod schema may *derive or check* the input type. It is never itself the application type.

### Layers

```
HTTP
 └→ *.routes.ts       transport: auth, map errors → status
     └→ *.http.ts     zod parse → plain input
         └→ <use-case>.ts orchestration + THE TRANSACTION
             ├→ domain/   pure rules and calculation
             ├→ shared/   money, clock, ids
             └→ repository → Kysely → SQLite
```

**Simple projections** — a list, a detail view, a report — go straight from a query file to
SQL and return a DTO, skipping commands and domain entirely.

**Reads that make a business decision do not.** Visibility ("may this staff member see this
payroll?"), regulated or financial state ("what is the outstanding balance?", "which price
is effective today?") and anything a user could act on go through the same domain code a
command would use. A `GET` is not a licence to move business logic into SQL.

### The dependency boundary

`shared/` and every `modules/*/domain/` directory may import **nothing** — not Kysely, not
Fastify, not `better-sqlite3`, not `node:*`, not another module. `domain/` may import
`shared/`. Enforced by ESLint `no-restricted-imports`, not by discipline.

That boundary is what makes these files testable with no database, no mocks and no async.

### Dependencies are passed in, never reached for

A use case receives what it needs as a plain object. It must never know those dependencies
came from Fastify.

```ts
// ✓ the use case signature
registerPatient({ input, repo, clock, ids })

// ✗ never
function registerPatient(request: FastifyRequest) { request.clock.now() }
```

```
Fastify request  →  dependency container  →  plain deps object  →  use case
```

Fastify *resolves* `clock`, `ids` and repositories; the routes file unpacks them and calls
the use case. No file under `modules/` may import a Fastify type.

### Zod stops at the boundary

Zod validates untrusted input and then hands over a plain typed value. It is not the domain
model.

```
HTTP JSON  →  zod parse  →  RegisterPatientInput  →  use case  →  domain
```

A use case takes `RegisterPatientInput`, not `z.infer<typeof schema>` threaded through every
layer. Business logic operates on values that are already valid — re-validating downstream
means the boundary did not do its job.

## 3. Transactions

`better-sqlite3` is synchronous and Node is single-threaded, so a sync transaction is
atomic against other requests **in this process**. That property is what replaced the 56
removed triggers — no mutex is needed.

### The deployment invariant this rests on

```
Exactly one application process may write to db/kpx.db.

Every check-then-write invariant in this system — chair and doctor overlap,
FEFO, stock levels, overlapping shifts and pay periods — depends on it.
```

This is an **architectural constraint, not a distributed-concurrency solution.** Two
processes would interleave check and write and the guarantee is gone, without a single test
failing:

```
Process A              Process B
check → free
                       check → free
insert
                       insert          ← both succeed
```

It also means nothing else may write to the file: no hand fixes in a SQL client against the
live database, no scripts run directly against it.

If a second writer ever becomes necessary — horizontal scaling, a cron worker, a blue/green
deploy overlap — the transaction strategy must be revisited first. The options are
`BEGIN IMMEDIATE` around the affected commands, or reinstating those specific triggers.
State it in the deploy notes, not only here.

All writes go through `write()` in `db/tx.ts`. Nothing else opens a transaction.

**A transaction may contain only these:**

```
write()
 ├── read from the database
 ├── evaluate business rules (domain/, shared/)
 ├── write to the database
 └── commit
```

**Never, inside a transaction:**

```
✗ await — of any kind
✗ an HTTP call or external API
✗ sending email or SMS
✗ reading or writing a file
✗ a timer, a queue publish, a cache call
```

One `await` splits the sync block and reopens every check-then-act race. ESLint enforces
this; it is the highest-value guardrail in the repo.

**Consequence — the outbox.** Anything that must reach the outside world is *recorded*
inside the transaction and *dispatched* separately. A command that causes a notification
writes the row in its own transaction; it never sends anything itself.

```
command                          dispatcher (separate, resumable)
  └→ write()                       └→ find Pending rows
      ├── the business change          └→ send
      └── the outbox row               └→ mark Sent
      commit
```

Dispatching **after commit in the same request is not sufficient** — the process can crash
between the commit and the send, and the message is lost with no trace that it was owed.
The contract is therefore:

- A pending message **survives a restart**. It lives in the table, not in memory.
- The dispatcher **retries** until it succeeds or is marked failed.
- Delivery is at-least-once, so **dispatch must tolerate being attempted twice.**

Phase I implements the dispatcher. Fixing the contract now means it can be added without
changing any command.

Single writer process. Stated in the deploy notes, not just here.

## 4. Determinism — no ambient state in business logic

Business logic never reaches for the current time or a new id itself. Both are injected.

```ts
interface Clock { now(): Date }          // SystemClock | FixedClock('2026-09-04T10:00:00Z')
interface Ids   { next(): string }       // UuidIds     | SeqIds('app-1', 'app-2', …)
```

Without this, a rule like "cancellation is inside the 24-hour window" can only be tested by
computing the expected answer the same way the code does — which tests nothing. With it:

```
Given now          = 2026-09-04 10:00
And appointment at = 2026-09-05 09:00
Then cancellation is inside the 24-hour window
```

The same applies to ids: a test asserting a created row cannot name it if the id is random.

### Time semantics — three distinct types

The clinic's business timezone is **`Asia/Ho_Chi_Minh`**. It is a constant in `shared/`, not
the server's local zone, which must never be read.

| Type | Example | Stored as | Converted? |
|---|---|---|---|
| **Instant** — an exact moment | `2026-09-04T03:00:00Z` | ISO-8601 UTC text | yes, to display |
| **LocalDate** — a calendar day | `2026-09-04` | `YYYY-MM-DD` text | **never** |
| **LocalTime** — a time of day | `08:30` | `HH:MM` text | **never** |

These are not interchangeable, and conflating them is the most likely time bug in this
system. `new Date('2026-09-04')` parses as UTC midnight, which is **07:00 on the 4th** in
Ho Chi Minh City — so a pay period, an expiry date or a day sheet computed that way silently
shifts by a day for part of every day.

Rules of thumb:

- An appointment *starts at* an Instant. A pay period *runs between* LocalDates. Clinic
  opening hours are LocalTimes. Inventory *expires on* a LocalDate.
- "Today", "this week", weekday, and "which pay period is this in" are answered in the
  clinic timezone, from `clock.now()` — never from the server's zone.
- A LocalDate is never round-tripped through a `Date`.

Formatting for display is the UI's job, never the domain's.

## 5. Money

- Integer **đồng**. VND has no minor unit — never `_cents`, never a float.
- Stored columns suffixed `_vnd`.
- Every formula lives in `shared/money.ts` or a module's `domain/`, never inline in a use case.
- Discounts allocate pro-rata across lines **before** VAT, rounded down to whole đồng with
  the remainder on the last line (§18).

### Rates are integers too

An integer amount multiplied by a floating-point rate is still floating-point arithmetic.
Percentages are **basis points** — integers, where 1 bp = 0.01%:

```ts
applyBasisPoints(1_000_000, 1500)   // ✓ 15.00%
applyRate(1_000_000, 0.15)          // ✗ never — 0.15 is not representable
```

| Rate | Basis points |
|---|---|
| 15% | 1500 |
| 7.5% | 750 |
| 0.25% | 25 |

VAT rates, commission rates and discount percentages are all stored and passed as basis
points. Where a rate is genuinely a ratio rather than a percentage, pass it as an explicit
`{ numerator, denominator }` pair — never a decimal.

**Every rounding point is a named policy**, not an inline `Math.round`. Rounding down with
the remainder on the last line is one such policy; a test names it and pins its behaviour.

## 6. Financial history is append-only

**A posted financial record is never edited or deleted to correct history. Corrections are
new, opposing records.**

```
Wrong                          Preferred
Payment      ₫1,000,000        Payment       +₫1,000,000
UPDATE amount = ₫800,000       Adjustment      −₫200,000
                                             ────────────
                               Net             ₫800,000
```

This is already the design's intent — negative `invoice_line` rows carrying `credits_line_id`,
`payment.direction = Out`, `payroll_adjustment` — and rules 11, 12, 15, 30, 43, 49, 57, 70,
73 exist to enforce it. Stating it once means no future schema or endpoint quietly breaks it.

**Consequences to hold on to:** append-only tables are protected by the API exposing **no
update or delete route**, not by triggers. A balance is a sum over rows, never a mutated
field. The golden-ledger test asserts the sum, not any single row.

## 7. Idempotency for money-changing commands

Required before the API accepts real payments. Not needed for `register-patient`.

The sync-transaction property does **not** solve this. A double-clicked "Record payment" is
not a race — the second request runs cleanly after the first and creates a second, perfectly
valid payment. Transactions cannot help; only a stable client-supplied key can.

```
POST /payments   Idempotency-Key: <client-generated uuid>
```

The key is stored with the command's result under a unique constraint. A repeat returns the
first result rather than performing the work again. Applies to `recordPayment`, `refund`,
`issue`, `approve`, `pay`, `settle`.

## 8. Error codes are the contract; messages are presentation

```ts
expect(err.code).toBe('CHAIR_DOUBLE_BOOKED')      // ← what rule tests assert
```

Codes are stable and machine-readable. Messages are display text and **will** change —
Vietnamese is planned. If forty rule tests assert wording, translation breaks forty tests
for no reason.

### One machine-readable source of truth

`shared/errors/catalogue.ts` is authoritative for anything a test or the runtime reads:

```ts
export const CATALOGUE = {
  CHAIR_DOUBLE_BOOKED: {
    rule: 2,
    en: 'chair double-booked: another appointment overlaps this chair',
    vi: null,
  },
} as const
```

`Design/rule-catalogue.md` stays the **design document** — its 87 rows and the "needs to
look at" column are the specification and the reason each rule exists. It is **not**
machine-synced, and no test parses it. Tests that scrape prose Markdown are worse than no
test: they fail on formatting and pass on a wrong message.

So:

- **Rule and API tests assert `code` only.**
- **One test per module** asserts that every code the module can emit exists in
  `CATALOGUE` with non-empty `en` and a `rule` number in the module's range. That test is
  the coverage gate — it counts entries, not prose.
- Wording changes touch `catalogue.ts` and that test alone. Vietnamese is filling in `vi`.
- Keeping `rule-catalogue.md` readable when wording changes is a manual step, and it is
  fine for it to lag; it describes intent, not runtime strings.

Response shape, fixed:

```json
{ "error": { "code": "CHAIR_DOUBLE_BOOKED", "message": "…", "field": "chairId" } }
```

## 9. State changes are verbs, not field edits

Each gets its own use-case file, and its own `domain/` rule file where it has rules. None is
a `PATCH` on a column:

`check-in` · `no-show` · `reschedule` · `cancel` · `accept` · `decline` · `complete` ·
`issue` · `void` · `refund` · `approve` · `settle`

## 10. Two documents describe every workflow

| Document | Answers | Form |
|---|---|---|
| `Design/rule-catalogue.md` | what gets refused, in what words | 87 numbered rules + messages |
| `Design/workflows/<name>.md` | what the arithmetic produces | R-rules + worked E-examples |

```markdown
# Payment Workflow            Status: Draft | Stable

R1  Payment cannot exceed the outstanding balance.   → PAYMENT_EXCEEDS_BALANCE
R2  Payment amount must be positive.                 → PAYMENT_NOT_POSITIVE

E1  balance 500,000 + pay 200,000  → balance 300,000
E2  balance 500,000 + pay 600,000  → rejected (R1)
```

A workflow stays `Draft` until walked through by hand against real use. Only `Stable`
workflows are treated as settled.

**When a requirement changes, in this order:**

```
update the requirement → update the expected examples → watch the tests fail → change code
```

That ordering is the point. It stops docs rotting behind the code.

## 11. Testing

| Level | How many | Runs against | Covers |
|---|---|---|---|
| Domain / shared unit tests | Many | Nothing — pure functions | Every arithmetic and rule edge case |
| Use-case / API tests | Moderate | A fresh seeded SQLite file | Rules, transactions, rollback, response shape |
| Playwright E2E | Few | The browser | One happy path per workflow |

Do not duplicate business edge cases through the browser.

Tests name the rule, never the implementation, and call only the exported use case or
domain function — no mocks, no internals:

```ts
it('61 — no commission on your own treatment', …)
it('E1 — a partial payment reduces the balance by exactly the amount paid', …)
```

**A behaviour-preserving refactor should not require changing a behaviour test.** Fixtures,
helpers, dependency construction and file organisation may legitimately move with a
refactor; the assertions about what the system *does* should not. If they must, either the
behaviour changed or the test was reaching into internals.

### Rollback tests, where they earn their place

Required for **any command that writes more than once, or that carries an atomicity
invariant**:

| Command | Why |
|---|---|
| `register-patient` | `app_user` + `patient_profile` — an orphan user is a real bug |
| `record-payment` | payment + allocation + invoice status + outbox |
| `complete-session` | session + invoice line + commission entries + stock |
| `settle-payroll` | record + adjustments + the lock |
| `consume-stock` | movement + batch remainder + procedure link |

Not required for a single-statement command. Forcing a throw after one `UPDATE` proves that
SQLite has transactions, not that the code is correct.

## 12. Definition of done for a step

- [ ] Workflow doc written first, with worked examples, if the step has business rules
- [ ] Every catalogue rule in range has a test asserting its **code**
- [ ] The module's code→message test covers any new codes
- [ ] Rollback test present if the command writes more than once (§11)
- [ ] Lint clean: no-`await`-in-transaction, and the `shared/` + `domain/` boundaries
- [ ] `/code-review` run, findings resolved
- [ ] Checklist box ticked, with the PR link

## 13. Deliberate shortcuts

Marked `// TODO(step-N):` naming the step that repays them. Currently open:

| Shortcut | Repaid by |
|---|---|
| Stub auth via `X-Acting-User` header | The auth step, not yet scheduled |
| No idempotency keys | Before Phase F accepts real payments |
| No clinic-hours entity — only per-doctor availability | Phase B1 |

## 14. Requirement changes

Recorded in `Design/plan/decisions.md`: what changed, why, and which workflow doc and tests
moved with it.
