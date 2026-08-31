# KPX — Core Entity Definitions

---

## Domain: Identity & Access

### User
The single authentication record for every person in the system.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| email | string | unique, used for login |
| passwordHash | string | |
| role | enum | Manager, Doctor, Receptionist, Accountant, Assistant, Patient |
| isActive | bool | soft-disable without deleting |
| createdAt | timestamp | |

**Relationships**
- 1–1 → `StaffProfile` (if role is staff)
- 1–1 → `PatientProfile` (if role is Patient)
- 1–N → `Notification` (sent or received)

---

### StaffProfile
Extended information for any non-patient user.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| userId | UUID | FK → User |
| fullName | string | |
| phone | string | |
| address | string | |
| dateOfBirth | date | |
| joinDate | date | |
| specialty | string | nullable; relevant for Doctor (e.g., "Orthodontics") |
| licenseNumber | string | nullable; for Doctor |
| wageType | enum | Monthly, Hourly — determines how base pay is calculated from attendance |
| hourlyRate | decimal | nullable; used when wageType = Hourly |

**Relationships**
- 1–N → `PayrollRecord`
- 1–N → `AttendanceLog`
- 1–N → `CommissionEntry`
- 1–N → `ReceptionistPerformanceLog.receptionistId` (if role is Receptionist)
- 1–N → `DoctorSchedule` (if role is Doctor)
- 1–N → `Appointment.doctorId` (if role is Doctor)

---

### PatientProfile
Extended information for patients.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| userId | UUID | FK → User; nullable (walk-in patients created by receptionist may not have a login yet) |
| fullName | string | |
| phone | string | |
| dateOfBirth | date | |
| address | string | |
| emergencyContact | string | |
| referralSource | string | nullable |
| createdBy | UUID | FK → User (receptionist who registered) |
| createdAt | timestamp | |

**Relationships**
- 1–1 → `HealthRecord`
- 1–N → `Appointment`
- 1–N → `TreatmentPlan`
- 1–N → `PatientMedia`

---

## Domain: Scheduling

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
| patientId | UUID | FK → PatientProfile |
| doctorId | UUID | FK → StaffProfile |
| scheduledAt | timestamp | |
| durationMinutes | int | default 30 |
| type | enum | Consultation, Procedure, Followup |
| status | enum | Scheduled, Confirmed, InProgress, Completed, Cancelled, NoShow |
| treatmentProcedureId | UUID | FK → TreatmentProcedure; nullable (consultation has none) |
| assistantId | UUID | FK → StaffProfile; nullable — assistant assigned to this visit |
| followedUpBy | UUID | FK → User (Receptionist); nullable — receptionist whose follow-up contact led to this booking |
| notes | text | receptionist or doctor notes |
| createdBy | UUID | FK → User |
| createdAt | timestamp | |

**Relationships**
- N–1 → `PatientProfile`
- N–1 → `StaffProfile` (doctor)
- N–1 → `StaffProfile` (assistant, optional)
- N–1 → `TreatmentProcedure` (optional)
- 1–N → `Notification` (reminders)

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
| patientId | UUID | FK → PatientProfile |
| doctorId | UUID | FK → StaffProfile |
| title | string | e.g., "Lower implant — Q3 2026" |
| status | enum | Draft, PendingApproval, Active, Completed, Cancelled |
| isSpecial | bool | derived from procedures; if true, requires SpecialProcedureProposal approval |
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
An individual step or session within a treatment plan.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| treatmentPlanId | UUID | FK → TreatmentPlan |
| serviceCategoryId | UUID | FK → ServiceCategory |
| instructionSetId | UUID | FK → ProcedureInstruction; nullable |
| sequence | int | order within the plan |
| status | enum | Planned, Scheduled, InProgress, Completed, Skipped |
| doctorNote | text | instructions for next session |
| assistantId | UUID | FK → StaffProfile; nullable — assistant who worked this procedure (used for commission) |
| scheduledDate | date | nullable |
| completedDate | date | nullable |

**Relationships**
- 1–N → `TreatmentProgress`
- 1–N → `Appointment`
- 1–N → `ProcedureSupplyList`
- 1–N → `CommissionEntry` (one for doctor, one for assistant on completion)

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

### TreatmentProgress
A timestamped log entry recording what happened during a procedure session.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| procedureId | UUID | FK → TreatmentProcedure |
| loggedBy | UUID | FK → User (Doctor or Assistant) |
| loggedAt | timestamp | |
| progressNote | text | |
| vitals | json | pulse, blood pressure, etc.; nullable |
| nextStepNote | text | doctor's note for next session |

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
| isActive | bool | |
| displayOrder | int | for patient-facing ordering |

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
| unitPrice | decimal | |
| currency | string | default "VND" |
| effectiveFrom | date | allows historical invoicing |
| setBy | UUID | FK → User (Manager) |
| notes | text | optional rationale |

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
| treatmentPlanId | UUID | FK → TreatmentPlan |
| patientId | UUID | FK → PatientProfile |
| issuedAt | timestamp | |
| subtotal | decimal | sum of procedure prices |
| discountAmount | decimal | from Promotion or approved DiscountProposal |
| total | decimal | subtotal − discountAmount |
| status | enum | Draft, Issued, PartiallyPaid, Paid, Overdue, Voided |
| dueDate | date | |
| promotionId | UUID | FK → Promotion; nullable |
| discountProposalId | UUID | FK → DiscountProposal; nullable |

**Relationships**
- 1–N → `Payment`

---

### Payment
An individual payment transaction against an invoice.

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| invoiceId | UUID | FK → Invoice |
| amount | decimal | |
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
| vendorId | UUID | FK → Vendor; nullable |
| category | string | e.g., "Consumable", "Equipment" |
| lastRestockedAt | timestamp | |

**Relationships**
- 1–N → `InventoryLog`
- N–N → `ProcedureSupplyList`

---

### InventoryLog
Tracks every stock movement (consumption or restocking).

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| inventoryItemId | UUID | FK → InventoryItem |
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
| basePay | decimal | fixed monthly salary OR hourlyRate × totalHoursWorked |
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
| sourceType | enum | ProcedureCompleted \| ReceptionistEvent |
| procedureId | UUID | FK → TreatmentProcedure; nullable — set when sourceType = ProcedureCompleted |
| performanceLogId | UUID | FK → ReceptionistPerformanceLog; nullable — set when sourceType = ReceptionistEvent |
| commissionRuleId | UUID | FK → CommissionRule (rule in effect at earnedAt date) |
| commissionBase | decimal | snapshot of the base value the rule was applied to (procedure price or first invoice total) |
| amount | decimal | computed: rule applied to commissionBase |
| status | enum | Pending, IncludedInPayroll |
| payrollRecordId | UUID | FK → PayrollRecord; nullable — set when payroll is finalized |
| earnedAt | timestamp | when the trigger event occurred |

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
| payrollRecordId | UUID | FK → PayrollRecord; nullable — set when this adjustment is included in a finalized payroll period |
| status | enum | Pending \| IncludedInPayroll |
| createdBy | UUID | FK → User (Manager) |
| createdAt | timestamp | |

> **Manager-only.** Only the Manager role can create, edit, or view `PayrollAdjustment` records. Adjustments in `Pending` status can be edited or deleted before payroll is finalized. Once `IncludedInPayroll`, they become immutable — any correction requires a new offsetting adjustment.

> **Typical debit scenarios:** patient refund caused by a procedure error (links `relatedInvoiceId`); commission clawback when a commission was paid on a treatment that was later cancelled (links `relatedCommissionEntryId`).

> **Typical credit scenarios:** one-off end-of-year bonus; compensation for a shift covered at short notice.
