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
 │   lifecycle: status = Provisional -> Active | Inactive   (the PERSON, never employment)
 │              verifiedAt / verifiedBy   <- stamped on arrival
 │
 │   PORTALS are granted by profile, not by role:
 │     PatientProfile exists                      -> patient portal
 │     StaffProfile.employmentStatus = Active     -> staff portal
 │     (a person may hold both; a departed doctor keeps only the patient one)
 │
 ├── Appointment ──── DoctorSchedule       [points at User, NOT PatientProfile]
 │    ├── bookingChannel: Online | FrontDesk | Phone
 │    ├── assistantId → StaffProfile
 │    └── followedUpBy → User (Receptionist)
 │         └─ Online + NoShow + still Provisional = the reschedule chase
 │
 ├── StaffProfile — EMPLOYMENT ONLY
 │    │   employmentStatus = Active | OnLeave | Departed   <- gates the staff portal
 │    │   joinDate, endDate?, specialty?, licenseNumber?, wageType, hourlyRate?
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

### 2. Identity, verification and authentication are three separate layers
Bundling them into one "has an account" flag is what makes walk-ins and online no-shows awkward. Held apart, every intake path runs through one table:

| Layer | Question | Held by |
|-------|----------|---------|
| Identity | Who is this person? | the `User` row exists |
| Verification | Have we checked them in person? | `verifiedAt` / `verifiedBy` |
| Authentication | How do they prove it to the system? | **deferred — not modelled yet** |

`status = Active` requires `verifiedAt` **and** `verifiedBy`. `nationalId` is stored as **text, never a numeric type** — it is an identifier, not a quantity, and leading zeros are significant. Vietnamese CCCD is exactly 12 digits.

The authentication layer is deliberately empty for now. What is already settled about it:

- **Provisional people never sign in.** They receive booking confirmations and reminders by phone or email, and contact the clinic to change anything. No credential is ever issued to someone who has not arrived.
- **Patients use no password.** They identify with a combination of `fullName`, `phone` and `nationalId` — all already on the `User` record, so patient sign-in needs no new columns. Which combination is required is still open.
- **Staff use a username and password, or a hardware chip.** Mechanism still open.

Because none of this needs new columns yet, credential storage can be designed later without disturbing the person model.

### 3. Portal access comes from profiles, not from `role`
There are two portals, and what grants them is what a person **has**, not what their `role` says:

| Portal | Granted when |
|--------|--------------|
| Patient | `User.status = Active` and a `PatientProfile` exists |
| Staff | `User.status = Active` and a `StaffProfile` with `employmentStatus = Active` exists |

`role` then governs permissions *inside* the staff portal. Patients can never reach it.

This is what makes the dual cases work without special-casing. A doctor who is also a patient holds both profiles and reaches both portals. A doctor who **quits but stays a patient** loses the staff portal the moment `employmentStatus` changes, and keeps the patient portal — no record surgery, no role rewrite.

### 4. Employment ends on `StaffProfile`; the person continues on `User`
`User.status` describes the **person** — known, verified, or deactivated. `StaffProfile.employmentStatus` describes the **job**. Keeping them apart is what allows a departed staff member to remain a patient at the clinic.

`employmentStatus` is `Active | OnLeave | Departed`; `Departed` requires an `endDate`. Only `Active` staff may be assigned to new appointments, procedures or schedules — `OnLeave` covers maternity, sabbatical or long illness, where someone is not bookable but has not left.

Departure is a **state change, never a deletion**. Past treatment plans, appointments, commission entries and payroll records keep pointing at the departed staff member; that is precisely what keeps last year's reports correct.

### 5. `Appointment` points at `User`, not `PatientProfile`
An online booking is made *before* the person has arrived and become a patient, so the appointment must be able to reference a `Provisional` person.

The alternative — a separate `lead` table for online bookers — looks tidier until you notice the appointment has to point at *someone*. Two tables force a polymorphic FK, turn every "who is coming tomorrow" query into a `UNION`, and make conversion a four-statement transaction that can strand orphans if it half-fails.

With one table, **conversion on arrival is one `UPDATE` plus one `INSERT`** — the appointment's FK never changes, because it was valid from the moment it was booked. `TreatmentPlan` and `Invoice` still reference `PatientProfile`: you can book before you are a patient, but you cannot carry a treatment plan or an invoice until you are.

### 6. `TreatmentPlan` is the clinical anchor
Everything clinical orbits the treatment plan: procedures, progress logs, notes, discounts, invoicing. A patient may have multiple treatment plans over time (e.g., one for orthodontics, one for implants).

### 7. Procedures are typed by `ServiceCategory`
`ServiceCategory` carries the `isSpecial` flag. Special categories (implant, orthodontic) require a `SpecialProcedureProposal` approved by the manager before the plan is activated. This matches the doctor's approval workflow.

### 8. Pricing is time-versioned
`PriceList` records carry an `effectiveFrom` date so historical invoices remain correct after the manager changes prices.

### 9. Discounts flow through two paths
- **Manager-set promotions**: `Promotion` entities applied at invoice time.
- **Doctor-proposed discounts**: `DiscountProposal` linked to a specific `TreatmentPlan`; requires manager approval before being applied to the `Invoice`.

### 10. Inventory is dual-purpose
`ProcedureSupplyList` is a template per `ProcedureInstruction` (what supplies are expected). `InventoryLog` records actual consumption or restocking events. Assistants work from both views.

### 11. `Notification` is a first-class entity
Paging between staff (doctor → assistant, manager → all) is tracked as notifications, not just ephemeral pushes. This supports audit and follow-up reminders.

### 12. Payroll is built from two independent streams
`PayrollRecord.netPay = basePay + commissionTotal − deductions`. Base pay comes from `AttendanceLog` (hours-based) or a fixed monthly rate. Commission comes from `CommissionEntry` records — the same mechanism for every staff role. There is no separate "performance bonus" stream; receptionist KPI bonuses flow through `CommissionEntry` like any other commission.

### 13. `CommissionRule` covers all commissionable roles with a single unified structure
One entity replaces two separate systems. For Doctor/Assistant the rule is scoped by `serviceCategoryId`; for Receptionist it is scoped by `eventType`. A nullable `staffId` field enables individual contract rates that override the role-level defaults. Rules are time-versioned with `effectiveFrom`, and each `CommissionEntry` locks in the rule at the time the event occurred — historical payroll is never retroactively changed.

### 14. `ReceptionistPerformanceLog` is a standalone event log, not a bonus ledger
It is a bridge between `StaffProfile` and `PatientProfile` that records *what happened* (which receptionist brought in which patient). Commission amounts live in `CommissionEntry`, not here. This separation keeps the event record clean and auditable independently of payroll configuration. The manager can see "receptionist A registered 12 new patients this month" separately from "how much did we pay her for that."

### 15. No staff member earns commission on their own treatment
Staff are welcome to be treated at the clinic — the rule is only about who gets paid. A `CommissionEntry` may not be created where the credited staff member resolves to the same `User` as the patient on that procedure's `TreatmentPlan`. It applies to the doctor and the assistant alike.

If Dr. Mai treats Dr. Minh, Dr. Mai earns her commission normally; Dr. Minh earns nothing, because he is the patient. Without this rule, consolidating staff and patients onto one `User` row would quietly let a doctor bill the clinic for treating themselves.

### 16. `CommissionEntry` uses `sourceType` to support two trigger paths
- `ProcedureCompleted`: created when a `TreatmentProcedure` moves to Completed. Two entries are written — one for the doctor, one for the assistant.
- `ReceptionistEvent`: created immediately when a `ReceptionistPerformanceLog` record is written.

In both cases the commission base value (`commissionBase`) is snapshotted at creation time so the manager's payroll review always shows the exact calculation, even if prices or rules change later.

### 17. Commission dashboard is Manager-only
`CommissionRule`, `CommissionEntry`, `PayrollAdjustment`, and the full `PayrollRecord` breakdown are visible only to the Manager role. Staff see only their own net pay on their payslip — not the commission rates, individual commission entries, or adjustment reasons. This is enforced at the API permission layer, not the data model.

### 18. Manual payroll adjustments are immutable once payroll is finalized
`PayrollAdjustment` records in `Pending` status can be edited or deleted by the manager before payroll is approved. Once a payroll is finalized (`status = Approved`), all linked adjustments become `IncludedInPayroll` and are locked. Any subsequent correction requires a new offsetting adjustment in the next payroll period — there is no in-place editing of settled records. This preserves a clean audit trail for disputes or accounting review.

The `direction` field (Credit / Debit) with a mandatory `reason` field means every non-system adjustment is traceable to a manager decision and a written business justification. Typical debit scenarios: patient refund caused by a procedure error (link `relatedInvoiceId`), commission clawback on a cancelled treatment (link `relatedCommissionEntryId`). Typical credit scenarios: discretionary end-of-year bonus, short-notice shift coverage.
