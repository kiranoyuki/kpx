# KPX — Build Plan

How to turn `core-entities/entities.md` into a working schema, one module at a time.

**40 entities, 9 modules.** Module order is derived from the actual foreign keys in the
design, not from workflow intuition — the two disagree in one place, and following
workflow order there would force a rebuild.

---

## Two structural facts to know first

### There is exactly one circular dependency

```
TreatmentProcedure.remedyForFailureId ──► TreatmentFailure
TreatmentFailure.procedureId          ──► TreatmentProcedure
```

A failure is *of* a procedure; a free-rework procedure is *because of* a failure. Both
directions are real, so the cycle cannot be designed away.

**It does not block the build, but not the way first assumed.** `CREATE TABLE` with a
forward reference succeeds — but with `PRAGMA foreign_keys = ON`, the very first `INSERT`
then fails, **even inserting NULL**:

```sql
CREATE TABLE tp (id TEXT PRIMARY KEY, fk TEXT REFERENCES tf(id));  -- succeeds
INSERT INTO tp VALUES ('p1', NULL);        -- Error: no such table: main.tf
```

Turning foreign keys off to get past it would defeat the point. The working answer is
`ALTER TABLE ADD COLUMN`, which SQLite *does* allow to carry a `REFERENCES` clause:

**Module 4 creates `treatment_procedure` without `remedy_for_failure_id` at all.**
**Module 6 adds the column once `treatment_failure` exists:**

```sql
ALTER TABLE treatment_procedure
    ADD COLUMN remedy_for_failure_id TEXT REFERENCES treatment_failure(id);
```

Verified end to end: the column is added, a valid value is accepted, an invalid one is
rejected by the constraint, and `foreign_key_check` stays clean. No pragma is ever
disabled.

### Treatment must be built before Booking

`Appointment` and `ProcedureSession` point *at* treatment, never the reverse. Workflow runs
book-then-treat; the schema runs treat-then-book. **SQLite cannot add a foreign key to an
existing table** — getting this backwards means rebuilding the table, so the dependency
order wins.

---

## The modules

| # | Module | Entities | Depends on |
|---|--------|----------|------------|
| 1 | People & Access | 3 | — |
| 2 | Clinic Setup | 7 | 1 |
| 3 | Scheduling | 2 | 1, 2 |
| 4 | Treatment Planning | 6 | 1, 2 |
| 5 | Clinical Record | 5 | 1, 2, 3, 4 |
| 6 | Billing | 4 | 1, 2, 4, 5 |
| 7 | Inventory | 5 | 1, 4 |
| 8 | Payroll & Commission | 7 | 1, 2, 3, 5, 6 |
| 9 | Notifications | 1 | 1 |

Modules 7 and 9 are off the critical path and can be built in parallel or deferred.

---

### Module 1 — People & Access

`User` · `StaffProfile` · `PatientProfile`

Small, but the trickiest rules in the system live here. Worth proving in isolation before
anything references it.

**Demonstrates**
- The identity lifecycle: an online booker created `Provisional`, converted to `Active` on arrival
- A verified walk-in who is `Active` with a CCCD and **cannot log in** — no email, no credentials
- One person holding both a `StaffProfile` and a `PatientProfile`
- A departed staff member who remains an active patient

**Verify**
- `status = Active` is rejected without `verifiedAt` and `verifiedBy`
- `nationalId` rejects 11 and 13 digits, non-numeric input, and duplicates
- Ending employment on `StaffProfile` leaves `User.status` untouched

---

### Module 2 — Clinic Setup

`Tooth` · `ChairType` · `Chair` · `ServiceCategory` · `MaterialOption` · `PriceList` · `Promotion`

Reference and configuration data. Mostly seeded once and rarely written thereafter.

**Demonstrates**
- All 52 FDI codes, 32 permanent and 20 primary
- The same crown priced differently in zirconia and PFM
- A price resolved as of today versus as of last year
- A voucher code that is valid, expired, and over its redemption limit

**Verify**
- `PriceList` resolution falls back to the category base row when a material has no price of its own
- A `Percentage` promotion above 100 is rejected
- `Tooth.validSurfaces` is `MIDBL` for anterior teeth and `MODBL` for posterior

---

### Module 3 — Scheduling

`DoctorSchedule` · `Appointment`

**Demonstrates**
- A booking made against doctor availability and a free chair
- A no-show that stays `Provisional` and appears in the reschedule chase
- An online self-booking with `createdBy` null

**Verify**
- **Two appointments cannot overlap in the same chair** — the reason `Chair` exists
- A procedure requiring the surgical chair type cannot be booked into a standard chair
- `Appointment.personId` accepts a `Provisional` person

---

### Module 4 — Treatment Planning

`TreatmentPlan` · `ProcedureInstruction` · `TreatmentProcedure` · `ProcedureDecision`
`DiscountProposal` · `SpecialProcedureProposal`

**Declares the forward FK to `TreatmentFailure`** (module 6). Leave it NULL until then.

**Demonstrates**
- A plan proposed, three procedures accepted and two declined with reasons
- A declined procedure re-proposed months later — both decisions surviving in the log
- A special procedure held at `PendingApproval` until the manager acts
- The **proposal invoice**: computed from current prices, never stored

**Verify**
- `Declined` and `Skipped` are rejected without a `reason`
- `TreatmentProcedure.status` always equals the `toStatus` of its latest `ProcedureDecision`
- `unitPrice` is NULL until the procedure is first invoiced

---

### Module 5 — Clinical Record

`HealthRecord` · `ToothCondition` · `ProcedureTooth` · `PatientMedia` · `ProcedureSession`

The odontogram and the record of work actually done.

**Demonstrates**
- A full-mouth chart from a first exam, grouped by `observedDuringProcedureId`
- Deep caries on 46 addressed by **two** procedures — root canal then crown
- One scaling resolving calculus findings across twenty teeth
- A three-session root canal worked by different assistants each visit

**Verify**
- A surface not in that tooth's `validSurfaces` is rejected — no occlusal on an incisor
- Whole-tooth conditions carry NULL surfaces
- Sessions sum their `billableAmount` to the procedure total
- A session cannot complete on a procedure that is not `Accepted`

---

### Module 6 — Billing

`Invoice` · `InvoiceLine` · `Payment` · `TreatmentFailure`

Closes the cycle opened in module 4.

**Demonstrates**
- Per-session billing across a multi-visit procedure
- Upfront payment, then a mid-plan cancellation refunded by credit line
- A failed veneer: fault judged, refund issued, free rework booked, staff debited
- A mixed-rate invoice with a voucher — **discount allocated before VAT**

**Verify**
- Line `discountAmount` values sum exactly to `Invoice.discountAmount`
- `vatAmount` computes on `lineTotal − discountAmount`, never on `lineTotal`
- A `Declined` procedure never produces a line
- No session is billed twice
- A `Voided` invoice keeps its number, and the number is never reissued

---

### Module 7 — Inventory

`Vendor` · `InventoryItem` · `InventoryBatch` · `InventoryLog` · `ProcedureSupplyList`

Off the critical path — buildable in parallel with 5 and 6.

**Demonstrates**
- Two batches of one composite with different expiry dates and different unit costs
- Earliest-expiry-first consumption
- Expected supplies from an instruction template versus what a procedure actually consumed
- A low-stock alert carrying the vendor's contact

**Verify**
- `quantityRemaining` never exceeds `quantityReceived` nor falls below zero
- For an item with `tracksExpiry`, `quantityOnHand` equals the sum of its batches
- A write-off past expiry produces an `Expired` log entry naming the lot

---

### Module 8 — Payroll & Commission

`WageRate` · `AttendanceLog` · `PayrollRecord` · `CommissionRule`
`ReceptionistPerformanceLog` · `CommissionEntry` · `PayrollAdjustment`

Built last: it reads from nearly every other module.

**Demonstrates**
- An intern promoted mid-month, with each day billed at the rate in force that day
- A doctor's contract implant rate beating the role rate, which beats the catch-all
- Commission on a session earned by the assistant who was actually there
- A payroll debit charged back for a failed treatment

**Verify**
- Commission equals `commissionBase × rate` for every entry
- **No staff member earns commission on their own treatment**
- Free rework earns zero commission, by arithmetic rather than by rule
- Rate resolution for a given day picks the greatest `effectiveFrom` on or before it
- Settled adjustments are immutable

---

### Module 9 — Notifications

`Notification`

Records what should be sent and to whom. **Delivery is out of scope** — a separate system
(internal chat, SMS, or Zalo) will bring its own channel, status and retry.

---

## How to verify each module

The pattern that worked on the first build, and that caught two real defects:

1. **Schema** — the module's DDL, with `CHECK` constraints for every documented invariant.
2. **Seed** — enough rows to exercise the edges, not just the happy path. The interesting
   rows are the walk-in with no email, the superseded price, the declined procedure.
3. **Three checks:**
   - `PRAGMA foreign_key_check` — expect zero rows
   - **Arithmetic** wherever money is involved — recompute totals from their parts and compare
   - **Negative tests** — prove each constraint actually *rejects* bad data

The third is the one that pays. It caught a `TreatmentPlan`/`Appointment` mix-up and a
cascade that silently destroyed commission history.

---

## Known gaps, deferred by decision

| Gap | Decision |
|-----|----------|
| Notification delivery | separate system, designed later |
| Plan-level discount split across staged invoices | parked; no entity impact |
| Clinic opening hours | not modelled — booking checks doctor and chair only |
| Patient sign-in fields, staff auth mechanism | open; needs no new columns on `User` |
| Monthly wage pro-rating mid-period | open; computation only |
| Periodontal charting | out of scope; slots in as a new entity |
| Two findings on one tooth, one procedure | the single shape `addressesConditionId` cannot express |

Settled and not to be revisited without cause: **surfaces stay a canonical string**
(`MOD`), and **one voucher per invoice**.
