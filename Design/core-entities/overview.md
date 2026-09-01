# KPX — Core Entity Overview

## Entity Domains

The system is organized into 8 domains, each grouping entities by concern.

| Domain | Entities |
|--------|----------|
| Identity & Access | User, StaffProfile, PatientProfile |
| Scheduling | DoctorSchedule, Appointment, **Chair**, **ChairType** |
| Clinical | HealthRecord, TreatmentPlan, TreatmentProcedure, ProcedureDecision, ProcedureSession, ProcedureInstruction, **TreatmentFailure**, PatientMedia |
| Dental Charting | Tooth, ToothCondition, ProcedureTooth |
| Catalog & Pricing | ServiceCategory, **MaterialOption**, PriceList, Promotion, DiscountProposal, SpecialProcedureProposal |
| Billing | Invoice, **InvoiceLine**, Payment |
| Inventory | InventoryItem, **InventoryBatch**, InventoryLog, Vendor, ProcedureSupplyList |
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
 │    ├── chairId → Chair ── ChairType   [capacity: no two visits share a chair]
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
      │    └── ◄── addressesConditionId  (from ProcedureTooth)          │
      └── TreatmentPlan                                                 │
           ├── TreatmentProcedure ─── ProcedureInstruction              │
           │    │   status: Proposed → Accepted → … → Completed          │
           │    │   materialOptionId → MaterialOption (changes the price) │
           │    ├── ProcedureDecision  [append-only: who decided, why]   │
           │    ├── ProcedureTooth ── Tooth  (teeth + surfaces)          │
           │    │    └── addressesConditionId → ToothCondition           │
           │    ├── ProcedureSupplyList ── InventoryItem                │
           │    └── ProcedureSession  ── Appointment   [THE BILLING UNIT]│
           │         │   sessionNumber, performedBy, assistantId         │
           │         │   billableAmount                                  │
           │         ├──[on complete]──► InvoiceLine ──► Invoice         │
           │         └──[on complete]──► CommissionEntry (doctor + assistant)
           ├── DiscountProposal (doctor → manager approval)
           ├── SpecialProcedureProposal (doctor → manager approval)
           └── Invoice  (no longer 1:1 with the plan — stage billing allowed)
                ├── InvoiceLine  (frozen snapshot; negative = credit line)
                └── Payment  (direction In | Out — Out is a refund)

TreatmentFailure  (work failed; who pays for it)
 ├── procedureId → TreatmentProcedure   [the work that failed; stays Completed]
 ├── faultAttribution: ClinicTechnique | MaterialDefect | PatientFactor | Inconclusive
 ├── remedy: Refund | FreeRework | Both | None
 ├──► InvoiceLine (negative) + Payment (Out)      — money back to the patient
 ├──► TreatmentProcedure.remedyForFailureId       — free rework, bills nothing
 └──► PayrollAdjustment.relatedFailureId (Debit)  — charged to the staff at fault

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
                ├── Promotion — voucher code (XASH 10%, off the whole invoice)
                ├── toothScope:   None | SingleTooth | MultiTooth | Quadrant | Arch | FullMouth
                └── pricingBasis: PerProcedure | PerTooth | PerSurface | PerQuadrant

InventoryItem ─── Vendor
              ├── InventoryBatch  (lotNumber, expiryDate, unitCost) — FEFO
              └── InventoryLog ── batchId

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

### 5. Chairs are the real capacity limit, and chair type is a scheduling rule
Two dentists cannot both work if there is one chair. Doctors were modelled and chairs were not, so nothing in the design stopped two 09:00 bookings landing in the same position.

`Chair` fixes that, and its one invariant is the reason it exists: **no two appointments may occupy the same chair at overlapping times.** In PostgreSQL that is an exclusion constraint on (chair, time range); in SQLite it has to be enforced in the application.

`ChairType` turns the chair from a label into a rule. An implant needs the surgical position with its sterile field; a scale does not. `ServiceCategory.requiredChairTypeId` is **nullable, and null means any chair will do** — so the constraint is only stated where it is real, and the common case needs no configuration.

`Appointment.chairId` is nullable so a chair can be assigned on the day rather than at booking. That flexibility has a cost worth naming: an appointment with no chair consumes no capacity, so a booking flow that leaves it null can quietly overbook the clinic.

Booking needs three things to align — the doctor is free, the chair is free, and the clinic is open. The third is still missing: there is no clinic-hours entity, only per-doctor availability. Worth closing before the booking screen is built.

### 6. `Appointment` points at `User`, not `PatientProfile`
An online booking is made *before* the person has arrived and become a patient, so the appointment must be able to reference a `Provisional` person.

The alternative — a separate `lead` table for online bookers — looks tidier until you notice the appointment has to point at *someone*. Two tables force a polymorphic FK, turn every "who is coming tomorrow" query into a `UNION`, and make conversion a four-statement transaction that can strand orphans if it half-fails.

With one table, **conversion on arrival is one `UPDATE` plus one `INSERT`** — the appointment's FK never changes, because it was valid from the moment it was booked. `TreatmentPlan` and `Invoice` still reference `PatientProfile`: you can book before you are a patient, but you cannot carry a treatment plan or an invoice until you are.

### 7. A proposal is a drawing; only completed work changes the record
The chart renders three layers, and only two of them are the patient's actual dental health:

| Layer | Source | Is it the record? |
|-------|--------|-------------------|
| Existing state | `ToothCondition`, status Active | **yes** |
| Findings to treat | `ToothCondition`, pathology types, status Active | **yes** |
| Planned work | `ProcedureTooth` on Proposed / Accepted / Scheduled procedures | **no** — an overlay for the doctor to read |

A doctor can plan a crown on 24, have it appear on the chart, and the tooth's recorded condition is untouched until the work is done. That separation is what lets the chart double as a treatment-planning surface without corrupting the clinical record.

Two writes follow from real work, at different moments. A **finding** may be charted during any session — a clinician who spots new caries mid-treatment records it immediately. The **resulting condition** from `ServiceCategory.resultingConditionType` lands only when the procedure's *final* session completes, because a half-placed crown is not a crown and a root canal is not treated until it is obturated. For single-session procedures the two coincide.

This is also the read model the chart screen needs: all 52 `Tooth` rows for the empty chart, joined to that patient's `ToothCondition` rows and to `ProcedureTooth` → `TreatmentProcedure` filtered by status. One projection, rather than five ad-hoc endpoints.

### 8. Findings and procedures are many-to-many, carried on `ProcedureTooth`
Clinically the relationship runs both ways, and both directions are ordinary. Deep caries on 46 needs a root canal **and then** a crown — one finding, two procedures. A full-mouth scaling clears calculus on twenty teeth — one procedure, twenty findings.

`ProcedureTooth.addressesConditionId` carries it. Because that table is already the (procedure × tooth) junction, and a finding is tooth-scoped, hanging the clinical *why* there gives a full many-to-many link **without a third table**: the root canal and the crown each have a `ProcedureTooth` row on 46 pointing at the same finding, while the scaling has twenty rows each pointing at its own.

The one shape it cannot express is two separate findings on the *same* tooth treated by a single procedure. In practice those are charted as one finding with combined surfaces, so it does not arise often enough to justify a junction table.

A finding resolves when the clinician confirms it, normally once the last procedure addressing it completes — not on the first, since deep caries is not dealt with until the crown is seated.

### 9. Treatment changes constantly, so decisions are logged, not just state
A doctor opens a tooth, finds a crack, and adjusts the plan. A patient accepts three of five recommendations and refuses the rest. A refusal is reconsidered eight months later. None of that is exceptional — it is the ordinary shape of dentistry, and a schema holding only *current* state loses all of it.

`ProcedureDecision` is an append-only log of every status transition: who decided, when, and why. `TreatmentProcedure.status` becomes a cache of that log's head.

**Informed refusal is why this matters.** A `declinedAt` field records only the latest state, and treatment is routinely re-proposed: a patient who declines a crown on cost in March and accepts in November would overwrite the March refusal. That refusal is exactly the record the clinic needs if the tooth had instead fractured. `Declined` alone is a status; `Declined` with a dated reason and `riskExplained` is a defence.

With what already exists, this closes a complete and defensible chain:

| Question | Answered by | Kept how |
|----------|-------------|----------|
| What did we find? | `ToothCondition` | append-only; errors marked `EnteredInError` |
| What did we recommend, and what was decided? | `ProcedureDecision` | append-only |
| What did we actually do, and who did it? | `ProcedureSession` | `progressNote`, `performedBy`, `assistantId` |
| What did it cost? | `InvoiceLine` | frozen at issue |

Nothing in that chain is mutable — which is what makes it worth having when a dispute arrives years later.

### 10. The tooth is a dimension, not a note
Dentistry happens to a specific tooth, and usually to specific surfaces of it. `ProcedureTooth` records which teeth and surfaces each procedure addresses; `ToothCondition` records what was found on a tooth and whether it has been dealt with.

The alternative — a tooth number written into `doctorNote` — fails the moment anyone needs to *use* it. Free text cannot be counted for billing, drawn on a chart, filtered for recall, or audited. It is also what the earlier seed data quietly did (`'Atraumatic extraction #46'`), which is exactly the smell this entity removes.

`ProcedureTooth` is a junction rather than a column because the relationship is many-to-many in both directions: a three-unit bridge covers three teeth (two `Abutment`, one `Pontic`), full-mouth scaling covers all of them, and a single molar accumulates a filling, then a crown, then an extraction over a decade.

### 11. FDI notation, with the patient's left and right
Codes are FDI / ISO 3950: quadrant digit then position digit, `11`–`48` for the 32 permanent teeth and `51`–`85` for the 20 primary ones. Primary teeth are not optional — the clinic treats children, and a seven-year-old is in mixed dentition.

`Tooth` is a static 52-row reference table rather than a bare `CHECK` constraint, because those rows carry information the rest of the system needs: `validSurfaces` (`MIDBL` anterior, `MODBL` posterior) validates a filling, `isAnterior` drives clinical and pricing rules, and `name`/`nameVi` let the record read as words. `universalCode` cross-references US 1–32 numbering for imaging software that speaks Universal rather than FDI.

Side is always the **patient's** left and right, never the viewer's. It is the most common charting error, so it is stated on the entity itself.

### 12. Tooth-level work changes how an invoice is calculated
`ServiceCategory` gains `toothScope` (how many teeth a service applies to — validation) and `pricingBasis` (what the unit price is charged per — billing). They are independent: a full-mouth scaling can still be priced per quadrant.

`Invoice.subtotal` was "the sum of procedure prices". With tooth-level work it becomes the sum of *unit price × billable quantity*, where quantity follows `pricingBasis` — `1` for PerProcedure, the `ProcedureTooth` count for PerTooth, the total surface count for PerSurface, the distinct quadrant count for PerQuadrant.

A two-surface filling and a three-surface filling are different money. Without this, either the schema cannot express the difference or someone types the right number into a free-text field and nothing can check it.

### 13. The session is the unit of work, and the unit of payment
A procedure is a clinical step; a **session** is one visit's worth of it. Root canals, crowns and orthodontic courses all take several visits, and the clinic is paid as each one completes — so money is recognised per session, never per procedure.

`ProcedureSession` replaces the former `TreatmentProgress`, which already described itself as "what happened during a procedure session". It now carries the session's identity, staff and money as well as its notes.

**Every procedure has at least one session, even a single-visit filling.** That is what keeps the billing rule free of special cases: *one completed session, one invoice line.* The alternative — billing whole procedures except when they are multi-visit — is two rules that will drift apart.

Sessions also fix a modelling error. `Appointment.treatmentProcedureId` was a single FK, so a visit could only ever record one procedure — yet a filling and a scale in the same chair is an ordinary afternoon. The link is now inverted: an appointment has many sessions, each pointing at its own procedure.

And because a session carries its own `performedBy` and `assistantId`, a procedure delivered over three visits by two different doctors and two different assistants attributes each visit to whoever was actually there. Commission follows the same granularity for the same reason: **only the people who did the work are paid.** `TreatmentPlan.doctorId` owns the case but earns nothing — they may not have been in the room.

### 14. Failed work is a case with three linked consequences, not a refund button
A veneer cracks two days after fitting. The clinic refunds — but only where the fault was its own, and when it does, the loss is charged back to whoever did the work. That is one event with three consequences, and they have to stay linked or the audit falls apart.

`TreatmentFailure` is the case file: what the patient reported, what the clinician found, what the manager determined and **why**. `faultAttribution` is the gate on refunding, and it is a recorded human judgment, never an automatic rule:

| Attribution | Typical remedy | Staff charged? |
|-------------|----------------|----------------|
| ClinicTechnique | Refund, FreeRework, or Both | **yes** |
| MaterialDefect | Refund or FreeRework | no — pursue the vendor |
| PatientFactor | None; new work charged normally | no |
| Inconclusive | manager's discretion | manager's discretion |

**No new money machinery was needed.** Three mechanisms already in the design carry it:

| Step | Recorded as |
|------|-------------|
| Cancel the charge | `InvoiceLine` with negative `lineTotal`, naming what it reverses in `creditsLineId` |
| Return the money | `Payment` with `direction = Out` |
| Redo it free | `TreatmentProcedure.remedyForFailureId` — non-billable |
| Charge the staff | `PayrollAdjustment` Debit with `relatedFailureId` |

Refunding by credit line rather than by editing the invoice is the same rule that already governs settled payroll and clinical findings: **corrections are new rows, never edits.** The invoice ends balanced at zero with both the charge and its reversal visible, which is what an auditor or a court would ask to see.

**Free rework earns no commission, and no rule was needed to make that true.** Commission derives from a session's `billableAmount`; a remedy procedure bills nothing, so the entry is zero by arithmetic. The `PayrollAdjustment` debit is separate and recovers the clinic's *real* loss, which routinely exceeds the refund once a lab remake and the free chair time are counted.

**The failed procedure keeps `status = Completed`.** It was completed; it later failed. Rewriting its status would falsify exactly the history this record exists to preserve — and `ProcedureSession.performedBy` on each visit is what lets a manager see who did the work rather than guess.

`ServiceCategory.warrantyDays` flags whether a claim arrived inside the window. It is advisory: it informs the judgment, it does not make it.

### 15. An estimate is computed; an invoice is issued
At proposal time everything needed to price the plan is already known — the procedures, their materials, their teeth. So the clinic can and should show the patient a total. **That total is a computation, not a record.**

It is not stored as an `Invoice`, and the reason is staleness rather than law. A `Draft` invoice takes no legal number, so creating one early would be harmless in itself. But two rules the clinic set make a stored figure wrong almost immediately:

- **Prices move.** A rise means the patient pays the new price, so a March quote does not survive to a November acceptance.
- **Patients accept a subset.** `Proposed → Accepted / Declined` runs per procedure; someone taking three of five procedures invalidates a stored five-procedure invoice the moment they decide.

A stored early invoice is therefore a cached copy of a number that can always be derived, carrying a way to be wrong that the derivation does not have. An invoice appears when there is something real to bill: at acceptance under `Upfront`, or as sessions complete under `PerSession`.

This is also why `unitPrice` is null while `Proposed`. Storing it would imply a guarantee. Null encodes *estimate, not commitment*; acceptance turns it into a commitment and locks it.

**What was quoted still belongs in the record.** An estimate that is displayed and forgotten cannot answer "you told me thirty million" — the dispute this design logs everything else to answer. `ProcedureDecision.quotedAmount` captures the figure at the moment it was given, so a March quote and a November acceptance at a different price are both visible, in order, with who said what. It proves what was said without binding the clinic to a price that has since moved.

### 16. Pay-before-treatment needed no new entities, but moved when the price is set
The clinic's real sequence is: exam, proposal, patient accepts, **patient pays**, then the doctor works. `TreatmentPlan.paymentMode = Upfront` already described that, and commission already fired on session completion rather than on payment — so the flow itself fitted the design unchanged.

It did expose one genuine contradiction. `unitPrice` resolved "when the first session completes", while an Upfront invoice line is created **at acceptance** — before any session exists. The clinic would have been invoicing a price that had not been calculated yet.

`unitPrice` now resolves **at acceptance**. That is the moment the patient agrees to a figure, and the earliest point the clinic may need to bill it. A `Proposed` procedure carries no price at all: it is quoted at the price current when presented, and a patient who deliberates for six months accepts whatever the price is then.

**Commission follows the work, never the money.** An entry is created when a session completes, whether the patient paid up front, pays later, or never pays. `ProcedureSession.billableAmount` is the *value of that session's work* — under `PerSession` it becomes an invoice line as the session completes, and under `Upfront` the money was collected at acceptance but the figure still stands, because it is what commission is computed from.

That separation gives the right answer to the awkward case: a patient who prepays a whole plan then abandons it after one visit leaves the clinic holding the money and exactly one session credited to staff. Neither number is wrong, and no special rule was needed to get there.

Prepayment followed by cancellation needs no new machinery either — the undone procedures are credited off with negative `InvoiceLine` rows and returned as a `Payment` with `direction = Out`, the same path a failed-treatment refund takes.

### 17. Two payment modes, one mechanism
`TreatmentPlan.paymentMode` records what was agreed: **Upfront** or **PerSession**. Both produce `InvoiceLine` rows — only the trigger and the reference differ.

| Mode | Line references | Created when | Line total |
|------|-----------------|--------------|------------|
| PerSession | `sessionId` | each session completes | that session's `billableAmount` |
| Upfront | `procedureId` | the patient accepts | the procedure's full total |

A procedure's total is split across its sessions by `billableAmount`, summing to the whole. An even split is the default; a doctor may weight it, since an implant is commonly 60% at fixture placement and 40% at the crown.

This is also why `Invoice` is no longer 1:1 with `TreatmentPlan`. A twenty-month orthodontic course cannot sit on one invoice carried for two years while the patient pays per visit. The plan is a clinical container; the invoice is a financial document, and they need not line up.

### 18. A discount is agreed on the invoice but must be allocated to its lines
`Promotion` is now a **voucher code**: the manager creates `XASH` at 10%, sets a window, and a patient presents it at billing. It comes off the whole invoice. The earlier per-category scoping is gone — it added configuration for a case the clinic does not have.

That simplification creates one obligation. VAT is charged **per line** and the rates differ, because dental treatment and cosmetic work are not taxed alike. So an invoice-level discount has to be **allocated across the lines pro-rata by value before VAT is computed**:

| Line | Gross | Allocated discount | Net | VAT rate | VAT |
|------|-------|--------------------|-----|----------|-----|
| Composite filling | 1,000,000 | 100,000 | 900,000 | 0% | 0 |
| Teeth whitening | 2,000,000 | 200,000 | 1,800,000 | 10% | 180,000 |
| **Invoice** | **3,000,000** | **300,000** | **2,700,000** | | **180,000** |

Computing VAT before the discount charges 200,000 instead of 180,000 and bills 2,900,000 instead of 2,880,000 — **a 20,000 overcharge on one visit**, growing with every mixed-rate invoice, and misstating the tax the clinic owes. It was a real defect in this design until now: `vatAmount` was `lineTotal × vatRate` while `discountAmount` only reduced the subtotal afterwards.

`InvoiceLine.discountAmount` holds each line's share, and `vatAmount` is computed on `lineTotal − discountAmount`. Shares are rounded down to whole đồng with the last line absorbing the remainder, so they sum to the invoice discount exactly — VND has no minor unit, so the rounding has to land somewhere deliberate.

At most one discount source applies per invoice: a voucher code **or** an approved `DiscountProposal`, never both. Stacking is a business decision the clinic has not asked for, and forbidding it keeps the allocation unambiguous.

### 19. VAT is per service, and invoice numbers are legally sequential
`ServiceCategory.vatRate` sits on the **service**, not the clinic, because Vietnamese VAT does not treat all dentistry alike — medical treatment and cosmetic work are handled differently, so a filling and a whitening may not carry the same rate. The design records a rate per service and leaves the actual figures to be confirmed with the clinic's accountant.

`InvoiceLine` snapshots both `vatRate` and `vatAmount` alongside the price, for the same reason every other field there is frozen: the bill must not move when the catalogue changes. A credit line carries negative VAT, so refunding a failed veneer reverses the tax with the charge.

Legal numbering has strict rules, and they are strict on purpose:

- A number is assigned **when the invoice is issued**, never while it is `Draft` — a draft is not yet an invoice.
- Numbers are **never reused**. A `Voided` invoice keeps its number; the gap it would otherwise leave is exactly what sequential numbering exists to prevent.
- Once issued, the serial and number are immutable. Corrections are credit lines or new invoices.

`taxAuthorityCode` is a hook for e-invoice registration, which Vietnam now mandates. The integration itself is a separate concern.

### 20. `InvoiceLine` freezes the bill away from the clinical record
`Invoice` previously held only a subtotal — no itemisation, and nothing connecting money back to a tooth. `InvoiceLine` adds both, and every descriptive field on it is a **snapshot**.

That is not belt-and-braces. Clinical records get amended — `ToothCondition` carries `EnteredInError` precisely because corrections happen. If an invoice were a live view over procedures, correcting a tooth number next month would silently change a bill already issued and paid. Freezing the line decouples the financial record from the clinical one, and `Invoice.subtotal` becomes `SUM(lineTotal)` — derivable and auditable rather than asserted.

Only a **Completed** session, or an **Accepted** procedure paid up front, may produce a line. A `Declined` procedure can never leak into a total.

### 21. Material changes the price, not the service
A crown is one clinical service, but zirconia and porcelain-fused-metal are not the same money — and the patient chooses. `MaterialOption` hangs variants off a `ServiceCategory`, and `PriceList` gains a nullable `materialOptionId`: null is the category's base price, a value prices that specific material. Resolution falls back to the base row, so adding a material never requires repricing everything.

Modelling these as separate categories — "Zirconia Crown", "PFM Crown" — would duplicate `isSpecial`, `toothScope`, `pricingBasis`, `resultingConditionType` and the instruction templates, and the catalogue would double again with every new implant brand. Clinical rules belong on the service; commercial choice belongs on the material.

### 22. Patient acceptance and manager approval are different gates
`TreatmentProcedure.status` gains `Proposed`, `Accepted` and `Declined`. A proposal is not a separate entity — it is a procedure that has not happened yet, which is also what makes it draw on the chart as planned work.

Manager approval (`SpecialProcedureProposal`, `DiscountProposal`) is a different question with a different reviewer. Keeping them apart means a doctor can propose work to a patient without a manager in the loop, and the manager still gates the cases that need it.

A price rise applies to procedures accepted after it, never to one already agreed: `unitPrice` resolves once, **at acceptance**, so neither a patient mid-root-canal nor one who paid up front sees the rate move.

### 23. `TreatmentPlan` is the clinical anchor
Everything clinical orbits the treatment plan: procedures, progress logs, notes, discounts, invoicing. A patient may have multiple treatment plans over time (e.g., one for orthodontics, one for implants).

### 24. Procedures are typed by `ServiceCategory`
`ServiceCategory` carries the `isSpecial` flag. Special categories (implant, orthodontic) require a `SpecialProcedureProposal` approved by the manager before the plan is activated. This matches the doctor's approval workflow.

### 25. Pricing is time-versioned
`PriceList` records carry an `effectiveFrom` date so historical invoices remain correct after the manager changes prices.

### 26. Discounts flow through two paths
- **Voucher codes**: a `Promotion` code the patient presents, taken off the invoice total.
- **Doctor-proposed discounts**: `DiscountProposal` linked to a specific `TreatmentPlan`; requires manager approval before being applied to the `Invoice`.

### 27. Expiry belongs to the batch, not the item
`InventoryLog.changeType` has always included `Expired` with nothing in the model able to drive it. The reason is that expiry is not a property of an item at all: ten boxes of composite bought on two dates expire on two dates, and only a batch can say which.

`InventoryBatch` carries `lotNumber`, `expiryDate` and `quantityRemaining`, and consumption picks the **earliest expiry first** — which is what stops usable stock quietly expiring behind newer stock. `InventoryItem.tracksExpiry` decides whether an item needs batches at all: composite and anaesthetic do, a mirror does not.

It also carries `unitCost`. That is what makes cost of goods answerable at all: the same composite bought at two prices is two batches, and a procedure's real material cost depends on which one was opened. Without it, the accountant's cost reporting has no basis to compute from.

### 28. Inventory is dual-purpose
`ProcedureSupplyList` is a template per `ProcedureInstruction` (what supplies are expected). `InventoryLog` records actual consumption or restocking events. Assistants work from both views.

### 29. `Notification` is a first-class entity
Paging between staff (doctor → assistant, manager → all) is tracked as notifications, not just ephemeral pushes. This supports audit and follow-up reminders.

### 30. Pay rates are versioned, never overwritten
`WageRate` holds one row per rate a staff member has ever been on, each with an `effectiveFrom`. A raise or a promotion **inserts** a row; it never edits one. The rate for a day of work is the row with the greatest `effectiveFrom` on or before that day — the same mechanism `PriceList` uses to price a procedure by the date it was performed.

A single `hourlyRate` column on `StaffProfile` could only ever hold the *current* rate. That answers "what do we pay them now" and nothing else:

| Question | Single column | Versioned rows |
|----------|---------------|----------------|
| What is this person paid today? | yes | yes |
| What were they paid last quarter? | **no — overwritten** | yes |
| Can we reproduce an old payslip? | **no** | yes |
| Staff promotion lands mid-period? | **cannot express** | resolves per day |

The last row is the one that forces the design. An intern promoted on the 15th has half a month at the trainee rate and half at the new one; with a single column you must pick one rate for the whole period and both choices are wrong. Because `WageRate` is resolved per `AttendanceLog` day, that case needs no special handling at all.

Settled payroll was never *wrong* under the old shape — `PayrollRecord.basePay` stores the computed figure. But it was not **reproducible**, which is what a labour inspection or a staff dispute actually asks for. `basePay` remains a stored snapshot of what was settled; it is now also derivable from the rate history.

Open decision: for `wageType = Monthly`, a rate change mid-period needs a pro-rating rule — calendar days or working days. `Hourly` needs none.

### 31. Payroll is built from two independent streams
`PayrollRecord.netPay = basePay + commissionTotal − deductions`. Base pay comes from `AttendanceLog` (hours-based) or a fixed monthly rate. Commission comes from `CommissionEntry` records — the same mechanism for every staff role. There is no separate "performance bonus" stream; receptionist KPI bonuses flow through `CommissionEntry` like any other commission.

### 32. `CommissionRule` covers all commissionable roles with a single unified structure
One entity replaces two separate systems. For Doctor/Assistant the rule is scoped by `serviceCategoryId`; for Receptionist it is scoped by `eventType`. A nullable `staffId` field enables individual contract rates that override the role-level defaults. Rules are time-versioned with `effectiveFrom`, and each `CommissionEntry` locks in the rule at the time the event occurred — historical payroll is never retroactively changed.

### 33. `ReceptionistPerformanceLog` is a standalone event log, not a bonus ledger
It is a bridge between `StaffProfile` and `PatientProfile` that records *what happened* (which receptionist brought in which patient). Commission amounts live in `CommissionEntry`, not here. This separation keeps the event record clean and auditable independently of payroll configuration. The manager can see "receptionist A registered 12 new patients this month" separately from "how much did we pay her for that."

### 34. No staff member earns commission on their own treatment
Staff are welcome to be treated at the clinic — the rule is only about who gets paid. A `CommissionEntry` may not be created where the credited staff member resolves to the same `User` as the patient on that procedure's `TreatmentPlan`. It applies to the doctor and the assistant alike.

If Dr. Mai treats Dr. Minh, Dr. Mai earns her commission normally; Dr. Minh earns nothing, because he is the patient. Without this rule, consolidating staff and patients onto one `User` row would quietly let a doctor bill the clinic for treating themselves.

### 35. `CommissionEntry` uses `sourceType` to support two trigger paths
- `ProcedureCompleted`: created when a `TreatmentProcedure` moves to Completed. Two entries are written — one for the doctor, one for the assistant.
- `ReceptionistEvent`: created immediately when a `ReceptionistPerformanceLog` record is written.

In both cases the commission base value (`commissionBase`) is snapshotted at creation time so the manager's payroll review always shows the exact calculation, even if prices or rules change later.

### 36. Commission dashboard is Manager-only
`CommissionRule`, `CommissionEntry`, `PayrollAdjustment`, and the full `PayrollRecord` breakdown are visible only to the Manager role. Staff see only their own net pay on their payslip — not the commission rates, individual commission entries, or adjustment reasons. This is enforced at the API permission layer, not the data model.

### 37. Manual payroll adjustments are immutable once payroll is finalized
`PayrollAdjustment` records in `Pending` status can be edited or deleted by the manager before payroll is approved. Once a payroll is finalized (`status = Approved`), all linked adjustments become `IncludedInPayroll` and are locked. Any subsequent correction requires a new offsetting adjustment in the next payroll period — there is no in-place editing of settled records. This preserves a clean audit trail for disputes or accounting review.

The `direction` field (Credit / Debit) with a mandatory `reason` field means every non-system adjustment is traceable to a manager decision and a written business justification. Typical debit scenarios: patient refund caused by a procedure error (link `relatedInvoiceId`), commission clawback on a cancelled treatment (link `relatedCommissionEntryId`). Typical credit scenarios: discretionary end-of-year bonus, short-notice shift coverage.
