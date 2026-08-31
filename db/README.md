# KPX Database

SQLite build of the KPX data model. **Scope: the "patient becomes revenue" spine only** —
the remaining domains (clinical records, approvals, inventory, HR/payroll, notifications)
are not built yet.

## Files

| File | Role |
|------|------|
| `schema.sql` | DDL — 12 tables, 4 views, 29 indexes. Source of truth. |
| `seed.sql`   | Mock data — 6 patient cases through to payment and commission. |
| `build.sh`   | Drops and rebuilds `kpx.db` from the two files above, then verifies. |
| `kpx.db`     | Build artefact. Gitignored — never edit it as the source of truth. |

## Rebuild

```bash
./db/build.sh
```

Destroys the local `kpx.db` and rebuilds it. Edit `schema.sql` / `seed.sql`, then rerun.

## Tables in this scope

`app_user` · `staff_profile` · `patient_profile` · `service_category` · `price_list`
`treatment_plan` · `treatment_procedure` · `appointment` · `invoice` · `payment`
`commission_rule` · `commission_entry`

`commission_rule` was pulled in because `commission_entry.commission_rule_id` is
`NOT NULL` — without it a commission amount has no provenance.

Columns deliberately left out until their target tables exist:
`invoice.promotion_id`, `invoice.discount_proposal_id`, `commission_entry.payroll_record_id`,
`commission_entry.performance_log_id`, `treatment_procedure.instruction_set_id`.
They join by `ALTER TABLE` when those domains land.

## Identity model

`app_user` is a **person record, not a login**. Every human has exactly one row.
Three facts move independently:

| Fact | Becomes true when | Held by |
|------|-------------------|---------|
| We know who they are | First contact | the row exists |
| We have verified them | They arrive and someone checks their documents | `verified_at` / `verified_by` |
| They can log in | Optional; may never happen | `password_hash` |

Two `CHECK` constraints enforce it:

```sql
status <> 'Active' OR (verified_at IS NOT NULL AND verified_by IS NOT NULL)
password_hash IS NULL OR email IS NOT NULL
```

`national_id` is the Vietnamese CCCD: **exactly 12 digits**, `UNIQUE`, optional, and
stored as `TEXT` — it is an identifier, not a quantity, and leading zeros are significant.

**Intake paths, all through one table:**

| Path | What happens |
|------|--------------|
| Books online | `Provisional` row: name, phone, email. No CCCD, no password. Appointment booked against it immediately. |
| Arrives | Receptionist fills `national_id`, stamps `verified_at`/`verified_by`, flips to `Active`, creates `patient_profile`. |
| No-shows | Stays `Provisional`. `v_reschedule_followup` finds them. |
| Walks in | Created `Active` in one step, CCCD in hand. |

**`appointment.person_id` references `app_user`, not `patient_profile`** — an online
booking exists before the person has arrived. `treatment_plan` and `invoice` still
reference `patient_profile`: you can book before you are a patient, but you cannot
carry a treatment plan or an invoice until you are. Conversion on arrival is one
`UPDATE` plus one `INSERT`; the appointment's FK never changes.

## Views

| View | Answers |
|------|---------|
| `v_invoice_balance`      | What does each patient still owe? |
| `v_revenue_spine`        | One row per procedure, patient through to invoice status. |
| `v_commission_dashboard` | Unsettled commission per staff member. Manager-only. |
| `v_current_price`        | Price in effect today per service. |
| `v_reschedule_followup`  | Who booked online, never arrived, and has nothing on the books? |
| `v_intake_funnel`        | How many people sit at each stage of the identity lifecycle? |

## Conventions

- **ids** — `TEXT`. Seed data uses readable slugs (`pp-01`, `proc-03`); production uses UUIDs.
- **money** — `NUMERIC`, VND, whole numbers. Percentage rates carry decimals.
- **timestamps** — `TEXT`, ISO-8601. **dates** — `TEXT`, `YYYY-MM-DD`.
- **booleans** — `INTEGER` 0/1. **enums** — `TEXT` + `CHECK`.
- `app_user` maps to the `User` entity; renamed because `user` is reserved in PostgreSQL.

**Foreign keys are OFF by default in SQLite.** Every connection must issue
`PRAGMA foreign_keys = ON;` — including the DBeaver connection (see below).

## What the seed data exercises

| Person | Case | State |
|--------|------|-------|
| Hoàng Văn Tuấn | Implant, in progress | Active, can log in — invoice PartiallyPaid, 12,400,000 outstanding |
| Nguyễn Thị Lan Anh | Orthodontics, in progress | Active, can log in — PartiallyPaid, 2,000,000 discount |
| Trần Minh Đức | Crown, Nov 2025 | Active, can log in — Paid at the **superseded** crown price |
| Phạm Thị Ngọc | Root canal + crown | Active, **no email, no login** — verified walk-in |
| Lý Văn Hùng | Consultation only | Active, **no email, no login** — verified walk-in |
| Đặng Thu Trang | New patient exam + hygiene | Active, can log in — Paid, arrived via referral |
| Bùi Thị Hạnh | Booked online, upcoming | **Provisional** — no CCCD, no login, no patient_profile |
| Ngô Quang Huy | Booked online, no-showed | **Provisional** — the one row `v_reschedule_followup` returns |

Deliberate edge cases worth keeping as the schema grows:

- **Verified but cannot log in.** Two patients are fully `Active` with a CCCD on file and
  no credentials at all. This is the case that breaks designs which bundle identity
  and authentication into one flag.
- **Provisional people hold bookings.** Two rows have appointments but no
  `patient_profile`. `v_intake_funnel` shows them as `is_patient = 0`.
- **The chase is precise.** `v_reschedule_followup` returns only Ngô Quang Huy —
  Bùi Thị Hạnh no-showed nothing and still has a future booking, so she is excluded.
- **Price versioning bites.** `Porcelain Crown` has two `price_list` rows. Trần Minh Đức's
  2025 invoice uses 5,500,000; Hoàng Văn Tuấn's 2026 crown uses 6,000,000. Both correct.
- **Contract commission rates.** `cr-05` gives Dr. Minh 22% on implants, beating the
  role-level 20% (`cr-03`) and the 15% catch-all (`cr-01`). Precedence is
  staff+role+category → role+category → role.
- **Commission only on completion.** `proc-04`, `proc-07` and `proc-11` are not
  `Completed`, so they have generated no `commission_entry` rows.
- **The manager self-verifies.** A bootstrap case: the owner set the system up before
  anyone existed to check her documents.
