# KPX — Core Entity Definitions

---

## Domain: Identity & Access

### User
A **person record**, not a login. Every human in the system — staff, patient, or someone who has only ever booked online — has exactly one `User` row.

Two facts about a person move independently:

| Fact | Becomes true when | Held by |
|------|-------------------|---------|
| We know who they are | First contact — online booking, phone, or the receptionist's questions | the row exists |
| We have verified them | They arrive and a staff member checks their CCCD | `verifiedAt` / `verifiedBy` |

**Authentication is a third, separate layer and is deliberately not modelled yet** — see *Authentication* below.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| fullName | string | known from first contact; also a patient identifying field |
| phone | string | required — dedup key at booking, and a patient identifying field |
| email | string | unique; nullable — a walk-in may have none |
| dateOfBirth | date | nullable |
| address | string | nullable |
| nationalId | string | unique; nullable — Vietnamese CCCD, exactly 12 digits. Stored as text, never numeric: it is an identifier, not a quantity, and leading zeros are significant |
| status | enum | Provisional, Active, Inactive — the **person's** lifecycle, never their employment |
| verifiedAt | timestamp | nullable — when identity was checked in person |
| verifiedBy | UUID | FK → User; nullable — which staff member checked it |
| role | enum | Manager, Doctor, Receptionist, Accountant, Assistant, Patient |
| createdAt | timestamp | |

**Invariants**
- `status = Active` requires both `verifiedAt` and `verifiedBy` — Active means a person physically verified them.
- `nationalId` is exactly 12 digits when present, and unique across everyone.

**Lifecycle**

| Path | What happens |
|------|--------------|
| Books online | Row created `Provisional`: name, phone, email. No CCCD. **Never logs in** — receives booking confirmation and reminders by phone or email, and contacts the clinic to change anything. |
| Arrives at clinic | Receptionist checks the CCCD, fills `nationalId`, stamps `verifiedAt`/`verifiedBy`, flips to `Active`, creates the `PatientProfile`. |
| No-shows | Stays `Provisional`. The desk chases a reschedule by phone or email. |
| Walks in | Created `Active` in one step, CCCD in hand. Same table, no special case. |

**Authentication** *(credential and OTP storage is out of scope for now)*

There are two portals, and a person reaches them by what they **have**, not by their `role`:

| Portal | Granted when |
|--------|--------------|
| Patient | `User.status = Active` **and** a `PatientProfile` exists |
| Staff | `User.status = Active` **and** a `StaffProfile` exists with `employmentStatus` of **Intern or Active** |

`role` then governs permissions *inside* the staff portal. Patients can never reach the staff portal.

**Patients use no password.** Two routes, both resting on fields already present on this record:

| Route | Uses | Proves |
|-------|------|--------|
| **Phone OTP** | `phone` | *possession* — they hold the handset |
| Identifying fields | `fullName` + `phone` + `nationalId` | *knowledge* — exact combination TBD |

Phone OTP is the stronger of the two and the better default: it does not depend on the CCCD being confidential, and it is the only route that works for a patient who has **neither an email nor a CCCD** — a foreign patient, or a walk-in verified by other means.

- **Staff use a username and password, or a hardware chip.** Mechanism TBD.
- **Provisional people never authenticate**, by either route. They have a `phone`, so an OTP would technically reach them — but issuing one would let an unverified person into the system and bypass the in-person check that `Active` exists to record. Their phone is for booking confirmations and reminders only.

> Deriving portal access from profiles rather than `role` is what lets one person hold both: a doctor who is also a patient reaches both portals, and a **departed** doctor keeps the patient portal while losing the staff one.

> Security note for the sign-in decision: a CCCD is **not a secret** — it appears on documents and is routinely shared with hotels and banks. Phone OTP avoids that problem entirely; if the identifying-fields route is also offered, it is worth deciding consciously how much it should unlock on its own before it gates clinical records.

**Relationships**
- 0–1 → `StaffProfile` (employment, if staff)
- 0–1 → `PatientProfile` (care relationship, created on arrival)
- 1–N → `Appointment` (a Provisional person can hold a booking)
- 1–N → `Notification` (sent or received)

> A person may hold **both** profiles. `role` governs system access; having a `PatientProfile` governs whether they receive care. They are orthogonal — a doctor who is also a patient keeps `role = Doctor` and simply has both.

---

### StaffProfile
Employment data only. Identity lives on `User`.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| userId | UUID | FK → User; unique |
| joinDate | date | |
| employmentStatus | enum | **Intern, Active, OnLeave, Departed** — where they sit in the employment lifecycle |
| endDate | date | nullable; required when `employmentStatus = Departed` |
| specialty | string | nullable; Doctor only (e.g., "Orthodontics") |
| licenseNumber | string | nullable; Doctor only |

> **Pay is not stored here.** `wageType` and `hourlyRate` used to live on this record; they now live on `WageRate`, one row per rate the person has ever been on. A single column could only ever hold the *current* rate, which cannot answer what someone was paid last quarter.

**Employment lifecycle**

| Status | Working? | Assignable to new work? | Staff portal? | Notes |
|--------|----------|------------------------|---------------|-------|
| **Intern** | yes | **yes** | yes | Applied and accepted, in training or on trial. Not full-time. Carries its own wage and commission terms. |
| **Active** | yes | yes | yes | Full employment. |
| **OnLeave** | no | no | no | Maternity, sabbatical, long illness. Not bookable, but not gone. |
| **Departed** | no | no | no | Employment ended. `endDate` required. |

**Invariants**
- `employmentStatus = Departed` requires `endDate`; `endDate` set requires `employmentStatus = Departed`.
- Only `Intern` or `Active` staff may be assigned to **new** appointments, procedures or schedules, and only they reach the staff portal. An intern is working and needs the system to do the job — the distinction from `Active` is terms, not access.
- **Ending employment never changes `User.status`.** The person stays `Active` and keeps any `PatientProfile` they have.

> **Interns are paid on different terms.** A `WageRate` row carries the trainee rate; promotion inserts a second row rather than editing the first, so the intern months keep the intern rate forever. A `CommissionRule` scoped to that `staffId` carries any reduced commission — or none, if interns earn none.

> This separation is the whole point: employment ends on `StaffProfile`, the person continues on `User`. A doctor who quits and remains a patient at the clinic loses the staff portal and keeps the patient portal, with no record surgery and no history rewritten.

**Historical records are never rewritten on departure.** Past `TreatmentPlan`, `Appointment`, `CommissionEntry` and `PayrollRecord` rows keep pointing at the departed staff member — that is what makes last year's reports still correct. Departure is a state change, never a deletion.

**Relationships**
- N–1 → `User`
- 1–N → `PayrollRecord`, `AttendanceLog`, `CommissionEntry`
- 1–N → `DoctorSchedule` (if Doctor)

---

### PatientProfile
The **care relationship**. Created on arrival — never at online-booking time. Its existence is what distinguishes a patient from a provisional booker, and what grants the patient portal. Identity lives on `User`.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| userId | UUID | FK → User; **required and unique** — every patient has a person record |
| emergencyContact | string | nullable |
| referralSource | string | nullable |
| createdBy | UUID | FK → User (receptionist who registered them on arrival) |
| createdAt | timestamp | |

**Relationships**
- N–1 → `User`
- 1–1 → `HealthRecord`
- 1–N → `TreatmentPlan`, `PatientMedia`
- 1–N → `ToothCondition` — the patient's odontogram is their `Active` conditions

> A `TreatmentPlan` and an `Invoice` reference `PatientProfile`, not `User`: you cannot carry a treatment plan or an invoice until you have arrived and become a patient. Only `Appointment` accepts a provisional person.

> A staff member may hold a `PatientProfile` and receive care at their own clinic. When they do, no one earns commission on their treatment — see `CommissionEntry`.

---

## Domain: Scheduling

### ChairType
What a chair is equipped to do. A handful of static rows the clinic defines once.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| name | string | "Standard", "Surgical", "Orthodontic", "Imaging", "Paediatric" |
| description | text | what distinguishes it — sterile field, CBCT unit, scanner |
| isActive | bool | |
| displayOrder | int | |

**Relationships**
- 1–N → `Chair`
- 1–N → `ServiceCategory.requiredChairTypeId`

---

### Chair
A physical treatment position. **Chairs, not doctors, are what actually cap the clinic's throughput** — two dentists cannot both work if there is one chair.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| code | string | "Ghế 1", "Room 2 — Surgery" |
| chairTypeId | UUID | FK → ChairType |
| status | enum | **Available, Maintenance, Retired** |
| notes | text | |
| displayOrder | int | ordering on the day sheet |

**Invariants**
- **No two appointments may occupy the same chair at overlapping times.** This is the constraint the entity exists for; without it nothing in the model stops two 09:00 bookings landing in one chair. In PostgreSQL this is an exclusion constraint on (`chairId`, time range); in SQLite it has to be enforced in the application.
- Only `Available` chairs may be booked. `Maintenance` covers a unit down for repair — not bookable, not gone.
- A chair may only host an appointment whose procedures allow its type — see `ServiceCategory.requiredChairTypeId`.

> **Booking needs three things to line up:** the doctor is free (`DoctorSchedule`), the chair is free (this entity), and the clinic is open. The third is not yet modelled — there is no clinic-hours entity — which is worth closing before the booking screen is built.

> `Appointment.chairId` is nullable so a chair can be assigned on the day rather than at booking. That flexibility has a cost: an appointment with no chair consumes no capacity, so a booking flow that leaves it null can overbook the clinic. Assigning at booking time is the safer default.

**Relationships**
- N–1 → `ChairType`
- 1–N → `Appointment`

---

### DoctorSchedule
Defines a doctor's working availability in recurring or one-off blocks.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| doctorId | UUID | FK → StaffProfile |
| dayOfWeek | int | 0–6; nullable if date is set |
| date | date | nullable; for one-off overrides |
| startTime | time | |
| endTime | time | |
| isAvailable | bool | false = blocked/holiday |

**Relationships**
- Used by Receptionist to determine open slots when creating `Appointment`.

---

### Appointment
A scheduled visit linking a patient to a doctor at a specific time.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| personId | UUID | FK → **User** — not PatientProfile, so a Provisional person can hold a booking made before they ever arrived |
| doctorId | UUID | FK → StaffProfile |
| chairId | UUID | FK → Chair; nullable — the physical position this visit occupies. Nullable so it can be assigned on the day, but leaving it null means the visit consumes no capacity |
| scheduledAt | timestamp | |
| durationMinutes | int | default 30 |
| type | enum | Consultation, Procedure, Followup |
| status | enum | Scheduled, Confirmed, InProgress, Completed, Cancelled, NoShow |
| bookingChannel | enum | Online, FrontDesk, Phone — Online bookings are the ones that create Provisional people and need the no-show chase |
| assistantId | UUID | FK → StaffProfile; nullable — assistant assigned to this visit |
| followedUpBy | UUID | FK → User (Receptionist); nullable — receptionist whose follow-up contact led to this booking |
| notes | text | receptionist or doctor notes |
| createdBy | UUID | FK → User; nullable — null means the patient self-booked online |
| createdAt | timestamp | |

**Relationships**
- N–1 → `User` (the person the appointment is with)
- N–1 → `StaffProfile` (doctor)
- 1–N → `ProcedureSession` — **what was actually done at this visit**, one row per procedure worked on
- N–1 → `StaffProfile` (assistant, optional)
- 1–N → `Notification` (reminders)

> A visit routinely covers more than one procedure — a filling and a scale in the same chair — so the work done is a list of `ProcedureSession` rows, not a single foreign key on the appointment. All of those sessions share the appointment's chair, which is why the chair sits here rather than on the session.

> **Two appointments may never overlap in the same chair.** That constraint is the whole reason `Chair` exists, and it cannot be expressed without it.

> `followedUpBy` is the key field for receptionist follow-up KPI: a completed `Followup`-type appointment with `followedUpBy` set counts as a successful returning-patient acquisition for that receptionist.

---

## Domain: Clinical

### HealthRecord
Medical history and baseline health data for a patient.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| patientId | UUID | FK → PatientProfile; unique |
| bloodType | string | nullable |
| allergies | text | |
| currentMedications | text | |
| medicalConditions | text | (diabetes, hypertension, etc.) |
| dentalHistory | text | prior treatments elsewhere |
| lastUpdatedBy | UUID | FK → User |
| lastUpdatedAt | timestamp | |

---

### PatientMedia
Imaging and photographs associated with a patient.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| patientId | UUID | FK → PatientProfile |
| type | enum | Xray, CBCT, Photograph, Other |
| stage | enum | Before, During, After; nullable |
| fileUrl | string | storage reference |
| takenAt | date | |
| uploadedBy | UUID | FK → User |
| procedureId | UUID | FK → TreatmentProcedure; nullable |
| notes | text | |

---

### TreatmentPlan
The top-level clinical record for a course of treatment.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| patientId | UUID | FK → PatientProfile — a plan requires an arrived, verified patient |
| doctorId | UUID | FK → StaffProfile — the doctor **responsible for the case**. Ownership only: this earns nothing. Commission follows whoever actually worked each session |
| title | string | e.g., "Lower implant — Q3 2026" |
| status | enum | Draft, PendingApproval, Active, Completed, Cancelled |
| isSpecial | bool | derived from procedures; if true, requires SpecialProcedureProposal approval |
| paymentMode | enum | **Upfront, PerSession** — what was agreed with the patient. Upfront bills accepted procedures in advance; PerSession bills each completed session as it happens |
| startDate | date | nullable |
| estimatedEndDate | date | nullable |
| notes | text | |
| createdAt | timestamp | |
| updatedAt | timestamp | |

**Relationships**
- 1–N → `TreatmentProcedure`
- 0–1 → `SpecialProcedureProposal`
- 0–1 → `DiscountProposal`
- 0–1 → `Invoice`

---

### TreatmentProcedure
One clinically distinct step within a plan — a filling, an extraction, a crown. A procedure may take **several sessions** to deliver, and the clinic is paid per session, not per procedure.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| treatmentPlanId | UUID | FK → TreatmentPlan |
| serviceCategoryId | UUID | FK → ServiceCategory |
| materialOptionId | UUID | FK → MaterialOption; nullable — **required** when the category sets `requiresMaterialChoice`. This is the patient's choice, and it changes the price |
| instructionSetId | UUID | FK → ProcedureInstruction; nullable |
| sequence | int | order within the plan |
| status | enum | Proposed, Accepted, Declined, Scheduled, InProgress, Completed, Skipped |
| plannedSessions | int | default 1 — how many visits this is expected to take |
| remedyForFailureId | UUID | FK → TreatmentFailure; nullable — **when set this is free rework**: it produces no invoice line, and therefore no commission |
| unitPrice | decimal | nullable until work starts — resolved from `PriceList` when the **first session completes**, then held for the life of the procedure |
| doctorNote | text | instructions for the next session |
| completedDate | date | nullable — set when the final session completes |

**Status lifecycle**

```
Proposed ──► Accepted ──► Scheduled ──► InProgress ──► Completed
    │
    └──────► Declined
```

| Status | Meaning |
|--------|---------|
| Proposed | The doctor recommended it; the patient has not decided. Draws on the chart as planned work. |
| Accepted | The patient agreed. Now schedulable and billable. |
| Declined | The patient said no. **Never produces an invoice line.** |
| Scheduled · InProgress · Completed | Being delivered — see `ProcedureSession` |
| Skipped | Clinically no longer needed, e.g. the tooth was extracted so the planned filling is moot |

> Patient acceptance and manager approval are **different gates**. Acceptance lives here on `status`; manager approval for special or discounted work lives on `SpecialProcedureProposal` and `DiscountProposal`.

**Invariants**
- A procedure with `remedyForFailureId` set is **non-billable**: no `InvoiceLine`, and commission falls out at zero because it is computed from a session's `billableAmount`.
- `unitPrice` is resolved **once**, at the first completed session, and never re-resolved. A price rise applies to new procedures, not to one already under way — a patient mid-root-canal should not see the rate move between visits.
- `materialOptionId` must belong to this procedure's `serviceCategoryId`.
- Only an `Accepted` procedure may be scheduled or started.
- `Completed` requires every one of its sessions to be Completed.
- Staff and dates are **not** here — they live on `ProcedureSession`, because different sessions can be worked by different assistants.

**Relationships**
- 1–N → `ProcedureDecision` (how it reached its current status, and why)
- 1–N → `ProcedureSession` (the visits that deliver it, and the unit of billing)
- 1–N → `ProcedureTooth`
- 1–N → `ProcedureSupplyList`
- 1–N → `ToothCondition.observedDuringProcedureId` (findings charted during this visit)
- N–1 → `MaterialOption` (optional)

> The tooth a procedure treats lives in `ProcedureTooth`, never in `doctorNote`. Free-text "#46" cannot be counted, priced, charted or audited.

---

### ProcedureDecision
An append-only log of every status change a procedure passes through — who decided, when, and why. This is the clinic's defensive record. It answers, years later: *what did we recommend, what did the patient agree to, and what did they refuse?*

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| procedureId | UUID | FK → TreatmentProcedure |
| fromStatus | enum | nullable — null on the first entry, when the procedure is created |
| toStatus | enum | the status moved to |
| decidedBy | UUID | FK → User — the staff member who **recorded** it |
| decidedAt | timestamp | |
| reason | text | **required** for `Declined` and `Skipped` |
| riskExplained | bool | nullable — on a refusal, whether the consequence was explained to the patient |
| note | text | |

Whose decision it was is carried by `toStatus`: `Accepted` and `Declined` are the **patient's**, recorded by staff; `Skipped` and `Scheduled` are clinical or operational.

**Why a log rather than timestamps on the procedure.** A `declinedAt` field records only the most recent state, and treatment is routinely re-proposed. A patient declines a crown on cost grounds in March and accepts it in November after the tooth chips — with a timestamp field, that first refusal is overwritten. It is also precisely the record the clinic would want if the tooth had instead fractured. The log keeps every cycle.

**Informed refusal is the point.** A documented refusal — dated, with a reason, with `riskExplained` set — is the clinic's answer when a patient later asks why a problem was not dealt with. `Declined` without a reason is a status; `Declined` with a reason and an explained risk is a defence.

**Invariants**
- Append-only. Never edited, never deleted.
- A procedure's current `status` equals the `toStatus` of its most recent decision — the field on `TreatmentProcedure` is a cache of this log's head.
- `Declined` and `Skipped` require a `reason`.

**Relationships**
- N–1 → `TreatmentProcedure`, `User`

---

### TreatmentFailure
A patient reports that completed work has failed — a veneer cracks two days after fitting. This record carries the claim, the clinic's determination of fault, the remedy, and the link to whatever the responsible staff are charged. It is what makes a refund possible, deliberate and traceable.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| procedureId | UUID | FK → TreatmentProcedure — the completed work that failed |
| toothCode | string | FK → Tooth; nullable — which tooth, when the procedure covered several |
| reportedAt | timestamp | |
| patientAccount | text | what the patient says happened, in their words |
| clinicalFinding | text | what the examining clinician found |
| examinedBy | UUID | FK → User |
| status | enum | Reported, UnderReview, Resolved, Rejected |
| faultAttribution | enum | nullable until determined — **ClinicTechnique, MaterialDefect, PatientFactor, Inconclusive** |
| remedy | enum | nullable until determined — **Refund, FreeRework, Both, None** |
| determinedBy | UUID | FK → User (Manager); nullable |
| determinedAt | timestamp | nullable |
| determinationNote | text | nullable — **why** this attribution was reached |

**The clinic refunds when the fault is its own.** `faultAttribution` is the gate, and it is a human judgment recorded with its reasoning, never an automatic rule:

| Attribution | Typical remedy | Staff charged? |
|-------------|----------------|----------------|
| ClinicTechnique | Refund, FreeRework, or Both | **yes** — see below |
| MaterialDefect | Refund or FreeRework | no — pursue the vendor instead |
| PatientFactor | None; new work is charged normally | no |
| Inconclusive | manager's discretion | manager's discretion |

**How the money actually moves.** Three existing mechanisms carry it, so nothing new is needed to move a single đồng:

| Step | Recorded as |
|------|-------------|
| Cancel the charge | an `InvoiceLine` with a **negative** `lineTotal`, its `creditsLineId` naming the line it reverses |
| Return the money | a `Payment` with `direction = Out` |
| Redo the work free | a new `TreatmentProcedure` with `remedyForFailureId` set — it produces no invoice line |
| Charge the responsible staff | a `PayrollAdjustment` with `direction = Debit` and `relatedFailureId` set |

> **Free rework earns no commission, and needs no rule to make that true.** Commission is computed from a session's `billableAmount`, and a remedy procedure bills nothing — so the entry is zero by arithmetic. The separate `PayrollAdjustment` debit is what recovers the clinic's actual loss, which may exceed the refund once a lab remake is paid for.

> **Who is charged, and how much, is the manager's call.** The design records the decision and its reasoning; it does not compute it. A procedure delivered across sessions by different staff has a `performedBy` on each, so the manager can see who did the work that failed rather than guessing.

**Invariants**
- `status = Resolved` requires `faultAttribution`, `remedy`, `determinedBy` and `determinedAt`.
- `remedy` including Refund requires a credit line and an outbound payment; including FreeRework requires a procedure pointing back with `remedyForFailureId`.
- Once `Resolved`, the record is immutable. A reversal is a new `PayrollAdjustment`, never an edit — the same rule that governs settled payroll.
- The failed procedure keeps `status = Completed`. It *was* completed; it later failed. Rewriting its status would falsify the history this record exists to preserve.

**Relationships**
- N–1 → `TreatmentProcedure` (the failed work), `Tooth`, `User`
- 1–N → `TreatmentProcedure.remedyForFailureId` (free rework)
- 1–N → `PayrollAdjustment.relatedFailureId` (staff consequence)

---

### ProcedureInstruction
Reusable instruction templates that a doctor can define per procedure type.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| createdBy | UUID | FK → StaffProfile (Doctor) |
| serviceCategoryId | UUID | FK → ServiceCategory |
| title | string | |
| instructions | text | step-by-step clinical instructions |
| suppliesRequired | text | free-text or linked to ProcedureSupplyList template |
| version | int | for tracking edits |
| updatedAt | timestamp | |

---

### ProcedureSession
One visit's worth of work on a procedure — **and the unit at which the clinic gets paid.** This replaces the former `TreatmentProgress`, which already described itself as "what happened during a procedure session"; it now carries the session's identity, staff and money alongside its clinical notes.

Every procedure has at least one session, even a single-visit filling. That keeps one billing rule with no special cases: **one completed session, one invoice line.**

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| procedureId | UUID | FK → TreatmentProcedure |
| sessionNumber | int | 1, 2, 3 … within the procedure |
| appointmentId | UUID | FK → Appointment; nullable — the visit it happened at |
| status | enum | Scheduled, Completed, Cancelled |
| performedBy | UUID | FK → StaffProfile — the doctor for **this** session |
| assistantId | UUID | FK → StaffProfile; nullable — the assistant for **this** session |
| billableAmount | decimal | the portion of the procedure's total falling due after this session |
| completedAt | timestamp | nullable |
| progressNote | text | what was done |
| vitals | json | pulse, blood pressure, …; nullable |
| nextStepNote | text | instructions for the next session |

**Invariants**
- `sessionNumber` is unique within a procedure.
- The sum of `billableAmount` across a procedure's sessions equals the procedure total (`unitPrice` × billable quantity). An even split is the default; a doctor may weight it — an implant is commonly 60% at fixture placement and 40% at the crown.
- `status = Completed` requires `completedAt` and `performedBy`.
- A session may only be completed on an `Accepted` procedure.

> **Why sessions rather than the appointment itself.** A single visit often covers more than one procedure — a filling and a scale in the same chair. Hanging work off `Appointment` with one FK could only ever record one of them. Sessions invert the link: an appointment has many sessions, each pointing at its own procedure, so "what happened at this visit" is a list rather than a single value.

**Relationships**
- N–1 → `TreatmentProcedure`, `Appointment`, `StaffProfile` (performer and assistant)
- 0–1 → `InvoiceLine` (created when the session completes)
- 1–N → `CommissionEntry` (one for the doctor, one for the assistant on this session)

---

## Domain: Dental Charting

The odontogram. Everything clinical in a dental practice happens *to a specific tooth*, and often to specific *surfaces* of it — so the tooth is a first-class dimension, not a note.

---

### Tooth
Static reference data: the FDI two-digit notation (ISO 3950). **52 rows, seeded once, never edited by users.**

FDI reads as `quadrant · position`:

| First digit — quadrant | | Second digit — position from the midline |
|---|---|---|
| `1` upper right, `2` upper left | *permanent* | `1` central incisor · `2` lateral incisor · `3` canine |
| `3` lower left, `4` lower right | | `4` first premolar · `5` second premolar |
| `5` upper right, `6` upper left | *primary* | `6` first molar · `7` second molar · `8` third molar |
| `7` lower left, `8` lower right | | *(primary teeth stop at position 5)* |

So `46` is the lower-right first molar; `11` is the upper-right central incisor; `51` is a child's upper-right primary central incisor. Left and right are always the **patient's**, not the viewer's — the single most common charting error.

| Field | Type | Notes |
|-------|------|-------|
| code | string | PK — the FDI code itself: `11`–`18`, `21`–`28`, `31`–`38`, `41`–`48` (permanent), `51`–`55`, `61`–`65`, `71`–`75`, `81`–`85` (primary) |
| quadrant | int | 1–8, the first digit |
| position | int | 1–8 permanent, 1–5 primary — the second digit |
| dentition | enum | Permanent (32 teeth), Primary (20 teeth) |
| arch | enum | Upper, Lower |
| side | enum | Right, Left — **the patient's** |
| toothType | enum | Incisor, Canine, Premolar, Molar |
| isAnterior | bool | positions 1–3; decides whether the biting surface is incisal or occlusal |
| validSurfaces | string | the surfaces that physically exist on this tooth — `MIDBL` anterior, `MODBL` posterior |
| name | string | "Lower right first molar" |
| nameVi | string | Vietnamese name, for patient-facing display |
| universalCode | string | nullable — US 1–32 / A–T cross-reference, for imaging and CBCT software that speaks Universal rather than FDI |

**Surfaces.** Five per tooth, and which five depends on where the tooth sits:

| Code | Surface | Present on |
|------|---------|-----------|
| `M` | Mesial — toward the midline | all |
| `D` | Distal — away from the midline | all |
| `B` | Buccal / labial — toward cheek or lip | all |
| `L` | Lingual / palatal — toward tongue or palate | all |
| `O` | Occlusal — the chewing surface | posterior only (positions 4–8) |
| `I` | Incisal — the biting edge | anterior only (positions 1–3) |

`O` and `I` are mutually exclusive, which is why every tooth has exactly five. Surface sets are written in canonical order **M · O/I · D · B · L**, so a three-surface filling is `MOD` and never `DOM` — one spelling per set, so it can be compared and counted.

> Why a table and not just a `CHECK` on a code column: the chart UI is data-driven from these rows, `validSurfaces` is what validates a filling, `isAnterior` drives clinical and pricing rules, and `name`/`nameVi` mean the patient-facing record reads as words rather than digits.

**Relationships**
- 1–N → `ToothCondition`
- 1–N → `ProcedureTooth`

---

### ToothCondition
A clinical finding on one tooth for one patient: what the dentist observed, when, and whether it has been dealt with. Together, the `Active` rows for a patient **are** their odontogram.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| patientId | UUID | FK → PatientProfile |
| toothCode | string | FK → Tooth |
| surfaces | string | nullable — canonical-ordered subset of that tooth's `validSurfaces`; null for whole-tooth findings |
| conditionType | enum | see the table below |
| status | enum | Active, Monitoring, Resolved, EnteredInError |
| severity | enum | nullable — Mild, Moderate, Severe |
| note | text | |
| observedDuringProcedureId | UUID | FK → TreatmentProcedure; nullable — the visit these findings were charted at, usually a Consultation. Groups a whole exam without needing an examination entity |
| observedBy | UUID | FK → User (the clinician who charted it) |
| observedAt | timestamp | |
| resolvedAt | timestamp | nullable |

**`conditionType` values**, grouped by what they describe:

| Group | Values |
|-------|--------|
| Pathology | Caries, Fracture, Attrition, Erosion, Abrasion, Abscess, Mobility, Sensitivity, Discolouration |
| Existing restoration | Filling, Crown, Veneer, BridgeAbutment, BridgePontic, Implant, RootCanalTreated, Denture |
| Absence & eruption | Missing, Unerupted, Impacted, Supernumerary |

Pathology and restorations sit in one enum deliberately: a dentist charting a mouth records "decay on 46 occlusal" and "existing crown on 24" in the same pass, and the odontogram draws them together.

**Invariants**
- `surfaces` must be a subset of that tooth's `validSurfaces` — an `O` on an incisor is nonsense and should be rejected.
- Whole-tooth findings (`Missing`, `Unerupted`, `Impacted`, `Implant`, `Crown`, `Denture`) carry `surfaces = null`.
- `status = Resolved` requires `resolvedAt`. Resolution is confirmed by the clinician, and normally follows the last procedure addressing it reaching Completed.
- **Rows are append-only.** A finding recorded in error is marked `EnteredInError`, never deleted or edited — a clinical record has to show what was believed at the time, and by whom.

> **A finding links to treatment through `ProcedureTooth.addressesConditionId`, not a field here.** That inversion is what allows *one finding to need several procedures* — deep caries on 46 requiring a root canal and then a crown is two procedures, each with a `ProcedureTooth` row on 46 pointing at the same finding. It also still allows one procedure to resolve many findings: a full-mouth scaling has a `ProcedureTooth` row per tooth, each addressing that tooth's calculus. The relationship is many-to-many in both directions, with no extra junction table, because `ProcedureTooth` already *is* the (procedure × tooth) junction and a finding is tooth-scoped.

**What may write to the record**

A proposal is a *drawing*, not a fact. The chart shows three layers, and only one of them is the patient's actual dental health:

| Layer | Source | Is it the record? |
|-------|--------|-------------------|
| Existing state | `ToothCondition` rows, status Active | **yes** — the patient's real dental health |
| Findings to treat | `ToothCondition` rows, pathology types, status Active | **yes** |
| Planned work | `ProcedureTooth` on procedures with status Proposed / Accepted / Scheduled | **no** — an overlay for the doctor to read |

**Proposing treatment never changes the record.** A doctor can plan a crown on 24 and have it render on the chart, and the tooth's condition is untouched until the work is actually done. Two writes follow from real work, and they fire at different moments:

| Write | Fires when | Why then |
|-------|-----------|----------|
| A finding is **charted** | any session, at any time | a clinician who spots new caries mid-treatment records it immediately |
| The **resulting condition** from `ServiceCategory.resultingConditionType` | the procedure's **final** session completes | a half-placed crown is not a crown; a root canal is not treated until it is obturated |

For a single-session procedure — most of them — the final session *is* the session, so "completed session updates the record" holds exactly. For a multi-session crown, the `Crown` condition appears when it is cemented, not when the tooth is prepared.

> **The dental exam needs no entity of its own.** An exam is already a `TreatmentProcedure` of a Consultation category: billable, dated, attributed to a doctor. `observedDuringProcedureId` groups the findings charted at it. One nullable FK does the work of a whole `DentalExamination` table, and the exam gets billed through the same path as every other piece of work.

**Relationships**
- N–1 → `PatientProfile`, `Tooth`
- N–1 → `TreatmentProcedure` (optional, as the resolver)

---

### ProcedureTooth
Which teeth — and which surfaces — a `TreatmentProcedure` addresses. A junction table, because the relationship is genuinely many-to-many in both directions.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| procedureId | UUID | FK → TreatmentProcedure |
| toothCode | string | FK → Tooth |
| surfaces | string | nullable — canonical-ordered subset of `validSurfaces`; null when the whole tooth is treated |
| addressesConditionId | UUID | FK → ToothCondition; nullable — **the finding this work is treating** |
| role | enum | nullable — Primary, Abutment, Pontic |
| note | text | |

Unique on (`procedureId`, `toothCode`).

**Why not a `toothCode` column on `TreatmentProcedure`.** One procedure routinely covers several teeth, and one tooth accumulates procedures over years:

| Procedure | Teeth |
|-----------|-------|
| Extraction | one |
| Composite filling | one tooth, one to three surfaces |
| Three-unit bridge | three — two `Abutment`, one `Pontic` |
| Scaling | full mouth, or per quadrant |
| Orthodontics | the whole dentition |

A single column would be wrong the first time someone plans a bridge. `role` is what makes the bridge case legible: which teeth carry the load and which one is the replacement.

> A `TreatmentPlan` needs no tooth column of its own — the teeth it covers are the union of its procedures' `ProcedureTooth` rows.

> **`addressesConditionId` is what carries the clinical *why*.** Because this table is already the (procedure × tooth) junction, hanging the finding here gives a full many-to-many link with no third table: several procedures may address one finding, and one procedure may address several. The one shape it cannot express is two separate findings on the *same* tooth treated by a single procedure — in practice those are charted as one finding with combined surfaces.

**Relationships**
- N–1 → `TreatmentProcedure`, `Tooth`

---

## Domain: Catalog & Pricing

### ServiceCategory
The catalog of dental services/procedures the clinic offers.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| name | string | e.g., "Implant", "Orthodontic", "Scaling", "Whitening" |
| description | text | visible to patients on the public service list |
| isSpecial | bool | true = requires manager approval to include in a plan |
| toothScope | enum | **None, SingleTooth, MultiTooth, Quadrant, Arch, FullMouth** — how many teeth this service applies to, and therefore how many `ProcedureTooth` rows a procedure of this type must carry |
| pricingBasis | enum | **PerProcedure, PerTooth, PerSurface, PerQuadrant** — what the `PriceList` unit price is charged *per* |
| vatRate | decimal | VAT percentage for this service, default 0. **Per service, not per clinic** — Vietnamese VAT treats medical treatment differently from cosmetic work, so a filling and a whitening may not carry the same rate. Confirm the actual rates with the clinic's accountant |
| requiresMaterialChoice | bool | true when the patient must pick a `MaterialOption` — a crown must, a consultation must not |
| requiredChairTypeId | UUID | FK → ChairType; **nullable — null means any chair will do**. Set it where the work genuinely needs the equipment: an implant needs the surgical position, a scale does not |
| warrantyDays | int | nullable — the window within which failure is presumed worth investigating. **Advisory only**: it flags a claim as in or out of window, it never decides fault |
| resultingConditionType | enum | nullable — the `ToothCondition` this service leaves behind when completed (Filling, Crown, Implant, Missing …), so the chart updates itself rather than being re-drawn by hand |
| isActive | bool | |
| displayOrder | int | for patient-facing ordering |

**Tooth scope and pricing**

`toothScope` validates; `pricingBasis` bills. They are independent — a full-mouth scaling may still be priced per quadrant.

| Service | toothScope | pricingBasis | A procedure of this type… |
|---------|-----------|--------------|---------------------------|
| Consultation | None | PerProcedure | carries no `ProcedureTooth` rows |
| Tooth Extraction | SingleTooth | PerTooth | carries exactly one |
| Composite Filling | SingleTooth | PerSurface | one tooth; price × number of surfaces |
| Porcelain Crown | SingleTooth | PerTooth | exactly one |
| Bridge | MultiTooth | PerTooth | one row per unit, abutments and pontic alike |
| Scaling & Polishing | FullMouth | PerProcedure | teeth optional; one flat price |
| Orthodontic Braces | FullMouth | PerProcedure | one flat price for the course |

> **This changes invoice arithmetic.** `Invoice.subtotal` was "sum of procedure prices"; with tooth-level work it becomes the sum over procedures of *unit price × billable quantity*, where the quantity comes from `pricingBasis`: `1` for PerProcedure, the `ProcedureTooth` count for PerTooth, the total surface count for PerSurface, the distinct quadrant count for PerQuadrant. A two-surface filling and a three-surface filling are not the same money, and the schema has to be able to say so.

**Relationships**
- 1–N → `PriceList`
- 1–N → `TreatmentProcedure`
- 1–N → `ProcedureInstruction`

---

### PriceList
Versioned price per service category, set by the manager.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| serviceCategoryId | UUID | FK → ServiceCategory |
| materialOptionId | UUID | FK → MaterialOption; **nullable — null is the category's base price**, a value prices that specific material |
| unitPrice | decimal | |
| currency | string | default "VND" |
| effectiveFrom | date | allows historical invoicing |
| setBy | UUID | FK → User (Manager) |
| notes | text | optional rationale |

Unique on (`serviceCategoryId`, `materialOptionId`, `effectiveFrom`) — one price per material per start date.

**Resolution order.** For a service, a material and a date: take the row matching both the category *and* the material with the greatest `effectiveFrom` on or before that date. If none exists, fall back to the category's base row (`materialOptionId` null). So a new material can be added without repricing everything, and a material without its own row simply costs the base price.

---

### MaterialOption
A material or product choice within a service, priced separately. A crown is a crown, but zirconia and porcelain-fused-metal are not the same money — and it is the patient who chooses.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| serviceCategoryId | UUID | FK → ServiceCategory |
| name | string | "Zirconia", "Porcelain-fused-metal", "Osstem TS III", "Ceramic bracket" |
| description | text | patient-facing — this is a choice they are asked to make, so it has to read plainly |
| isActive | bool | retire an option without disturbing the procedures that used it |
| displayOrder | int | |

| Service | Typical options |
|---------|-----------------|
| Porcelain Crown | Porcelain-fused-metal · Zirconia · E-max |
| Composite Filling | Standard composite · Premium nano-composite |
| Dental Implant | Osstem · Dentium · Straumann |
| Orthodontic Braces | Metal · Ceramic · Clear aligner |

> **Why not just separate service categories.** "Zirconia Crown" and "PFM Crown" as two categories duplicates `isSpecial`, `toothScope`, `pricingBasis`, `resultingConditionType` and the instruction templates — and the catalogue doubles again every time a new implant brand arrives. Keeping the clinical service in one row and varying only the material keeps the two axes independent: clinical rules on `ServiceCategory`, commercial choice here.

**Relationships**
- N–1 → `ServiceCategory`
- 1–N → `PriceList` (its own versioned price)
- 1–N → `TreatmentProcedure` (the patient's recorded choice)

---

### Promotion
A discount campaign applicable to a service category or clinic-wide.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| name | string | |
| discountType | enum | Percentage, FixedAmount |
| discountValue | decimal | |
| applicableTo | enum | AllServices, SpecificCategory |
| serviceCategoryId | UUID | FK → ServiceCategory; nullable |
| startDate | date | |
| endDate | date | |
| createdBy | UUID | FK → User (Manager) |
| isActive | bool | |

---

### DiscountProposal
A doctor-requested one-off discount on a specific treatment plan; requires manager approval.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| treatmentPlanId | UUID | FK → TreatmentPlan |
| proposedBy | UUID | FK → User (Doctor) |
| discountType | enum | Percentage, FixedAmount |
| discountValue | decimal | |
| reason | text | |
| status | enum | Pending, Approved, Rejected |
| reviewedBy | UUID | FK → User (Manager); nullable |
| reviewedAt | timestamp | nullable |
| reviewNote | text | nullable |

---

### SpecialProcedureProposal
A doctor's request to include a special procedure in a treatment plan; requires manager approval.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| treatmentPlanId | UUID | FK → TreatmentPlan |
| proposedBy | UUID | FK → User (Doctor) |
| serviceCategoryId | UUID | FK → ServiceCategory |
| clinicalJustification | text | |
| estimatedCost | decimal | |
| status | enum | Pending, Approved, Rejected |
| reviewedBy | UUID | FK → User (Manager); nullable |
| reviewedAt | timestamp | nullable |
| reviewNote | text | nullable |

---

## Domain: Billing

### Invoice
The billing record for a treatment plan.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| treatmentPlanId | UUID | FK → TreatmentPlan — **no longer unique**, so a long course can be billed in stages |
| patientId | UUID | FK → PatientProfile |
| invoiceSerial | string | nullable until issued — the form symbol (*ký hiệu hóa đơn*) |
| invoiceNumber | string | nullable until issued — the legal sequential number (*số hóa đơn*) |
| taxAuthorityCode | string | nullable — the code returned when the e-invoice is registered |
| issuedAt | timestamp | nullable — when it left Draft and took its number |
| subtotal | decimal | **sum of its `InvoiceLine.lineTotal`**, net of VAT |
| discountAmount | decimal | from Promotion or approved DiscountProposal |
| vatTotal | decimal | sum of its lines' `vatAmount` |
| total | decimal | subtotal − discountAmount + vatTotal |
| status | enum | Draft, Issued, PartiallyPaid, Paid, Overdue, Voided |
| dueDate | date | |
| promotionId | UUID | FK → Promotion; nullable |
| discountProposalId | UUID | FK → DiscountProposal; nullable |

**Legal numbering.** Vietnamese invoicing requires a sequential, gapless number under a registered serial, so the rules are strict:

- A number is assigned **when the invoice is issued**, never while it is `Draft`. Drafts have no number because they are not yet invoices.
- Numbers are **never reused**. A `Voided` invoice keeps its number — the gap it would otherwise leave is precisely what sequential numbering exists to prevent.
- Once issued, `invoiceSerial` and `invoiceNumber` are immutable. A correction is a credit line or a new invoice, as everywhere else in this design.

> Vietnam now mandates electronic invoicing, so an issued invoice is also registered with the tax authority. `taxAuthorityCode` is the hook for the code that comes back; the integration itself is a separate concern and is not modelled here.

> **Dropping the 1:1 with `TreatmentPlan` is what makes per-session billing possible.** A twenty-month orthodontic course cannot sit on a single invoice carried for two years while the patient pays per visit. The plan is a *clinical* container; the invoice is a *financial* document, and they do not have to line up one to one.

**Relationships**
- 1–N → `InvoiceLine` (what is being charged for)
- 1–N → `Payment` (what has been received)

---

### InvoiceLine
One billable item, frozen at the moment the invoice is issued. This is the join between clinical work and money.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| invoiceId | UUID | FK → Invoice |
| sessionId | UUID | FK → ProcedureSession; nullable — set when billing a completed session |
| procedureId | UUID | FK → TreatmentProcedure; nullable — set when billing a whole procedure up front |
| description | string | **snapshot** — "Porcelain crown (Zirconia) — tooth 24" |
| toothCodes | string | **snapshot** — "24", or "14, 15, 16" for a bridge; null when not tooth-specific |
| surfaces | string | **snapshot** — "MOD"; null when not surface-specific |
| unitPrice | decimal | **snapshot** of the resolved price, material included |
| quantity | decimal | **snapshot** — 1, the tooth count, or the surface count, per `pricingBasis` |
| vatRate | decimal | **snapshot** of the service's VAT rate at issue |
| vatAmount | decimal | **snapshot** — `lineTotal` × `vatRate`; negative on a credit line so a refund reverses the VAT too |
| lineTotal | decimal | net of VAT; **negative on a credit line**, which is how a charge is reversed |
| creditsLineId | UUID | FK → InvoiceLine; nullable — on a credit line, the original line being reversed |
| issuedAt | timestamp | |

**Every descriptive field is a snapshot, deliberately.** Clinical records get amended — `ToothCondition` carries `EnteredInError` precisely because corrections happen. If an invoice were a live view over procedures, correcting a tooth number next month would silently change a bill already issued and paid. Freezing the line decouples the financial record from the clinical one.

**The two billing modes**, following `TreatmentPlan.paymentMode`:

| Mode | Line references | Created when |
|------|-----------------|--------------|
| PerSession | `sessionId` | each session completes; `lineTotal` = that session's `billableAmount` |
| Upfront | `procedureId` | the patient accepts; `lineTotal` = the procedure's full total |

**Invariants**
- Exactly one of `sessionId` or `procedureId` is set.
- A line may only come from a **Completed** session, or an **Accepted** procedure when paying up front. A `Declined` procedure can never produce one.
- Lines are immutable once the invoice leaves `Draft`. A correction is a credit line or a new invoice, never an edit.
- A credit line has a negative `lineTotal` and names the line it reverses in `creditsLineId`. Refunding a failed veneer credits the original charge and returns the money as a `Payment` with `direction = Out`, leaving the invoice balanced at zero rather than silently rewritten.
- No session is billed twice: at most one line per `sessionId`.

**Relationships**
- N–1 → `Invoice`
- N–1 → `ProcedureSession` *or* `TreatmentProcedure`
- 0–1 → `InvoiceLine` via `creditsLineId` (the line this one reverses)

---

### Payment
An individual payment transaction against an invoice.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| invoiceId | UUID | FK → Invoice |
| direction | enum | **In, Out** — In is money received, Out is a refund returned to the patient |
| amount | decimal | always positive; `direction` carries the sign |
| method | enum | Cash, BankTransfer, Card, Other |
| paidAt | timestamp | |
| receivedBy | UUID | FK → User (Receptionist) |
| referenceNumber | string | nullable; for transfer/card |
| notes | text | |

---

## Domain: Inventory

### InventoryItem
A supply or piece of equipment the clinic stocks.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| name | string | |
| unit | string | e.g., "box", "piece", "ml" |
| quantityOnHand | decimal | current stock level |
| reorderThreshold | decimal | trigger for low-supply alert |
| tracksExpiry | bool | true for perishables — composite, anaesthetic, impression material. False for a mirror or a handpiece, which never expire and need no batches |
| vendorId | UUID | FK → Vendor; nullable |
| category | string | e.g., "Consumable", "Equipment" |
| lastRestockedAt | timestamp | |

**Invariants**
- When `tracksExpiry` is true, stock is held in `InventoryBatch` rows and `quantityOnHand` is their sum. When false, `quantityOnHand` stands alone and no batches exist.

**Relationships**
- 1–N → `InventoryBatch` (when it tracks expiry)
- 1–N → `InventoryLog`
- N–N → `ProcedureSupplyList`

---

### InventoryBatch
One delivery of one item, with its own lot number and expiry. **Expiry belongs to the batch, not the item** — ten boxes of composite bought on two dates expire on two dates, and only a batch can say which.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| inventoryItemId | UUID | FK → InventoryItem |
| lotNumber | string | the manufacturer's lot, as printed on the box |
| expiryDate | date | |
| vendorId | UUID | FK → Vendor; nullable — who supplied *this* batch |
| quantityReceived | decimal | |
| quantityRemaining | decimal | drawn down as the batch is consumed |
| unitCost | decimal | what this batch cost per unit — the basis for cost of goods |
| receivedAt | timestamp | |

**Invariants**
- `quantityRemaining` never exceeds `quantityReceived`, and never falls below zero.
- An item's `quantityOnHand` equals the sum of its batches' `quantityRemaining`, for items that track expiry.
- Consumption picks the **earliest expiry first** (FEFO), which is what stops usable stock expiring behind newer stock.
- A batch past `expiryDate` with stock remaining is written off through an `InventoryLog` entry of type `Expired` — the change type that previously had nothing to drive it.

> `unitCost` sitting here rather than on the item is what makes cost of goods answerable. The same composite bought at two prices has two batches, and a procedure's true material cost depends on which one was opened.

**Relationships**
- N–1 → `InventoryItem`, `Vendor`
- 1–N → `InventoryLog`

---

### InventoryLog
Tracks every stock movement (consumption or restocking).

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| inventoryItemId | UUID | FK → InventoryItem |
| batchId | UUID | FK → InventoryBatch; nullable — required for items that track expiry, so consumption and write-offs name the lot |
| changeType | enum | Consumed, Restocked, Adjusted, Expired |
| quantityDelta | decimal | positive = added, negative = removed |
| quantityAfter | decimal | snapshot after change |
| relatedProcedureId | UUID | FK → TreatmentProcedure; nullable |
| loggedBy | UUID | FK → User |
| loggedAt | timestamp | |
| notes | text | |

---

### Vendor
Supplier contact information for inventory restocking.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| name | string | |
| contactPerson | string | |
| phone | string | |
| email | string | |
| address | string | |
| notes | text | |
| isActive | bool | |

---

### ProcedureSupplyList
The expected supplies needed for a given procedure (linked to instruction template or a specific procedure instance).

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| procedureId | UUID | FK → TreatmentProcedure; nullable |
| instructionSetId | UUID | FK → ProcedureInstruction; nullable |
| inventoryItemId | UUID | FK → InventoryItem |
| quantityRequired | decimal | |
| notes | string | |

---

## Domain: Communication & HR

### Notification
An in-app message or page sent between staff members or to patients.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| senderId | UUID | FK → User; nullable (system-generated) |
| recipientId | UUID | FK → User; nullable if broadcast |
| recipientRole | enum | nullable; for role-broadcast (e.g., "all Assistants") |
| type | enum | Reminder, Page, Alert, Announcement |
| title | string | |
| body | text | |
| relatedEntityType | string | nullable; e.g., "Appointment", "TreatmentPlan" |
| relatedEntityId | UUID | nullable |
| isRead | bool | |
| sentAt | timestamp | |

> **Delivery is deliberately out of scope.** This entity records *what should be sent and to whom*; getting it onto a phone is a separate system — internal chat, SMS, or Zalo — to be designed on its own. When that lands it will need a channel, a delivery status and a retry policy, and those belong with the delivery adapter rather than here. Appointment reminders and the no-show reschedule chase both wait on it.

---

### WageRate
A staff member's pay rate, versioned in time. One row per rate they have ever been on; a raise or promotion **inserts** a row, never edits one.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| staffId | UUID | FK → StaffProfile |
| wageType | enum | Monthly, Hourly |
| rate | decimal | monthly salary, or hourly rate, per `wageType` |
| effectiveFrom | date | the first day this rate applies |
| reason | string | nullable — "Hired as intern", "Promoted to full-time", "Annual review 2027" |
| setBy | UUID | FK → User (Manager) |

**Resolution rule.** The rate for a given day of work is the row for that staff member with the greatest `effectiveFrom` that is on or before that day. This is the same mechanism `PriceList` uses to price a procedure by the date it was performed.

**Invariants**
- One row per (`staffId`, `effectiveFrom`) — a person cannot have two rates starting the same day.
- Every staff member has at least one row, effective from their `joinDate`.
- Rows are **append-only** once a payroll period covering them has been approved. Correcting a settled rate is a `PayrollAdjustment`, not an edit.

**Why this is not a single column on `StaffProfile`**

| Question | Single column | Versioned rows |
|----------|---------------|----------------|
| What is this person paid today? | yes | yes |
| What were they paid last quarter? | **no — overwritten** | yes |
| Can we reproduce an old payslip? | **no** | yes |
| Promotion mid-period? | **cannot express** | resolves per day |

Because the rate is resolved per `AttendanceLog` day, a promotion landing mid-period needs no special handling: days before the change find the old row, days after find the new one.

> Open decision: for `wageType = Monthly`, a rate change mid-period needs a pro-rating rule — by calendar days or by working days. `Hourly` needs none, since each day resolves independently.

**Relationships**
- N–1 → `StaffProfile`
- Read by `PayrollRecord` when computing `basePay`

---

### PayrollRecord
Monthly payroll entry for a staff member.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| staffId | UUID | FK → StaffProfile |
| periodStart | date | |
| periodEnd | date | |
| totalHoursWorked | decimal | aggregated from `AttendanceLog` for the period |
| basePay | decimal | computed from `AttendanceLog` hours against the `WageRate` in effect on each day worked — so a rate change mid-period is handled day by day. Stored as a snapshot of what was actually settled, and now reproducible from the rate history |
| commissionTotal | decimal | sum of `CommissionEntry.amount` for the period — covers all roles |
| totalCredits | decimal | sum of `PayrollAdjustment.amount` where direction = Credit |
| totalDebits | decimal | sum of `PayrollAdjustment.amount` where direction = Debit |
| netPay | decimal | basePay + commissionTotal + totalCredits − totalDebits |
| status | enum | Draft, Approved, Paid |
| approvedBy | UUID | FK → User (Manager); nullable |
| paidAt | timestamp | nullable |
| notes | text | |

> **Manager-only.** The full payroll record including commission breakdown and adjustment history is visible only to the Manager role. Staff members can see their own net pay but not the individual commission entries or adjustment reasons.

**Relationships**
- 1–N → `AttendanceLog` (period snapshot reference)
- 1–N → `CommissionEntry` (settled into this payroll — all staff types)
- 1–N → `PayrollAdjustment` (manual credits and debits applied by manager)

---

### AttendanceLog
Clock-in / clock-out record per staff per shift. Source of truth for hours-based wage calculation.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| staffId | UUID | FK → StaffProfile |
| date | date | |
| clockIn | timestamp | |
| clockOut | timestamp | nullable — null means shift still open |
| totalMinutes | int | computed on clock-out; null until then |
| payrollRecordId | UUID | FK → PayrollRecord; nullable — set when payroll is finalized |
| notes | text | nullable; e.g., reason for early leave |

---

### CommissionRule
Configurable commission rate covering all commissionable staff roles. Set by the manager; versioned like `PriceList`. **Manager-only** — staff cannot see their own commission rates or others'.

Rule matching priority (most specific wins):
1. `staffId` + role + category/event — individual contract rate
2. role + category/event — role-level rate for that procedure type or event
3. role only (both `serviceCategoryId` and `eventType` null) — catch-all for that role

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| role | enum | Doctor, Assistant, Receptionist |
| staffId | UUID | FK → StaffProfile; nullable — individual contract override, takes precedence over role-level rule |
| serviceCategoryId | UUID | FK → ServiceCategory; nullable — for Doctor/Assistant: scopes rule to a procedure type |
| eventType | enum | nullable — for Receptionist: NewPatientRegistered \| SuccessfulFollowUp |
| commissionType | enum | Percentage, FixedAmount |
| commissionValue | decimal | percentage (0–100) or fixed VND amount |
| effectiveFrom | date | |
| setBy | UUID | FK → User (Manager) |
| notes | text | |

---

### CommissionEntry
A single earned commission for any commissionable staff member. One unified record regardless of whether it came from a completed procedure (Doctor/Assistant) or a receptionist KPI event. Generated automatically by the system. **Manager-only** — individual commission entries are not exposed to the staff member directly.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| staffId | UUID | FK → StaffProfile |
| sourceType | enum | SessionCompleted \| ReceptionistEvent |
| sessionId | UUID | FK → ProcedureSession; nullable — set when sourceType = SessionCompleted |
| performanceLogId | UUID | FK → ReceptionistPerformanceLog; nullable — set when sourceType = ReceptionistEvent |
| commissionRuleId | UUID | FK → CommissionRule (rule in effect at earnedAt date) |
| commissionBase | decimal | snapshot of the base value the rule was applied to (procedure price or first invoice total) |
| amount | decimal | computed: rule applied to commissionBase |
| status | enum | Pending, IncludedInPayroll |
| payrollRecordId | UUID | FK → PayrollRecord; nullable — set when payroll is finalized |
| earnedAt | timestamp | when the trigger event occurred |

**Invariants**
- Exactly the FK its `sourceType` names is set; the other is null.
- Commission is earned **per completed session**, matching the granularity at which the clinic is paid.
- **Only the people who did the work are paid.** An entry credits the session's `performedBy` and its `assistantId` — never `TreatmentPlan.doctorId`, who owns the case but may not have been in the room. A procedure delivered over three visits by two different doctors and two different assistants produces entries attributing each visit to whoever was actually there.
- **No staff member earns commission on their own treatment.** An entry may not be created where the `staffId` resolves to the same `User` as the patient on the procedure's `TreatmentPlan`. This applies to the doctor and the assistant alike.

> Staff are permitted to be treated at the clinic — the rule is only about payment. If Dr. Mai treats Dr. Minh, Dr. Mai earns her commission normally; Dr. Minh earns nothing, because he is the patient.

---

### ReceptionistPerformanceLog
A standalone event log recording KPI events for receptionists. Acts as the source record that triggers a `CommissionEntry` — it does not carry commission amounts itself. One record per event, linking the receptionist to the specific patient they brought in.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| receptionistId | UUID | FK → StaffProfile |
| eventType | enum | NewPatientRegistered \| SuccessfulFollowUp |
| patientId | UUID | FK → PatientProfile — the patient this event relates to |
| appointmentId | UUID | FK → Appointment; nullable — the specific appointment that completed (for SuccessfulFollowUp) |
| occurredAt | timestamp | |

> **NewPatientRegistered**: written when a receptionist registers a new `PatientProfile` and that patient completes their first appointment. The `CommissionEntry` commission base is the first `Invoice.total` for that patient (supports percentage-of-revenue rules).

> **SuccessfulFollowUp**: written when an `Appointment` with `type = Followup` and `followedUpBy` set reaches `status = Completed`. The receptionist credited is `followedUpBy`. Commission base is typically a flat amount.

> A `CommissionEntry` (with `sourceType = ReceptionistEvent`) is created immediately after this record is written. The manager sees both the raw event and the computed commission amount at payroll review time.

---

### PayrollAdjustment
A manager-created manual credit or debit applied to a staff member's payroll. Used to correct for staff mistakes, patient refunds caused by procedure errors, or exceptional bonuses not covered by commission rules. Every adjustment requires a written reason and is permanently auditable.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| staffId | UUID | FK → StaffProfile — the staff member whose payroll is affected |
| direction | enum | Credit \| Debit |
| amount | decimal | always positive; `direction` determines whether it adds or subtracts from netPay |
| reason | text | mandatory — manager's written explanation (e.g., "Patient refund for botched implant procedure", "End-of-year performance bonus") |
| relatedCommissionEntryId | UUID | FK → CommissionEntry; nullable — use when reversing a specific earned commission (e.g., commission on a refunded invoice) |
| relatedInvoiceId | UUID | FK → Invoice; nullable — use when the cause is a specific patient refund |
| relatedFailureId | UUID | FK → TreatmentFailure; nullable — use when the cause is work the clinic judged its own fault |
| payrollRecordId | UUID | FK → PayrollRecord; nullable — set when this adjustment is included in a finalized payroll period |
| status | enum | Pending \| IncludedInPayroll |
| createdBy | UUID | FK → User (Manager) |
| createdAt | timestamp | |

> **Manager-only.** Only the Manager role can create, edit, or view `PayrollAdjustment` records. Adjustments in `Pending` status can be edited or deleted before payroll is finalized. Once `IncludedInPayroll`, they become immutable — any correction requires a new offsetting adjustment.

> **Typical debit scenarios:** work the clinic judged its own fault, charged to the staff who performed it (links `relatedFailureId`, and `relatedInvoiceId` for the refunded invoice); commission clawback when a commission was paid on a treatment later cancelled (links `relatedCommissionEntryId`). The amount is the manager's judgment and may exceed the refund itself, since a lab remake and the free chair time are real losses too.

> **Typical credit scenarios:** one-off end-of-year bonus; compensation for a shift covered at short notice.
