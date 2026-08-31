# KPX — Core Entity Overview

## Entity Domains

The system is organized into 8 domains, each grouping entities by concern.

| Domain | Entities |
|--------|----------|
| Identity & Access | User, StaffProfile, PatientProfile |
| Scheduling | DoctorSchedule, Appointment |
| Clinical | HealthRecord, TreatmentPlan, TreatmentProcedure, **ProcedureSession**, ProcedureInstruction, PatientMedia |
| Dental Charting | Tooth, ToothCondition, ProcedureTooth |
| Catalog & Pricing | ServiceCategory, **MaterialOption**, PriceList, Promotion, DiscountProposal, SpecialProcedureProposal |
| Billing | Invoice, **InvoiceLine**, Payment |
| Inventory | InventoryItem, InventoryLog, Vendor, ProcedureSupplyList |
| Communication & HR | Notification, AttendanceLog, WageRate, CommissionRule, CommissionEntry, ReceptionistPerformanceLog (standalone bridge), PayrollAdjustment, PayrollRecord |

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
 │     StaffProfile.employmentStatus Intern|Active -> staff portal
 │     (a person may hold both; a departed doctor keeps only the patient one)
 │
 ├── Appointment ──── DoctorSchedule       [points at User, NOT PatientProfile]
 │    ├── bookingChannel: Online | FrontDesk | Phone
 │    ├── assistantId → StaffProfile
 │    └── followedUpBy → User (Receptionist)
 │         └─ Online + NoShow + still Provisional = the reschedule chase
 │
 ├── StaffProfile — EMPLOYMENT ONLY
 │    │   employmentStatus = Intern | Active | OnLeave | Departed  <- gates staff portal
 │    │   joinDate, endDate?, specialty?, licenseNumber?    (no pay fields — see WageRate)
 │    ├── AttendanceLog (clock-in / clock-out per shift)
 │    ├── WageRate (versioned pay: one row per rate, effectiveFrom)
 │    ├── CommissionEntry ←─────────────────────────────────────────────┐
 │    ├── PayrollAdjustment [Manager-only] (credits / debits)           │
 │    └── PayrollRecord [Manager-only]                                  │
 │         ├── ← AttendanceLog × WageRate (hours × rate on that day)     │
 │         ├── ← CommissionEntry (all roles — procedure + event based)  │
 │         └── ← PayrollAdjustment (manual credits and debits)          │
 │                                                                      │
 └── PatientProfile — CARE RELATIONSHIP ONLY                            │
      │   created on arrival; its existence = "this person is a patient"│
      │   emergencyContact?, referralSource?, createdBy, createdAt      │
      ├── HealthRecord                                                  │
      ├── PatientMedia (X-rays, CBCT, before/after photos)              │
      ├── ToothCondition ── Tooth   [the odontogram: Active rows = chart]│
      │    └── resolvedByProcedureId → TreatmentProcedure               │
      └── TreatmentPlan                                                 │
           ├── TreatmentProcedure ─── ProcedureInstruction              │
           │    │   status: Proposed → Accepted → … → Completed          │
           │    │   materialOptionId → MaterialOption (changes the price) │
           │    ├── ProcedureTooth ── Tooth  (which teeth + surfaces)    │
           │    ├── ProcedureSupplyList ── InventoryItem                │
           │    └── ProcedureSession  ── Appointment   [THE BILLING UNIT]│
           │         │   sessionNumber, performedBy, assistantId         │
           │         │   billableAmount                                  │
           │         ├──[on complete]──► InvoiceLine ──► Invoice         │
           │         └──[on complete]──► CommissionEntry (doctor + assistant)
           ├── DiscountProposal (doctor → manager approval)
           ├── SpecialProcedureProposal (doctor → manager approval)
           └── Invoice  (no longer 1:1 with the plan — stage billing allowed)
                ├── InvoiceLine  (frozen snapshot: description, teeth, price, qty)
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

Tooth — STATIC REFERENCE (FDI / ISO 3950, 52 rows: 32 permanent + 20 primary)
 │   code = quadrant digit + position digit   e.g. 46 = lower right first molar
 └── validSurfaces: MIDBL anterior (incisal) | MODBL posterior (occlusal)

ServiceCategory ─── MaterialOption (Zirconia | PFM | Osstem | …)
                │        └── PriceList per material, versioned
                ├── PriceList (set by Manager; base price when material is null)
                ├── Promotion (set by Manager)
                ├── toothScope:   None | SingleTooth | MultiTooth | Quadrant | Arch | FullMouth
                └── pricingBasis: PerProcedure | PerTooth | PerSurface | PerQuadrant

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
| Authentication | How do they prove it to the system? | mechanism chosen (below); **storage deferred** |

`status = Active` requires `verifiedAt` **and** `verifiedBy`. `nationalId` is stored as **text, never a numeric type** — it is an identifier, not a quantity, and leading zeros are significant. Vietnamese CCCD is exactly 12 digits.

No credential or OTP tables exist yet. What is already settled:

- **Provisional people never sign in**, by any route. They receive booking confirmations and reminders by phone or email, and contact the clinic to change anything. They *do* have a phone, so an OTP would technically reach them — but issuing one would admit an unverified person and bypass the very in-person check that `Active` exists to record.
- **Patients use no password.** Two routes, both reading fields the record already has:

| Route | Uses | Proves |
|-------|------|--------|
| **Phone OTP** | `phone` | *possession* — they hold the handset |
| Identifying fields | `fullName` + `phone` + `nationalId` | *knowledge* — required combination still open |

- **Staff use a username and password, or a hardware chip.** Mechanism still open.

Phone OTP is the better patient default. It does not depend on the CCCD being confidential — and a CCCD is **not** a secret: it appears on documents and is routinely handed to hotels and banks. OTP is also the only route that works for a patient with neither an email nor a CCCD, such as a foreign patient or a walk-in verified by other means.

Because every route reads columns the `User` record already carries, credential and OTP storage can be designed later without disturbing the person model.

### 3. Portal access comes from profiles, not from `role`
There are two portals, and what grants them is what a person **has**, not what their `role` says:

| Portal | Granted when |
|--------|--------------|
| Patient | `User.status = Active` and a `PatientProfile` exists |
| Staff | `User.status = Active` and a `StaffProfile` with `employmentStatus` of Intern or Active exists |

`role` then governs permissions *inside* the staff portal. Patients can never reach it.

This is what makes the dual cases work without special-casing. A doctor who is also a patient holds both profiles and reaches both portals. A doctor who **quits but stays a patient** loses the staff portal the moment `employmentStatus` changes, and keeps the patient portal — no record surgery, no role rewrite.

### 4. Employment ends on `StaffProfile`; the person continues on `User`
`User.status` describes the **person** — known, verified, or deactivated. `StaffProfile.employmentStatus` describes the **job**. Keeping them apart is what allows a departed staff member to remain a patient at the clinic.

`employmentStatus` is `Intern | Active | OnLeave | Departed`; `Departed` requires an `endDate`.

| Status | Assignable to new work | Staff portal |
|--------|------------------------|--------------|
| Intern | yes | yes |
| Active | yes | yes |
| OnLeave | no | no |
| Departed | no | no |

`Intern` covers someone accepted and in training or on trial, not yet full-time. They are working, so they are assignable and reach the staff portal — **the distinction from `Active` is terms, not access.** Their different pay needs no new fields: `wageType`/`hourlyRate` carry the trainee rate, and a `CommissionRule` scoped to that `staffId` carries a reduced rate, or none at all if interns earn no commission.

`OnLeave` covers maternity, sabbatical or long illness — not bookable, but not gone.

One consequence to settle later: `hourlyRate` holds a single value, so promoting an intern overwrites the trainee rate, and recomputing an earlier payroll period would silently use the new one. That is the same problem `PriceList` solves with `effectiveFrom`; wages likely want the same treatment before payroll runs on real money.

Departure is a **state change, never a deletion**. Past treatment plans, appointments, commission entries and payroll records keep pointing at the departed staff member; that is precisely what keeps last year's reports correct.

### 5. `Appointment` points at `User`, not `PatientProfile`
An online booking is made *before* the person has arrived and become a patient, so the appointment must be able to reference a `Provisional` person.

The alternative — a separate `lead` table for online bookers — looks tidier until you notice the appointment has to point at *someone*. Two tables force a polymorphic FK, turn every "who is coming tomorrow" query into a `UNION`, and make conversion a four-statement transaction that can strand orphans if it half-fails.

With one table, **conversion on arrival is one `UPDATE` plus one `INSERT`** — the appointment's FK never changes, because it was valid from the moment it was booked. `TreatmentPlan` and `Invoice` still reference `PatientProfile`: you can book before you are a patient, but you cannot carry a treatment plan or an invoice until you are.

### 6. A proposal is a drawing; only completed work changes the record
The chart renders three layers, and only two of them are the patient's actual dental health:

| Layer | Source | Is it the record? |
|-------|--------|-------------------|
| Existing state | `ToothCondition`, status Active | **yes** |
| Findings to treat | `ToothCondition`, pathology types, status Active | **yes** |
| Planned work | `ProcedureTooth` on Proposed / Accepted / Scheduled procedures | **no** — an overlay for the doctor to read |

A doctor can plan a crown on 24, have it appear on the chart, and the tooth's recorded condition is untouched until the work is done. That separation is what lets the chart double as a treatment-planning surface without corrupting the clinical record.

Two writes follow from real work, at different moments. A **finding** may be charted during any session — a clinician who spots new caries mid-treatment records it immediately. The **resulting condition** from `ServiceCategory.resultingConditionType` lands only when the procedure's *final* session completes, because a half-placed crown is not a crown and a root canal is not treated until it is obturated. For single-session procedures the two coincide.

This is also the read model the chart screen needs: all 52 `Tooth` rows for the empty chart, joined to that patient's `ToothCondition` rows and to `ProcedureTooth` → `TreatmentProcedure` filtered by status. One projection, rather than five ad-hoc endpoints.

### 7. One procedure can resolve many findings; one finding cannot span many procedures
`resolvedByProcedureId` sits on the **condition**, which makes it many-to-one. A single full-mouth scaling resolving calculus on twenty teeth is twenty condition rows pointing at one procedure — already supported.

The reverse is not expressible. Deep caries needing a root canal *and* a crown is one finding and two procedures; it must point at whichever procedure completes its treatment. The chart reads correctly throughout — the caries stays Active while treatment is under way — and only the audit trail loses the detail that two procedures shared the work.

That case is common enough in dentistry to be worth naming rather than discovering later. A junction table would express it, and can be added without migrating existing rows, so the cost of waiting is low.

### 8. The tooth is a dimension, not a note
Dentistry happens to a specific tooth, and usually to specific surfaces of it. `ProcedureTooth` records which teeth and surfaces each procedure addresses; `ToothCondition` records what was found on a tooth and whether it has been dealt with.

The alternative — a tooth number written into `doctorNote` — fails the moment anyone needs to *use* it. Free text cannot be counted for billing, drawn on a chart, filtered for recall, or audited. It is also what the earlier seed data quietly did (`'Atraumatic extraction #46'`), which is exactly the smell this entity removes.

`ProcedureTooth` is a junction rather than a column because the relationship is many-to-many in both directions: a three-unit bridge covers three teeth (two `Abutment`, one `Pontic`), full-mouth scaling covers all of them, and a single molar accumulates a filling, then a crown, then an extraction over a decade.

### 9. FDI notation, with the patient's left and right
Codes are FDI / ISO 3950: quadrant digit then position digit, `11`–`48` for the 32 permanent teeth and `51`–`85` for the 20 primary ones. Primary teeth are not optional — the clinic treats children, and a seven-year-old is in mixed dentition.

`Tooth` is a static 52-row reference table rather than a bare `CHECK` constraint, because those rows carry information the rest of the system needs: `validSurfaces` (`MIDBL` anterior, `MODBL` posterior) validates a filling, `isAnterior` drives clinical and pricing rules, and `name`/`nameVi` let the record read as words. `universalCode` cross-references US 1–32 numbering for imaging software that speaks Universal rather than FDI.

Side is always the **patient's** left and right, never the viewer's. It is the most common charting error, so it is stated on the entity itself.

### 10. Tooth-level work changes how an invoice is calculated
`ServiceCategory` gains `toothScope` (how many teeth a service applies to — validation) and `pricingBasis` (what the unit price is charged per — billing). They are independent: a full-mouth scaling can still be priced per quadrant.

`Invoice.subtotal` was "the sum of procedure prices". With tooth-level work it becomes the sum of *unit price × billable quantity*, where quantity follows `pricingBasis` — `1` for PerProcedure, the `ProcedureTooth` count for PerTooth, the total surface count for PerSurface, the distinct quadrant count for PerQuadrant.

A two-surface filling and a three-surface filling are different money. Without this, either the schema cannot express the difference or someone types the right number into a free-text field and nothing can check it.

### 11. The session is the unit of work, and the unit of payment
A procedure is a clinical step; a **session** is one visit's worth of it. Root canals, crowns and orthodontic courses all take several visits, and the clinic is paid as each one completes — so money is recognised per session, never per procedure.

`ProcedureSession` replaces the former `TreatmentProgress`, which already described itself as "what happened during a procedure session". It now carries the session's identity, staff and money as well as its notes.

**Every procedure has at least one session, even a single-visit filling.** That is what keeps the billing rule free of special cases: *one completed session, one invoice line.* The alternative — billing whole procedures except when they are multi-visit — is two rules that will drift apart.

Sessions also fix a modelling error. `Appointment.treatmentProcedureId` was a single FK, so a visit could only ever record one procedure — yet a filling and a scale in the same chair is an ordinary afternoon. The link is now inverted: an appointment has many sessions, each pointing at its own procedure.

And because a session carries its own `performedBy` and `assistantId`, a procedure delivered over three visits by two different doctors and two different assistants attributes each visit to whoever was actually there. Commission follows the same granularity for the same reason: **only the people who did the work are paid.** `TreatmentPlan.doctorId` owns the case but earns nothing — they may not have been in the room.

### 12. Two payment modes, one mechanism
`TreatmentPlan.paymentMode` records what was agreed: **Upfront** or **PerSession**. Both produce `InvoiceLine` rows — only the trigger and the reference differ.

| Mode | Line references | Created when | Line total |
|------|-----------------|--------------|------------|
| PerSession | `sessionId` | each session completes | that session's `billableAmount` |
| Upfront | `procedureId` | the patient accepts | the procedure's full total |

A procedure's total is split across its sessions by `billableAmount`, summing to the whole. An even split is the default; a doctor may weight it, since an implant is commonly 60% at fixture placement and 40% at the crown.

This is also why `Invoice` is no longer 1:1 with `TreatmentPlan`. A twenty-month orthodontic course cannot sit on one invoice carried for two years while the patient pays per visit. The plan is a clinical container; the invoice is a financial document, and they need not line up.

### 13. `InvoiceLine` freezes the bill away from the clinical record
`Invoice` previously held only a subtotal — no itemisation, and nothing connecting money back to a tooth. `InvoiceLine` adds both, and every descriptive field on it is a **snapshot**.

That is not belt-and-braces. Clinical records get amended — `ToothCondition` carries `EnteredInError` precisely because corrections happen. If an invoice were a live view over procedures, correcting a tooth number next month would silently change a bill already issued and paid. Freezing the line decouples the financial record from the clinical one, and `Invoice.subtotal` becomes `SUM(lineTotal)` — derivable and auditable rather than asserted.

Only a **Completed** session, or an **Accepted** procedure paid up front, may produce a line. A `Declined` procedure can never leak into a total.

### 14. Material changes the price, not the service
A crown is one clinical service, but zirconia and porcelain-fused-metal are not the same money — and the patient chooses. `MaterialOption` hangs variants off a `ServiceCategory`, and `PriceList` gains a nullable `materialOptionId`: null is the category's base price, a value prices that specific material. Resolution falls back to the base row, so adding a material never requires repricing everything.

Modelling these as separate categories — "Zirconia Crown", "PFM Crown" — would duplicate `isSpecial`, `toothScope`, `pricingBasis`, `resultingConditionType` and the instruction templates, and the catalogue would double again with every new implant brand. Clinical rules belong on the service; commercial choice belongs on the material.

### 15. Patient acceptance and manager approval are different gates
`TreatmentProcedure.status` gains `Proposed`, `Accepted` and `Declined`. A proposal is not a separate entity — it is a procedure that has not happened yet, which is also what makes it draw on the chart as planned work.

Manager approval (`SpecialProcedureProposal`, `DiscountProposal`) is a different question with a different reviewer. Keeping them apart means a doctor can propose work to a patient without a manager in the loop, and the manager still gates the cases that need it.

A price rise applies to new procedures, not to one already under way: `unitPrice` resolves once, at the first completed session, so a patient mid-root-canal does not see the rate move between visits.

### 16. `TreatmentPlan` is the clinical anchor
Everything clinical orbits the treatment plan: procedures, progress logs, notes, discounts, invoicing. A patient may have multiple treatment plans over time (e.g., one for orthodontics, one for implants).

### 17. Procedures are typed by `ServiceCategory`
`ServiceCategory` carries the `isSpecial` flag. Special categories (implant, orthodontic) require a `SpecialProcedureProposal` approved by the manager before the plan is activated. This matches the doctor's approval workflow.

### 18. Pricing is time-versioned
`PriceList` records carry an `effectiveFrom` date so historical invoices remain correct after the manager changes prices.

### 19. Discounts flow through two paths
- **Manager-set promotions**: `Promotion` entities applied at invoice time.
- **Doctor-proposed discounts**: `DiscountProposal` linked to a specific `TreatmentPlan`; requires manager approval before being applied to the `Invoice`.

### 20. Inventory is dual-purpose
`ProcedureSupplyList` is a template per `ProcedureInstruction` (what supplies are expected). `InventoryLog` records actual consumption or restocking events. Assistants work from both views.

### 21. `Notification` is a first-class entity
Paging between staff (doctor → assistant, manager → all) is tracked as notifications, not just ephemeral pushes. This supports audit and follow-up reminders.

### 22. Pay rates are versioned, never overwritten
`WageRate` holds one row per rate a staff member has ever been on, each with an `effectiveFrom`. A raise or a promotion **inserts** a row; it never edits one. The rate for a day of work is the row with the greatest `effectiveFrom` on or before that day — the same mechanism `PriceList` uses to price a procedure by the date it was performed.

A single `hourlyRate` column on `StaffProfile` could only ever hold the *current* rate. That answers "what do we pay them now" and nothing else:

| Question | Single column | Versioned rows |
|----------|---------------|----------------|
| What is this person paid today? | yes | yes |
| What were they paid last quarter? | **no — overwritten** | yes |
| Can we reproduce an old payslip? | **no** | yes |
| Promotion lands mid-period? | **cannot express** | resolves per day |

The last row is the one that forces the design. An intern promoted on the 15th has half a month at the trainee rate and half at the new one; with a single column you must pick one rate for the whole period and both choices are wrong. Because `WageRate` is resolved per `AttendanceLog` day, that case needs no special handling at all.

Settled payroll was never *wrong* under the old shape — `PayrollRecord.basePay` stores the computed figure. But it was not **reproducible**, which is what a labour inspection or a staff dispute actually asks for. `basePay` remains a stored snapshot of what was settled; it is now also derivable from the rate history.

Open decision: for `wageType = Monthly`, a rate change mid-period needs a pro-rating rule — calendar days or working days. `Hourly` needs none.

### 23. Payroll is built from two independent streams
`PayrollRecord.netPay = basePay + commissionTotal − deductions`. Base pay comes from `AttendanceLog` (hours-based) or a fixed monthly rate. Commission comes from `CommissionEntry` records — the same mechanism for every staff role. There is no separate "performance bonus" stream; receptionist KPI bonuses flow through `CommissionEntry` like any other commission.

### 24. `CommissionRule` covers all commissionable roles with a single unified structure
One entity replaces two separate systems. For Doctor/Assistant the rule is scoped by `serviceCategoryId`; for Receptionist it is scoped by `eventType`. A nullable `staffId` field enables individual contract rates that override the role-level defaults. Rules are time-versioned with `effectiveFrom`, and each `CommissionEntry` locks in the rule at the time the event occurred — historical payroll is never retroactively changed.

### 25. `ReceptionistPerformanceLog` is a standalone event log, not a bonus ledger
It is a bridge between `StaffProfile` and `PatientProfile` that records *what happened* (which receptionist brought in which patient). Commission amounts live in `CommissionEntry`, not here. This separation keeps the event record clean and auditable independently of payroll configuration. The manager can see "receptionist A registered 12 new patients this month" separately from "how much did we pay her for that."

### 26. No staff member earns commission on their own treatment
Staff are welcome to be treated at the clinic — the rule is only about who gets paid. A `CommissionEntry` may not be created where the credited staff member resolves to the same `User` as the patient on that procedure's `TreatmentPlan`. It applies to the doctor and the assistant alike.

If Dr. Mai treats Dr. Minh, Dr. Mai earns her commission normally; Dr. Minh earns nothing, because he is the patient. Without this rule, consolidating staff and patients onto one `User` row would quietly let a doctor bill the clinic for treating themselves.

### 27. `CommissionEntry` uses `sourceType` to support two trigger paths
- `ProcedureCompleted`: created when a `TreatmentProcedure` moves to Completed. Two entries are written — one for the doctor, one for the assistant.
- `ReceptionistEvent`: created immediately when a `ReceptionistPerformanceLog` record is written.

In both cases the commission base value (`commissionBase`) is snapshotted at creation time so the manager's payroll review always shows the exact calculation, even if prices or rules change later.

### 28. Commission dashboard is Manager-only
`CommissionRule`, `CommissionEntry`, `PayrollAdjustment`, and the full `PayrollRecord` breakdown are visible only to the Manager role. Staff see only their own net pay on their payslip — not the commission rates, individual commission entries, or adjustment reasons. This is enforced at the API permission layer, not the data model.

### 29. Manual payroll adjustments are immutable once payroll is finalized
`PayrollAdjustment` records in `Pending` status can be edited or deleted by the manager before payroll is approved. Once a payroll is finalized (`status = Approved`), all linked adjustments become `IncludedInPayroll` and are locked. Any subsequent correction requires a new offsetting adjustment in the next payroll period — there is no in-place editing of settled records. This preserves a clean audit trail for disputes or accounting review.

The `direction` field (Credit / Debit) with a mandatory `reason` field means every non-system adjustment is traceable to a manager decision and a written business justification. Typical debit scenarios: patient refund caused by a procedure error (link `relatedInvoiceId`), commission clawback on a cancelled treatment (link `relatedCommissionEntryId`). Typical credit scenarios: discretionary end-of-year bonus, short-notice shift coverage.
