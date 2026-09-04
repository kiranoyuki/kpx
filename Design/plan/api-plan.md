# KPX — API Plan

> **Decision: all business logic lives in the API.** The 56 triggers are removed; the
> 319 declarative constraints stay. Auth is **parked** until the rest of the backend is
> complete. Backend first, front end after.

> **Two sections below are superseded — the rest stands.**
>
> - **§1, the in-process mutex.** Not needed. `better-sqlite3` is synchronous and Node is
>   single-threaded, so a sync transaction is already atomic against other requests in the
>   process. The rule that replaces the mutex is *never `await` inside a transaction*.
>   See `backend-skeleton.md`.
> - **§3, "the 37 views are already the read model."** Wrong: **16 of the 37 carry no id
>   column.** `v_day_sheet` returns patient and doctor names with no `appointment_id`, so a
>   client cannot click a row. Read endpoints are their own queries in `*.queries.ts`; the
>   views remain a reporting and verification layer.
>
> The command inventory in §3 and the derived-column analysis in §1 remain the spec.
> Current working docs: `checklist.md`, `conventions.md`, `open-questions.md`.

---

## 1. Where the rules execute — decided

### The decision

Business logic belongs in the API, for three reasons that hold up:

1. **Traceability.** A developer reading `INSERT INTO appointment` in application code
   has no indication that five triggers are about to fire, and a stack trace stops at
   the SQLite boundary. That cost compounds with every person who joins the project.
2. **Change cost.** Rules change — commission rates, eligibility, thresholds. A rule in
   TypeScript changes with a deploy; a rule in a trigger changes with a migration.
3. **One place to look.** A split between database and API means checking both for
   every rule, which is the traceability cost without the benefit of consistency.

Volume supports it: four chairs, roughly forty appointments a day, three receptionists.
This is not a system where concurrency pressure forces the rules downward.

### What stays in the database

Enforcement in this schema was never mostly triggers:

| | count | status |
|---|---|---|
| CHECK constraints | 176 | **stay** |
| FOREIGN KEY references | 108 | **stay** |
| UNIQUE constraints & indexes | 35 | **stay** |
| triggers | 56 | **removed** |

The 319 declarative constraints are visible in the table definition itself. A developer
reading the schema sees them; they need no separate lookup and carry none of the
traceability cost above. They are the schema's type system, not its business logic.
`PRAGMA foreign_keys = ON` must still be issued on every connection or a third of that
disappears silently.

### What this costs, accepted deliberately

**1. Concurrency moves to the API.** Check-then-act races (chair and doctor
double-booking, FEFO, stock levels, overlapping shifts and pay periods) are no longer
atomic. The mitigation is an **in-process lock** — a mutex keyed on the contended
resource, held across check-and-write. Caching is *not* a mitigation: a cache is a
staler read and widens the window.

The lock is sound while both of these hold, and they must be treated as conditions
rather than assumptions:

- exactly **one API process** writes to the database
- **nothing else writes** — no hand fixes in a SQL client against the live file, no
  scripts run directly

A second writer (blue/green deploy overlap, a cron worker, horizontal scaling) breaks
the lock without breaking any test. If that day comes, the options are `BEGIN IMMEDIATE`
around the affected commands, or reinstating those specific triggers.

**2. Six derived columns lose their maintainer.**

| Column | Was maintained from |
|---|---|
| `treatment_procedure.status` | decision log head |
| `invoice.subtotal` / `vat_total` / `total` | its lines |
| `invoice.status` | payments received |
| `inventory_item.quantity_on_hand` | batch remainders |
| `inventory_batch.quantity_remaining` | its logs |
| `procedure_session.billable_amount` | the invoice line |

Where possible the better answer is **not** to have the API maintain them but to **drop
the stored column and derive it in a view** — no duplicated state, nothing to drift.
That suits procedure status and stock levels.

**Invoice totals are the exception and stay stored.** A Vietnamese legal invoice must
record what was printed and issued, not recompute later from lines that could be read
differently. The API writes them once at issue, and they freeze.

**3. The audit trail loses its floor.** The ten immutability rules become "the API
exposes no update path", which is readable and sufficient against application bugs. The
residual risk is explicit: anyone with file access can rewrite a decision log and
nothing would detect it. Given the legal-audit requirement, the mitigation is
restricting who can open the database file.

**4. The ~149 negative tests must transfer, not lapse.** They stop being schema tests
and become the API's integration suite — the safety net that replaces the triggers.
This is the part that keeps the change from being a downgrade, and it is not optional.

---

## 2. Removal order

Nothing is dropped before its replacement exists and is tested.

1. **Port each rule into the API's command layer**, module by module, in build order
   1 → 9, carrying its exact message.
2. **Retarget its negative tests** from SQL to HTTP as each rule lands. A rule is not
   ported until its tests pass against the API.
3. **Then drop the trigger** from the schema file. Delete, never comment out: commented
   SQL is not compiled, not tested, and unreadable as intent within two months. Git
   holds every version — `git show a1fe9bc:db/modules/0801_payroll_schema.sql`.
4. **Convert the derived columns to views** where they should not be stored at all.

Before any of this, extract the **rule catalogue**: rule id, module, the invariant in one
sentence, the exact user-facing message, and the negative test that proves it. That
document is the API's specification and its test plan, and it is what makes deleting the
triggers safe rather than lossy.

### The one rule to port with care

`trg_ce_cites_the_applicable_rule` resolves commission rates most-specific-first:
contract rate → service category rate → role catch-all. The precedence must not end up
implemented twice. Add first:

```sql
CREATE VIEW v_commission_due AS   -- completed sessions with no entry yet, joined to
                                  -- the rule that resolves for that staff member and
                                  -- that work: staff, rule, base, amount
```

`completeSession` then inserts straight from the view. The resolution order lives in one
place, and it is a view — a read, not a rule — which sits comfortably on the API side of
the line.

---

## 3. API shape

### Reads: the 37 views are already the read model

`v_day_sheet`, `v_tooth_chart`, `v_invoice_balance`, `v_payslip`, `v_pick_order`,
`v_inbox`, `v_pending_chases` and the rest were each written to answer a question
someone actually asks. Most GET endpoints are `SELECT * FROM v_x WHERE …` with
pagination, driven by one route → view → filters → visibility table rather than a file
per endpoint.

### Writes: ~30 commands, not 43 resources

The schema makes several REST-shaped operations impossible on purpose, and the API must
expose the real sequences:

- **Invoice:** open Draft → add lines → apply voucher → issue. Lines freeze on issue.
- **Payroll:** open Draft → gather the period's rows → approve → pay. Totals are
  recomputed from the linked rows at approval.
- **Procedure status** is the head of an append-only decision log, never a field to set.

| Module | Commands |
|---|---|
| People | `registerWalkIn` · `bookProvisional` · `verifyOnArrival` · `changeEmployment` |
| Scheduling | `book` · `confirm` · `checkIn` · `markNoShow` · `cancel` |
| Planning | `createPlan` · `proposeProcedure` · `recordDecision` · `quoteProposal` (computes, stores nothing) |
| Clinical | `recordFindings` · `startSession` · `completeSession` |
| Billing | `openInvoice` · `addLine` · `applyVoucher` · `issue` · `recordPayment` · `reportFailure` · `determineFault` |
| Inventory | `receiveStock` · `consume` · `logMaintenance` |
| Payroll | `clockIn` · `clockOut` · `raiseAdjustment` · `openRun` · `settle` · `approve` · `pay` |
| Notify | `send` · `markRead` |

Every command runs in one transaction, and every command threads the **acting user**
through — the schema carries `created_by`, `set_by`, `decided_by`, `approved_by`
throughout, and those are the audit trail.

### Cross-cutting

- **Error contract.** Each rule has an id and a user-facing message. Field-level where
  the UI can point at a field; message-level otherwise. Messages will need Vietnamese.
- **Authorization.** `v_portal_access` already answers who may enter which portal. The
  commission dashboard is manager-only, and patients reach only their own records —
  which is now an API responsibility, since `trg_notif_patient_sees_own` and the
  cross-patient checks are going.
- **SQLite operations.** WAL mode, `busy_timeout`, `foreign_keys = ON` per connection.

---

## 4. Build order

**0.** Skeleton, error contract, rule catalogue extracted
**1.** Read API from the 37 views
**2.** Commands module by module, 1 → 9, each with its ported rules and retargeted tests
**3.** Authorization matrix
**4.** An audit pass in the established pattern — asking what a *wrong* request still
gets through, not whether a correct one works

**Parked by decision:** authentication (staff credentials, patient OTP, sessions) until
the rest of the backend is complete.
