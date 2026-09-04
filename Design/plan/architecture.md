# KPX Backend Architecture

## Context

The KPX design work so far is documents only — `Design/core-entities/` and `Design/user_requirements/`, no code. Before any feature is built, the layering needs to be settled, because the domain carries rules that must hold regardless of which route triggers them: pro-rata discount allocation before per-line VAT (§18), the no-self-treatment commission bar (§34), `effectiveFrom` resolution for prices and wages (§25, §30), chair/time non-overlap that SQLite cannot enforce (§5), and append-only correction discipline (§14, §37).

The proposed chain was `HTTP → Fastify → Use Case → Domain Logic → Repository → SQLite`. The layers are right; two relationships need correcting before code is written:

1. **Domain is called by the use case, not passed through it.** As drawn, domain logic would depend on the repository — untestable without a database. Domain sits beside the repository.
2. **Nothing owned the transaction.** Completing one session writes to six tables; a use case must open one transaction and pass the handle down, or a crash leaves a completed session nobody was paid for.

Plus one addition: **reads bypass the domain.** Much of the requirement set is reporting (accountant revenue/cost/profit, manager KPI, the odontogram projection, payroll breakdown). Hydrating aggregates to render tables is slow and painful. Commands take the full stack; queries go straight to SQL returning DTOs.

Intended outcome: a running skeleton with one vertical slice proving the shape, so subsequent features are fill-in-the-blank.

## Target architecture

```
HTTP
 └→ Fastify route          transport only: JSON-schema validate, authn, map errors→status
     └→ Use Case           orchestration, authz, TRANSACTION BOUNDARY
         ├→ Repository.load(tx)      I/O — reconstitutes aggregates
         ├→ Domain                   pure: no I/O, no async, no clock, no random
         └→ Repository.save(tx)      I/O — persists
             └→ SQLite (Kysely)

reads:  Fastify route → Query service → SQL → DTO      (skips domain, skips repositories)
```

Dependency rule: `domain/` imports nothing from `repo/`, `routes/`, or Kysely. Enforce with an ESLint `no-restricted-imports` rule under each domain module.

## Decisions taken

| Decision | Choice | Consequence |
|---|---|---|
| Database | SQLite now, Postgres later | Keep SQL portable; no SQLite-only functions in repositories |
| Data access | Kysely | Dialect swap on migration; same builder serves read models |
| Foldering | By domain module | A VAT change touches one folder, not four |
| Money | `INTEGER` đồng | VND has no minor unit; never `REAL` |
| Dates | ISO-8601 UTC `TEXT` | SQLite has no date type |
| Enums | `CHECK` constraints | Portable to Postgres enums or kept as checks |
| Transactions | Use case owns; repos take `tx` | No repository opens its own connection |

## Layout

```
src/
  identity/      User, StaffProfile, PatientProfile
  scheduling/    DoctorSchedule, Appointment, Chair, ChairType
  clinical/      TreatmentPlan, TreatmentProcedure, ProcedureSession, ToothCondition…
  catalog/       ServiceCategory, MaterialOption, PriceList, Promotion
  billing/       Invoice, InvoiceLine, Payment
  payroll/       WageRate, CommissionRule, CommissionEntry, PayrollAdjustment, PayrollRecord
  inventory/     InventoryItem, InventoryBatch, InventoryLog, Vendor
  comms/         Notification
  shared/
    db/          Kysely instance, migrations, pragmas, tx helper
    domain/      Money, DateOnly, Result, DomainError
    http/        error mapping, authn plugin, authz guard
```

Each module: `domain/` · `usecase/` · `repo/` · `query/` · `routes.ts`.

Cross-module rule: modules talk through use cases, never by importing another module's repository. Where a write spans modules (session completion touches clinical + billing + payroll + inventory), one orchestrating use case in `clinical/` calls the others' use cases inside its own transaction.

## Where each invariant lives

| Rule | Layer | Note |
|---|---|---|
| Discount pro-rata → VAT on net, remainder to last line (§18) | Domain, pure | The 20,000đ bug the design already caught |
| No commission when staff == patient `User` (§34) | Domain | Needs both ids loaded before the call |
| `effectiveFrom` price/wage resolution (§25, §30) | Repository query + domain | Repo fetches candidate rows; domain picks |
| Chair × time non-overlap (§5) | Use case, in transaction | SQLite's single writer makes this safe today; becomes a Postgres exclusion constraint on migration |
| Invoice number assigned at issue, never reused (§19) | Use case, in transaction | Sequence table, not `AUTOINCREMENT` |
| Append-only: `InvoiceLine`, `ProcedureDecision`, settled `PayrollAdjustment` | Schema | `BEFORE UPDATE … RAISE(ABORT)` triggers as defence in depth |
| Manager-only commission visibility (§36) | Route/use-case authz | Design doc already states: permission layer, not data model |

## Steps

1. **Scaffold** — TypeScript, Fastify, Kysely + `better-sqlite3`, Vitest. `shared/db` sets `PRAGMA foreign_keys = ON`, `journal_mode = WAL`, `busy_timeout`, on every connection.
2. **Transaction helper** — `withTx(fn)` in `shared/db`; repository methods take `tx` as the first parameter. No repository may reach the global db handle.
3. **Migrations** — Kysely migrations, one per domain module, in dependency order (identity → catalog → scheduling → clinical → billing → payroll → inventory). Static `Tooth` seed of all 52 FDI rows.
4. **Shared domain primitives** — `Money` (integer đồng), `Result`/`DomainError` so the domain returns failures instead of throwing, error→HTTP mapping in `shared/http`.
5. **Vertical slice: complete a session** — the hardest path, chosen deliberately to prove the shape. One use case opens a transaction and: marks `ProcedureSession` Completed → writes an `InvoiceLine` from `billableAmount` → recomputes `Invoice` totals via the pure allocation function → writes doctor and assistant `CommissionEntry` rows (applying §34) → decrements `InventoryBatch` FEFO → applies `resultingConditionType` if it is the final session.
6. **Read-model slice: the odontogram** — `clinical/query/chart.ts`, one SQL projection joining all 52 `Tooth` rows to that patient's `ToothCondition` and to `ProcedureTooth` filtered by status, returning a DTO. Proves reads need neither repository nor domain.
7. **Boundary lint** — `no-restricted-imports` forbidding `domain/` from importing `repo/`, Kysely, or `node:*`.

## Verification

- **Unit** — the discount/VAT allocator reproduces the §18 table exactly (3,000,000 gross → 180,000 VAT, not 200,000), including remainder placement on the last line. No DB, no mocks.
- **Unit** — §34: a `CommissionEntry` is refused when credited staff and patient resolve to one `User`.
- **Integration** — session completion against a temp-file SQLite db: assert all six writes land; then force a failure after the invoice line and assert the transaction rolled back with no orphan `CommissionEntry`.
- **Integration** — two concurrent bookings for one chair at overlapping times: exactly one succeeds.
- **Integration** — `UPDATE` on an `InvoiceLine` is rejected by the trigger.
- **Smoke** — `fastify.inject()` on the slice's route and on the odontogram route; assert status codes and DTO shape.
- **Portability check** — `grep` repositories for SQLite-only SQL before the Postgres migration is ever attempted.
