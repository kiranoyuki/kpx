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
| Communication & HR | Notification, PayrollRecord |

---

## High-Level Entity Map

```
User (role: Manager | Doctor | Receptionist | Accountant | Assistant | Patient)
 ├── StaffProfile (Doctor, Manager, Receptionist, Accountant, Assistant)
 │    └── PayrollRecord
 └── PatientProfile
      ├── HealthRecord
      ├── PatientMedia (X-rays, CBCT, before/after photos)
      ├── Appointment ──────────────── DoctorSchedule
      └── TreatmentPlan
           ├── TreatmentProcedure ─── ProcedureInstruction
           │    └── TreatmentProgress
           │    └── ProcedureSupplyList ── InventoryItem
           ├── DiscountProposal (doctor → manager approval)
           ├── SpecialProcedureProposal (doctor → manager approval)
           └── Invoice
                └── Payment

ServiceCategory ─── PriceList (set by Manager)
                └── Promotion (set by Manager)

InventoryItem ─── Vendor
              └── InventoryLog

Notification (broadcast or targeted, sent by any staff role)
```

---

## Key Design Decisions

### 1. Unified `User` table with role-based profiles
A single `User` record handles authentication. Role-specific data lives in `StaffProfile` or `PatientProfile`. This lets a person hold one login while the system enforces role permissions.

### 2. `TreatmentPlan` is the clinical anchor
Everything clinical orbits the treatment plan: procedures, progress logs, notes, discounts, invoicing. A patient may have multiple treatment plans over time (e.g., one for orthodontics, one for implants).

### 3. Procedures are typed by `ServiceCategory`
`ServiceCategory` carries the `isSpecial` flag. Special categories (implant, orthodontic) require a `SpecialProcedureProposal` approved by the manager before the plan is activated. This matches the doctor's approval workflow.

### 4. Pricing is time-versioned
`PriceList` records carry an `effectiveFrom` date so historical invoices remain correct after the manager changes prices.

### 5. Discounts flow through two paths
- **Manager-set promotions**: `Promotion` entities applied at invoice time.
- **Doctor-proposed discounts**: `DiscountProposal` linked to a specific `TreatmentPlan`; requires manager approval before being applied to the `Invoice`.

### 6. Inventory is dual-purpose
`ProcedureSupplyList` is a template per `ProcedureInstruction` (what supplies are expected). `InventoryLog` records actual consumption or restocking events. Assistants work from both views.

### 7. `Notification` is a first-class entity
Paging between staff (doctor → assistant, manager → all) is tracked as notifications, not just ephemeral pushes. This supports audit and follow-up reminders.
