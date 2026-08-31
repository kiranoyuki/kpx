-- =============================================================================
-- KPX — Dental Clinic Management
-- SCOPE: "patient becomes revenue" spine only
--
--   app_user · staff_profile · patient_profile · service_category · price_list
--   treatment_plan · treatment_procedure · appointment
--   invoice · payment · commission_rule · commission_entry
--
-- Source of truth for the full model: Design/core-entities/entities.md
-- Remaining domains (clinical records, approvals, inventory, HR/payroll,
-- notifications) are deliberately not built yet.
-- =============================================================================
--
-- CONVENTIONS
--   ids         TEXT holding a UUID string (readable slugs used in seed data)
--   timestamps  TEXT, ISO-8601 'YYYY-MM-DD HH:MM:SS'
--   dates       TEXT, 'YYYY-MM-DD'
--   money       NUMERIC — VND, whole numbers; percentage rates carry decimals
--   booleans    INTEGER 0 / 1
--   enums       TEXT + CHECK constraint (SQLite has no native enum)
--
-- NAMING: tables are snake_case, mapping 1:1 to the PascalCase entities in
-- entities.md. Exception: app_user <-> User, because "user" is reserved in
-- PostgreSQL and naming around it keeps a later migration off a rename.
--
-- Foreign keys are OFF by default in SQLite. Every connection must issue:
--     PRAGMA foreign_keys = ON;
-- =============================================================================

PRAGMA foreign_keys = ON;


-- =============================================================================
-- IDENTITY & ACCESS
--
-- app_user is a PERSON record, not a login. Every human in the system has
-- exactly one row. Three facts about a person move independently:
--
--   1. We know who they are   -> the row exists (name + phone, from first contact)
--   2. We have verified them  -> verified_at / verified_by stamped on arrival
--   3. They can log in        -> password_hash present (optional, may never happen)
--
-- Bundling these is what makes walk-ins and online no-shows awkward. Split,
-- every intake path falls out of the same table:
--
--   Online booking  -> Provisional row: name, phone, email. No CCCD, no password.
--   They arrive     -> receptionist verifies, fills national_id, flips to Active,
--                      creates patient_profile. Credentials offered separately.
--   They no-show    -> stays Provisional; reminder query finds them.
--   Walk-in         -> created Active in one step, CCCD in hand.
--
-- Identity fields (name, phone, address, dob, national_id) live here ONCE.
-- staff_profile and patient_profile hold only employment / care data.
-- =============================================================================

CREATE TABLE app_user (
    id             TEXT PRIMARY KEY,

    -- identity — known from first contact
    full_name      TEXT NOT NULL,
    phone          TEXT NOT NULL,          -- practical dedup key before a CCCD exists
    email          TEXT UNIQUE,            -- nullable: walk-ins may have none
    date_of_birth  TEXT,
    address        TEXT,
    -- Vietnamese CCCD: exactly 12 digits. Optional — a foreign patient or an
    -- elderly walk-in may be verified by other means.
    national_id    TEXT UNIQUE,

    -- lifecycle
    status         TEXT NOT NULL DEFAULT 'Provisional'
                       CHECK (status IN ('Provisional', 'Active', 'Inactive')),
    verified_at    TEXT,                   -- when identity was checked in person
    verified_by    TEXT REFERENCES app_user(id),

    -- credentials — independent of verification; NULL = cannot log in
    password_hash  TEXT,

    role           TEXT NOT NULL CHECK (role IN (
                       'Manager', 'Doctor', 'Receptionist',
                       'Accountant', 'Assistant', 'Patient')),
    created_at     TEXT NOT NULL DEFAULT (datetime('now')),

    -- CCCD is exactly 12 digits when present
    CHECK (national_id IS NULL OR
           national_id GLOB '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'),
    -- Active means a person physically verified them
    CHECK (status <> 'Active' OR (verified_at IS NOT NULL AND verified_by IS NOT NULL)),
    -- no username, no login
    CHECK (password_hash IS NULL OR email IS NOT NULL)
);

-- Employment data only. Identity lives on app_user.
CREATE TABLE staff_profile (
    id              TEXT PRIMARY KEY,
    user_id         TEXT NOT NULL UNIQUE REFERENCES app_user(id) ON DELETE CASCADE,
    join_date       TEXT,
    specialty       TEXT,                                   -- Doctor only
    license_number  TEXT,                                   -- Doctor only
    wage_type       TEXT NOT NULL DEFAULT 'Monthly'
                        CHECK (wage_type IN ('Monthly', 'Hourly')),
    hourly_rate     NUMERIC,
    CHECK (wage_type <> 'Hourly' OR hourly_rate IS NOT NULL)
);

-- The care relationship. Created on arrival, never at online-booking time —
-- its existence is what distinguishes a patient from a provisional booker.
CREATE TABLE patient_profile (
    id                 TEXT PRIMARY KEY,
    user_id            TEXT NOT NULL UNIQUE REFERENCES app_user(id) ON DELETE CASCADE,
    emergency_contact  TEXT,
    referral_source    TEXT,
    created_by         TEXT NOT NULL REFERENCES app_user(id),
    created_at         TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_app_user_phone       ON app_user(phone);        -- dedup at booking
CREATE INDEX idx_app_user_status      ON app_user(status);
CREATE INDEX idx_app_user_name        ON app_user(full_name);
CREATE INDEX idx_app_user_verifier    ON app_user(verified_by);
CREATE INDEX idx_staff_profile_user   ON staff_profile(user_id);
CREATE INDEX idx_patient_profile_user ON patient_profile(user_id);
CREATE INDEX idx_patient_profile_creator ON patient_profile(created_by);


-- =============================================================================
-- CATALOG & PRICING
-- =============================================================================

CREATE TABLE service_category (
    id             TEXT PRIMARY KEY,
    name           TEXT NOT NULL UNIQUE,
    description    TEXT,                                    -- patient-facing
    -- true => including this in a plan requires manager approval
    is_special     INTEGER NOT NULL DEFAULT 0 CHECK (is_special IN (0, 1)),
    is_active      INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    display_order  INTEGER NOT NULL DEFAULT 0
);

-- Time-versioned. A procedure is priced by the row in effect on the date it
-- was performed, so past invoices stay correct after a price change.
CREATE TABLE price_list (
    id                   TEXT PRIMARY KEY,
    service_category_id  TEXT NOT NULL REFERENCES service_category(id) ON DELETE CASCADE,
    unit_price           NUMERIC NOT NULL CHECK (unit_price >= 0),
    currency             TEXT NOT NULL DEFAULT 'VND',
    effective_from       TEXT NOT NULL,
    set_by               TEXT NOT NULL REFERENCES app_user(id),
    notes                TEXT,
    UNIQUE (service_category_id, effective_from)
);

CREATE INDEX idx_price_list_category ON price_list(service_category_id, effective_from DESC);


-- =============================================================================
-- CLINICAL (spine only)
--
-- treatment_plan and invoice reference patient_profile, not app_user: you
-- cannot carry a treatment plan or an invoice until you have arrived and
-- become a patient. Only appointment accepts a provisional person.
-- =============================================================================

CREATE TABLE treatment_plan (
    id                 TEXT PRIMARY KEY,
    patient_id         TEXT NOT NULL REFERENCES patient_profile(id) ON DELETE CASCADE,
    doctor_id          TEXT NOT NULL REFERENCES staff_profile(id),
    title              TEXT NOT NULL,
    status             TEXT NOT NULL DEFAULT 'Draft' CHECK (status IN (
                           'Draft', 'PendingApproval', 'Active', 'Completed', 'Cancelled')),
    -- derived from its procedures; true => needed manager approval to activate
    is_special         INTEGER NOT NULL DEFAULT 0 CHECK (is_special IN (0, 1)),
    start_date         TEXT,
    estimated_end_date TEXT,
    notes              TEXT,
    created_at         TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at         TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE treatment_procedure (
    id                   TEXT PRIMARY KEY,
    treatment_plan_id    TEXT NOT NULL REFERENCES treatment_plan(id) ON DELETE CASCADE,
    service_category_id  TEXT NOT NULL REFERENCES service_category(id),
    sequence             INTEGER NOT NULL,
    status               TEXT NOT NULL DEFAULT 'Planned' CHECK (status IN (
                             'Planned', 'Scheduled', 'InProgress', 'Completed', 'Skipped')),
    doctor_note          TEXT,                              -- instructions for next session
    -- assistant who worked this procedure; drives their commission entry
    assistant_id         TEXT REFERENCES staff_profile(id) ON DELETE SET NULL,
    scheduled_date       TEXT,
    completed_date       TEXT,
    UNIQUE (treatment_plan_id, sequence),
    CHECK (status <> 'Completed' OR completed_date IS NOT NULL)
);

CREATE INDEX idx_treatment_plan_patient   ON treatment_plan(patient_id);
CREATE INDEX idx_treatment_plan_doctor    ON treatment_plan(doctor_id);
CREATE INDEX idx_treatment_plan_status    ON treatment_plan(status);
CREATE INDEX idx_treatment_proc_plan      ON treatment_procedure(treatment_plan_id);
CREATE INDEX idx_treatment_proc_cat       ON treatment_procedure(service_category_id);
CREATE INDEX idx_treatment_proc_assistant ON treatment_procedure(assistant_id);
CREATE INDEX idx_treatment_proc_status    ON treatment_procedure(status);


-- =============================================================================
-- SCHEDULING
--
-- person_id references app_user, NOT patient_profile. An online booking is
-- made before the person has arrived and become a patient, so the appointment
-- must be able to point at a Provisional person. Keeping this on one table is
-- what avoids a polymorphic FK: conversion on arrival is one UPDATE to the
-- app_user row plus one INSERT into patient_profile — the appointment's FK
-- never changes, because it was valid from the moment it was booked.
-- =============================================================================

CREATE TABLE appointment (
    id                     TEXT PRIMARY KEY,
    person_id              TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    doctor_id              TEXT NOT NULL REFERENCES staff_profile(id),
    scheduled_at           TEXT NOT NULL,
    duration_minutes       INTEGER NOT NULL DEFAULT 30 CHECK (duration_minutes > 0),
    type                   TEXT NOT NULL CHECK (type IN ('Consultation', 'Procedure', 'Followup')),
    status                 TEXT NOT NULL DEFAULT 'Scheduled' CHECK (status IN (
                               'Scheduled', 'Confirmed', 'InProgress',
                               'Completed', 'Cancelled', 'NoShow')),
    -- how the booking arrived; Online bookings are the ones that create
    -- Provisional people and need the no-show reschedule chase
    booking_channel        TEXT NOT NULL DEFAULT 'FrontDesk'
                               CHECK (booking_channel IN ('Online', 'FrontDesk', 'Phone')),
    treatment_procedure_id TEXT REFERENCES treatment_procedure(id) ON DELETE SET NULL,
    assistant_id           TEXT REFERENCES staff_profile(id) ON DELETE SET NULL,
    -- receptionist whose follow-up contact produced this booking; a completed
    -- Followup appointment with this set is that receptionist's KPI credit
    followed_up_by         TEXT REFERENCES app_user(id) ON DELETE SET NULL,
    notes                  TEXT,
    created_by             TEXT REFERENCES app_user(id),    -- NULL = self-booked online
    created_at             TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_appointment_person      ON appointment(person_id);
CREATE INDEX idx_appointment_doctor_when ON appointment(doctor_id, scheduled_at);
CREATE INDEX idx_appointment_when        ON appointment(scheduled_at);
CREATE INDEX idx_appointment_status      ON appointment(status);
CREATE INDEX idx_appointment_channel     ON appointment(booking_channel, status);
CREATE INDEX idx_appointment_procedure   ON appointment(treatment_procedure_id);
CREATE INDEX idx_appointment_followup    ON appointment(followed_up_by);


-- =============================================================================
-- BILLING
--
-- NOTE: promotion_id and discount_proposal_id are omitted at this scope —
-- their target tables aren't built yet. discount_amount still carries the
-- money so invoice arithmetic is correct; the provenance columns join later.
-- =============================================================================

CREATE TABLE invoice (
    id                 TEXT PRIMARY KEY,
    treatment_plan_id  TEXT NOT NULL UNIQUE REFERENCES treatment_plan(id) ON DELETE CASCADE,
    patient_id         TEXT NOT NULL REFERENCES patient_profile(id),
    issued_at          TEXT,
    subtotal           NUMERIC NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
    discount_amount    NUMERIC NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    total              NUMERIC NOT NULL DEFAULT 0 CHECK (total >= 0),
    status             TEXT NOT NULL DEFAULT 'Draft' CHECK (status IN (
                           'Draft', 'Issued', 'PartiallyPaid',
                           'Paid', 'Overdue', 'Voided')),
    due_date           TEXT,
    CHECK (discount_amount <= subtotal),
    CHECK (total = subtotal - discount_amount)
);

CREATE TABLE payment (
    id                TEXT PRIMARY KEY,
    invoice_id        TEXT NOT NULL REFERENCES invoice(id) ON DELETE CASCADE,
    amount            NUMERIC NOT NULL CHECK (amount > 0),
    method            TEXT NOT NULL CHECK (method IN ('Cash', 'BankTransfer', 'Card', 'Other')),
    paid_at           TEXT NOT NULL DEFAULT (datetime('now')),
    received_by       TEXT NOT NULL REFERENCES app_user(id),
    reference_number  TEXT,
    notes             TEXT
);

CREATE INDEX idx_invoice_patient  ON invoice(patient_id);
CREATE INDEX idx_invoice_status   ON invoice(status);
CREATE INDEX idx_payment_invoice  ON payment(invoice_id);
CREATE INDEX idx_payment_when     ON payment(paid_at);


-- =============================================================================
-- COMMISSION  [Manager-only at the API layer]
--
-- commission_rule is included because commission_entry.commission_rule_id is
-- NOT NULL — without it an entry's amount has no provenance.
--
-- At this scope commission_entry covers the ProcedureCompleted path only.
-- The ReceptionistEvent path (performance_log_id) and payroll settlement
-- (payroll_record_id) arrive with the HR domain.
-- =============================================================================

-- One versioned rate table for every commissionable role.
-- Match precedence, most specific first:
--   1. staff_id + role + service_category_id   -- individual contract rate
--   2. role + service_category_id              -- role rate for that procedure type
--   3. role, category null                     -- catch-all for the role
CREATE TABLE commission_rule (
    id                  TEXT PRIMARY KEY,
    role                TEXT NOT NULL CHECK (role IN ('Doctor', 'Assistant', 'Receptionist')),
    staff_id            TEXT REFERENCES staff_profile(id) ON DELETE CASCADE,
    service_category_id TEXT REFERENCES service_category(id) ON DELETE CASCADE,
    event_type          TEXT CHECK (event_type IN ('NewPatientRegistered', 'SuccessfulFollowUp')),
    commission_type     TEXT NOT NULL CHECK (commission_type IN ('Percentage', 'FixedAmount')),
    commission_value    NUMERIC NOT NULL CHECK (commission_value >= 0),
    effective_from      TEXT NOT NULL,
    set_by              TEXT NOT NULL REFERENCES app_user(id),
    notes               TEXT,
    CHECK (commission_type <> 'Percentage' OR commission_value <= 100),
    -- category scopes clinical roles; event_type scopes the receptionist. Never both.
    CHECK (service_category_id IS NULL OR event_type IS NULL),
    CHECK (role <> 'Receptionist' OR service_category_id IS NULL),
    CHECK (role =  'Receptionist' OR event_type IS NULL)
);

CREATE TABLE commission_entry (
    id                  TEXT PRIMARY KEY,
    staff_id            TEXT NOT NULL REFERENCES staff_profile(id) ON DELETE CASCADE,
    source_type         TEXT NOT NULL DEFAULT 'ProcedureCompleted'
                            CHECK (source_type IN ('ProcedureCompleted', 'ReceptionistEvent')),
    procedure_id        TEXT REFERENCES treatment_procedure(id) ON DELETE SET NULL,
    commission_rule_id  TEXT NOT NULL REFERENCES commission_rule(id),
    commission_base     NUMERIC NOT NULL CHECK (commission_base >= 0), -- snapshot at earn time
    amount              NUMERIC NOT NULL CHECK (amount >= 0),
    status              TEXT NOT NULL DEFAULT 'Pending'
                            CHECK (status IN ('Pending', 'IncludedInPayroll')),
    earned_at           TEXT NOT NULL DEFAULT (datetime('now')),
    -- only the procedure path exists at this scope
    CHECK (source_type = 'ProcedureCompleted' AND procedure_id IS NOT NULL)
);

CREATE INDEX idx_commission_rule_lookup  ON commission_rule(role, effective_from DESC);
CREATE INDEX idx_commission_rule_staff   ON commission_rule(staff_id);
CREATE INDEX idx_commission_rule_cat     ON commission_rule(service_category_id);
CREATE INDEX idx_commission_entry_staff  ON commission_entry(staff_id, earned_at);
CREATE INDEX idx_commission_entry_status ON commission_entry(status);
CREATE INDEX idx_commission_entry_proc   ON commission_entry(procedure_id);
CREATE INDEX idx_commission_entry_rule   ON commission_entry(commission_rule_id);


-- =============================================================================
-- VIEWS — the revenue spine, read the way each role needs it
-- =============================================================================

-- What each invoice still owes.
CREATE VIEW v_invoice_balance AS
SELECT i.id            AS invoice_id,
       u.full_name     AS patient,
       tp.title        AS treatment_plan,
       i.subtotal, i.discount_amount, i.total,
       COALESCE(SUM(pay.amount), 0)            AS paid,
       i.total - COALESCE(SUM(pay.amount), 0)  AS balance_due,
       i.status, i.due_date
FROM invoice i
JOIN patient_profile pp ON pp.id = i.patient_id
JOIN app_user        u  ON u.id  = pp.user_id
JOIN treatment_plan  tp ON tp.id = i.treatment_plan_id
LEFT JOIN payment   pay ON pay.invoice_id = i.id
GROUP BY i.id, u.full_name, tp.title, i.subtotal,
         i.discount_amount, i.total, i.status, i.due_date;

-- The spine end to end: one row per procedure, patient through to money.
CREATE VIEW v_revenue_spine AS
SELECT pu.full_name       AS patient,
       tp.title           AS treatment_plan,
       tp.status          AS plan_status,
       tpr.sequence       AS step,
       sc.name            AS service,
       tpr.status         AS procedure_status,
       tpr.completed_date,
       du.full_name       AS doctor,
       au.full_name       AS assistant,
       i.total            AS invoice_total,
       i.status           AS invoice_status
FROM treatment_procedure tpr
JOIN treatment_plan   tp  ON tp.id  = tpr.treatment_plan_id
JOIN patient_profile  pp  ON pp.id  = tp.patient_id
JOIN app_user         pu  ON pu.id  = pp.user_id
JOIN service_category sc  ON sc.id  = tpr.service_category_id
JOIN staff_profile    doc ON doc.id = tp.doctor_id
JOIN app_user         du  ON du.id  = doc.user_id
LEFT JOIN staff_profile ast ON ast.id = tpr.assistant_id
LEFT JOIN app_user      au  ON au.id  = ast.user_id
LEFT JOIN invoice     i   ON i.treatment_plan_id = tp.id
ORDER BY pu.full_name, tpr.sequence;

-- Manager's commission dashboard: what each staff member has earned, unsettled.
CREATE VIEW v_commission_dashboard AS
SELECT u.full_name                  AS staff,
       u.role,
       COUNT(ce.id)                 AS entries,
       SUM(ce.commission_base)      AS total_base,
       SUM(ce.amount)               AS commission_earned,
       ce.status
FROM commission_entry ce
JOIN staff_profile s ON s.id = ce.staff_id
JOIN app_user      u ON u.id = s.user_id
GROUP BY u.full_name, u.role, ce.status
ORDER BY commission_earned DESC;

-- Price actually in effect on a given date, per service.
CREATE VIEW v_current_price AS
SELECT sc.id   AS service_category_id,
       sc.name AS service,
       sc.is_special,
       pl.unit_price,
       pl.currency,
       pl.effective_from
FROM service_category sc
JOIN price_list pl ON pl.id = (
    SELECT id FROM price_list
    WHERE service_category_id = sc.id AND effective_from <= date('now')
    ORDER BY effective_from DESC LIMIT 1
);

-- The reschedule chase: people who booked online, never arrived, and have
-- nothing on the books. Still Provisional, so they never became patients.
CREATE VIEW v_reschedule_followup AS
SELECT u.id            AS person_id,
       u.full_name,
       u.phone,
       u.email,
       a.id            AS missed_appointment_id,
       a.scheduled_at  AS missed_at,
       a.booking_channel,
       julianday('now') - julianday(a.scheduled_at) AS days_since
FROM app_user u
JOIN appointment a ON a.person_id = u.id AND a.status = 'NoShow'
WHERE u.status = 'Provisional'
  AND NOT EXISTS (
      SELECT 1 FROM appointment f
      WHERE f.person_id = u.id
        AND f.status IN ('Scheduled', 'Confirmed')
        AND f.scheduled_at > a.scheduled_at)
ORDER BY a.scheduled_at DESC;

-- Intake funnel: how many people sit at each stage of the identity lifecycle.
CREATE VIEW v_intake_funnel AS
SELECT u.status,
       u.role,
       COUNT(*)                                             AS people,
       SUM(CASE WHEN u.national_id   IS NOT NULL THEN 1 ELSE 0 END) AS with_cccd,
       SUM(CASE WHEN u.password_hash IS NOT NULL THEN 1 ELSE 0 END) AS can_log_in,
       SUM(CASE WHEN pp.id           IS NOT NULL THEN 1 ELSE 0 END) AS is_patient
FROM app_user u
LEFT JOIN patient_profile pp ON pp.user_id = u.id
GROUP BY u.status, u.role
ORDER BY u.status, u.role;
