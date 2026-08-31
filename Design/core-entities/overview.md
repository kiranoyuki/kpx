# KPX — Core Entity Overview

## Entity Domains

The system is organized into 7 domains, each grouping entities by concern.

| Domain | Entities |
|--------|----------|
| Identity & Access | User, StaffProfile, PatientProfile |
| Scheduling | DoctorSchedule, Appointment |
| Clinical | HealthRecord, TreatmentPlan, TreatmentProcedure, ProcedureInstruction, TreatmentProgress, PatientMedia |
| Catalog & Pricing | ServiceCategory, PriceList, Promotion, DiscountProposal, SpecialProcedureProposal |
| Billing | Invoice, Payment |
| Inventory | InventoryItem, InventoryLog, Vendor, ProcedureSupplyList |
| Communication & HR | Notification, AttendanceLog, CommissionRule, CommissionEntry, ReceptionistPerformanceLog (standalone bridge), PayrollAdjustment, PayrollRecord |

---

## High-Level Entity Map

```
User — PERSON RECORD (one row per human; credentials optional)
 │   identity: fullName, phone, email?, dateOfBirth?, address?, nationalId?
 │   lifecycle: status = Provisional -> Active | Inactive
 │              verifiedAt / verifiedBy   <- stamped on arrival
 │              passwordHash?             <- null = cannot log in
 │
 ├── Appointment ──── DoctorSchedule       [points at User, NOT PatientProfile]
 │    ├── bookingChannel: Online | FrontDesk | Phone
 │    ├── assistantId → StaffProfile
 │    └── followedUpBy → User (Receptionist)
 │         └─ Online + NoShow + still Provisional = the reschedule chase
 │
 ├── StaffProfile — EMPLOYMENT ONLY
 │    │   joinDate, specialty?, licenseNumber?, wageType, hourlyRate?
 │    ├── AttendanceLog (clock-in / clock-out per shift)
 │    ├── CommissionEntry ←─────────────────────────────────────────────┐
 │    ├── PayrollAdjustment [Manager-only] (credits / debits)           │
 │    └── PayrollRecord [Manager-only]                                  │
 │         ├── ← AttendanceLog (period totals → basePay)                │
 │         ├── ← CommissionEntry (all roles — procedure + event based)  │
 │         └── ← PayrollAdjustment (manual credits and debits)          │
 │                                                                      │
 └── PatientProfile — CARE RELATIONSHIP ONLY                            │
      │   created on arrival; its existence = "this person is a patient"│
      │   emergencyContact?, referralSource?, createdBy, createdAt      │
      ├── HealthRecord                                                  │
      ├── PatientMedia (X-rays, CBCT, before/after photos)              │
      └── TreatmentPlan                                                 │
           ├── TreatmentProcedure ─── ProcedureInstruction              │
           │    ├── assistantId → StaffProfile                          │
           │    ├── TreatmentProgress                                   │
           │    ├── ProcedureSupplyList ── InventoryItem                │
           │    └── ──[on complete]──► CommissionEntry (x2: doctor + assistant)
           ├── DiscountProposal (doctor → manager approval)
           ├── SpecialProcedureProposal (doctor → manager approval)
           └── Invoice
                └── Payment

ReceptionistPerformanceLog (standalone — bridges StaffProfile ↔ PatientProfile)
 ├── receptionistId → StaffProfile
 ├── patientId → PatientProfile
 ├── appointmentId → Appointment (nullable)
 └── ──[on write]──► CommissionEntry (sourceType = ReceptionistEvent) ──┘

CommissionRule [Manager-only] (set by Manager — covers all commissionable roles)
 ├── role: Doctor | Assistant | Receptionist
 ├── serviceCategoryId → ServiceCategory (nullable, for Doctor/Assistant)
 ├── eventType: NewPatientRegistered | SuccessfulFollowUp (nullable, for Receptionist)
 └── staffId → StaffProfile (nullable — individual contract override)

PayrollAdjustment [Manager-only] (bridges StaffProfile ↔ PayrollRecord)
 ├── staffId → StaffProfile
 ├── direction: Credit | Debit
 ├── relatedCommissionEntryId → CommissionEntry (nullable — for commission clawbacks)
 └── relatedInvoiceId → Invoice (nullable — for patient refund deductions)

ServiceCategory ─── PriceList (set by Manager)
                └── Promotion (set by Manager)

InventoryItem ─── Vendor
              └── InventoryLog

Notification (broadcast or targeted, sent by any staff role)
```

---

## Key Design Decisions

### 1. `User` is a person record, not a login
Every human gets exactly one `User` row — staff, patient, or someone who has only ever booked online. Identity (`fullName`, `phone`, `address`, `dateOfBirth`, `nationalId`) lives here once. `StaffProfile` holds employment data only; `PatientProfile` holds the care relationship only. Neither duplicates identity.

This matters most for `nationalId`: a person has one national ID. Held on both profiles it can drift, and you could never detect that your hygienist is also a patient. Held here with a `UNIQUE` constraint, that deduplication is free.

`role` governs system access; having a `PatientProfile` governs whether someone receives care. They are orthogonal — a doctor who is also a patient keeps `role = Doctor` and simply has both profiles.

### 2. Three facts about a person move independently
Bundling "has an account" into one flag is what makes walk-ins and online no-shows awkward. Split into three, every intake path falls out of one table:

| Fact | Becomes true when | Held by |
|------|-------------------|---------|
| We know who they are | First contact | the row exists |
| We have verified them | They arrive and someone checks their documents | `verifiedAt` / `verifiedBy` |
| They can log in | Optional; may never happen | `passwordHash` |

Two invariants enforce it: `status = Active` requires `verifiedAt` **and** `verifiedBy`; `passwordHash` requires `email`. A verified walk-in with no email is a perfectly valid Active patient who simply cannot log in.

`nationalId` is stored as **text, never a numeric type** — it is an identifier, not a quantity, and leading zeros are significant. Vietnamese CCCD is exactly 12 digits.

### 3. `Appointment` points at `User`, not `PatientProfile`
An online booking is made *before* the person has arrived and become a patient, so the appointment must be able to reference a `Provisional` person.

The alternative — a separate `lead` table for online bookers — looks tidier until you notice the appointment has to point at *someone*. Two tables force a polymorphic FK, turn every "who is coming tomorrow" query into a `UNION`, and make conversion a four-statement transaction that can strand orphans if it half-fails.

With one table, **conversion on arrival is one `UPDATE` plus one `INSERT`** — the appointment's FK never changes, because it was valid from the moment it was booked. `TreatmentPlan` and `Invoice` still reference `PatientProfile`: you can book before you are a patient, but you cannot carry a treatment plan or an invoice until you are.

### 4. `TreatmentPlan` is the clinical anchor
Everything clinical orbits the treatment plan: procedures, progress logs, notes, discounts, invoicing. A patient may have multiple treatment plans over time (e.g., one for orthodontics, one for implants).

### 5. Procedures are typed by `ServiceCategory`
`ServiceCategory` carries the `isSpecial` flag. Special categories (implant, orthodontic) require a `SpecialProcedureProposal` approved by the manager before the plan is activated. This matches the doctor's approval workflow.

### 6. Pricing is time-versioned
`PriceList` records carry an `effectiveFrom` date so historical invoices remain correct after the manager changes prices.

### 7. Discounts flow through two paths
- **Manager-set promotions**: `Promotion` entities applied at invoice time.
- **Doctor-proposed discounts**: `DiscountProposal` linked to a specific `TreatmentPlan`; requires manager approval before being applied to the `Invoice`.

### 8. Inventory is dual-purpose
`ProcedureSupplyList` is a template per `ProcedureInstruction` (what supplies are expected). `InventoryLog` records actual consumption or restocking events. Assistants work from both views.

### 9. `Notification` is a first-class entity
Paging between staff (doctor → assistant, manager → all) is tracked as notifications, not just ephemeral pushes. This supports audit and follow-up reminders.

### 10. Payroll is built from two independent streams
`PayrollRecord.netPay = basePay + commissionTotal − deductions`. Base pay comes from `AttendanceLog` (hours-based) or a fixed monthly rate. Commission comes from `CommissionEntry` records — the same mechanism for every staff role. There is no separate "performance bonus" stream; receptionist KPI bonuses flow through `CommissionEntry` like any other commission.

### 11. `CommissionRule` covers all commissionable roles with a single unified structure
One entity replaces two separate systems. For Doctor/Assistant the rule is scoped by `serviceCategoryId`; for Receptionist it is scoped by `eventType`. A nullable `staffId` field enables individual contract rates that override the role-level defaults. Rules are time-versioned with `effectiveFrom`, and each `CommissionEntry` locks in the rule at the time the event occurred — historical payroll is never retroactively changed.

### 12. `ReceptionistPerformanceLog` is a standalone event log, not a bonus ledger
It is a bridge between `StaffProfile` and `PatientProfile` that records *what happened* (which receptionist brought in which patient). Commission amounts live in `CommissionEntry`, not here. This separation keeps the event record clean and auditable independently of payroll configuration. The manager can see "receptionist A registered 12 new patients this month" separately from "how much did we pay her for that."

### 13. `CommissionEntry` uses `sourceType` to support two trigger paths
- `ProcedureCompleted`: created when a `TreatmentProcedure` moves to Completed. Two entries are written — one for the doctor, one for the assistant.
- `ReceptionistEvent`: created immediately when a `ReceptionistPerformanceLog` record is written.

In both cases the commission base value (`commissionBase`) is snapshotted at creation time so the manager's payroll review always shows the exact calculation, even if prices or rules change later.

### 14. Commission dashboard is Manager-only
`CommissionRule`, `CommissionEntry`, `PayrollAdjustment`, and the full `PayrollRecord` breakdown are visible only to the Manager role. Staff see only their own net pay on their payslip — not the commission rates, individual commission entries, or adjustment reasons. This is enforced at the API permission layer, not the data model.

### 15. Manual payroll adjustments are immutable once payroll is finalized
`PayrollAdjustment` records in `Pending` status can be edited or deleted by the manager before payroll is approved. Once a payroll is finalized (`status = Approved`), all linked adjustments become `IncludedInPayroll` and are locked. Any subsequent correction requires a new offsetting adjustment in the next payroll period — there is no in-place editing of settled records. This preserves a clean audit trail for disputes or accounting review.

The `direction` field (Credit / Debit) with a mandatory `reason` field means every non-system adjustment is traceable to a manager decision and a written business justification. Typical debit scenarios: patient refund caused by a procedure error (link `relatedInvoiceId`), commission clawback on a cancelled treatment (link `relatedCommissionEntryId`). Typical credit scenarios: discretionary end-of-year bonus, short-notice shift coverage.
