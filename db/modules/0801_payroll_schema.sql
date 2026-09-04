-- =============================================================================
-- KPX — MODULE 8: Payroll & Commission
-- wage_rate · attendance_log · commission_rule · receptionist_performance_log
-- commission_entry · payroll_adjustment · payroll_record
--
-- Source of truth: Design/core-entities/entities.md
-- Build order:     Design/build-plan.md  (module 8 of 9; reads from 1,2,3,5,6)
--
--   net_pay = base_pay + commission_total + credits - debits
--
--   base_pay   <- attendance_log hours x the wage_rate in force THAT DAY
--   commission <- commission_entry, one mechanism for every role
--   credits /  <- payroll_adjustment, manager-entered with a mandatory reason
--   debits
--
-- MANAGER-ONLY at the API layer: rates, entries and adjustments are not
-- visible to the staff they concern.
-- =============================================================================

PRAGMA foreign_keys = ON;


-- A pay rate, versioned in time. A raise or promotion INSERTS a row and never
-- edits one, so an intern's months keep the intern rate forever. Same shape as
-- price_list: the rate for a day is the row with the greatest effective_from on
-- or before it.
CREATE TABLE wage_rate (
    id             TEXT PRIMARY KEY,
    staff_id       TEXT NOT NULL REFERENCES staff_profile(id) ON DELETE CASCADE,
    wage_type      TEXT NOT NULL CHECK (wage_type IN ('Monthly','Hourly')),
    rate           NUMERIC NOT NULL CHECK (rate >= 0),
    effective_from TEXT NOT NULL,
    reason         TEXT,
    set_by         TEXT NOT NULL REFERENCES app_user(id),
    UNIQUE (staff_id, effective_from)
);


CREATE TABLE payroll_record (
    id                 TEXT PRIMARY KEY,
    staff_id           TEXT NOT NULL REFERENCES staff_profile(id) ON DELETE CASCADE,
    period_start       TEXT NOT NULL,
    period_end         TEXT NOT NULL,
    total_hours_worked NUMERIC NOT NULL DEFAULT 0 CHECK (total_hours_worked >= 0),
    base_pay           NUMERIC NOT NULL DEFAULT 0 CHECK (base_pay >= 0),
    commission_total   NUMERIC NOT NULL DEFAULT 0 CHECK (commission_total >= 0),
    total_credits      NUMERIC NOT NULL DEFAULT 0 CHECK (total_credits >= 0),
    total_debits       NUMERIC NOT NULL DEFAULT 0 CHECK (total_debits >= 0),
    net_pay            NUMERIC NOT NULL DEFAULT 0,
    status             TEXT NOT NULL DEFAULT 'Draft' CHECK (status IN ('Draft','Approved','Paid')),
    approved_by        TEXT REFERENCES app_user(id),
    approved_at        TEXT,
    paid_at            TEXT,
    notes              TEXT,

    UNIQUE (staff_id, period_start, period_end),
    CONSTRAINT ck_pay_period CHECK (period_end >= period_start),
    CONSTRAINT ck_pay_approved CHECK ((status = 'Draft') = (approved_by IS NULL AND approved_at IS NULL)),
    CONSTRAINT ck_pay_paid     CHECK ((status = 'Paid') = (paid_at IS NOT NULL)),
    CONSTRAINT ck_pay_net      CHECK (net_pay = base_pay + commission_total + total_credits - total_debits)
);


CREATE TABLE attendance_log (
    id                TEXT PRIMARY KEY,
    staff_id          TEXT NOT NULL REFERENCES staff_profile(id) ON DELETE CASCADE,
    date              TEXT NOT NULL,
    clock_in          TEXT NOT NULL,
    clock_out         TEXT,                       -- NULL means the shift is still open
    total_minutes     INTEGER CHECK (total_minutes IS NULL OR total_minutes > 0),
    payroll_record_id TEXT REFERENCES payroll_record(id),
    notes             TEXT,

    UNIQUE (staff_id, date, clock_in),
    CONSTRAINT ck_att_closed_together CHECK ((clock_out IS NULL) = (total_minutes IS NULL)),
    CONSTRAINT ck_att_out_after_in    CHECK (clock_out IS NULL OR clock_out > clock_in)
);


-- One versioned rate table for every commissionable role.
-- Match precedence, most specific first:
--   1. staff_id + role + service_category   -- individual contract rate
--   2. role + service_category              -- role rate for that procedure type
--   3. role, category null                  -- catch-all for the role
CREATE TABLE commission_rule (
    id                  TEXT PRIMARY KEY,
    role                TEXT NOT NULL CHECK (role IN ('Doctor','Assistant','Receptionist')),
    staff_id            TEXT REFERENCES staff_profile(id) ON DELETE CASCADE,
    service_category_id TEXT REFERENCES service_category(id) ON DELETE CASCADE,
    event_type          TEXT CHECK (event_type IS NULL OR event_type IN ('NewPatientRegistered','SuccessfulFollowUp')),
    commission_type     TEXT NOT NULL CHECK (commission_type IN ('Percentage','FixedAmount')),
    commission_value    NUMERIC NOT NULL CHECK (commission_value >= 0),
    effective_from      TEXT NOT NULL,
    set_by              TEXT NOT NULL REFERENCES app_user(id),
    notes               TEXT,

    CONSTRAINT ck_rule_pct_max_100 CHECK (commission_type <> 'Percentage' OR commission_value <= 100),
    -- category scopes the clinical roles; event_type scopes the receptionist
    CONSTRAINT ck_rule_one_scope   CHECK (service_category_id IS NULL OR event_type IS NULL),
    CONSTRAINT ck_rule_recep_event CHECK (role <> 'Receptionist' OR service_category_id IS NULL),
    CONSTRAINT ck_rule_clinical    CHECK (role =  'Receptionist' OR event_type IS NULL)
);


-- A standalone event log bridging staff and patient: which receptionist brought
-- which patient in. Records WHAT HAPPENED; the money is a commission_entry.
CREATE TABLE receptionist_performance_log (
    id              TEXT PRIMARY KEY,
    receptionist_id TEXT NOT NULL REFERENCES staff_profile(id) ON DELETE CASCADE,
    event_type      TEXT NOT NULL CHECK (event_type IN ('NewPatientRegistered','SuccessfulFollowUp')),
    patient_id      TEXT NOT NULL REFERENCES patient_profile(id) ON DELETE CASCADE,
    appointment_id  TEXT REFERENCES appointment(id) ON DELETE SET NULL,
    occurred_at     TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (receptionist_id, event_type, patient_id, appointment_id)
);


-- The unified earned-commission record: one shape for every role.
CREATE TABLE commission_entry (
    id                 TEXT PRIMARY KEY,
    staff_id           TEXT NOT NULL REFERENCES staff_profile(id) ON DELETE RESTRICT,
    source_type        TEXT NOT NULL CHECK (source_type IN ('SessionCompleted','ReceptionistEvent')),
    session_id         TEXT REFERENCES procedure_session(id),
    performance_log_id TEXT REFERENCES receptionist_performance_log(id),
    commission_rule_id TEXT NOT NULL REFERENCES commission_rule(id) ON DELETE RESTRICT,
    commission_base    NUMERIC NOT NULL CHECK (commission_base >= 0),  -- snapshot at earn time
    amount             NUMERIC NOT NULL CHECK (amount >= 0),
    status             TEXT NOT NULL DEFAULT 'Pending' CHECK (status IN ('Pending','IncludedInPayroll')),
    payroll_record_id  TEXT REFERENCES payroll_record(id),
    earned_at          TEXT NOT NULL DEFAULT (datetime('now')),

    CONSTRAINT ck_ce_source CHECK (
        (source_type = 'SessionCompleted'  AND session_id IS NOT NULL AND performance_log_id IS NULL) OR
        (source_type = 'ReceptionistEvent' AND performance_log_id IS NOT NULL AND session_id IS NULL)),
    CONSTRAINT ck_ce_settled CHECK ((status = 'Pending') = (payroll_record_id IS NULL))
);

-- One entry per person per source: nobody is paid twice for the same work.
CREATE UNIQUE INDEX uq_ce_session ON commission_entry(staff_id, session_id) WHERE session_id IS NOT NULL;
CREATE UNIQUE INDEX uq_ce_event   ON commission_entry(staff_id, performance_log_id) WHERE performance_log_id IS NOT NULL;


-- A manager-entered correction, with a mandatory written reason.
CREATE TABLE payroll_adjustment (
    id                          TEXT PRIMARY KEY,
    staff_id                    TEXT NOT NULL REFERENCES staff_profile(id) ON DELETE RESTRICT,
    direction                   TEXT NOT NULL CHECK (direction IN ('Credit','Debit')),
    amount                      NUMERIC NOT NULL CHECK (amount > 0),
    reason                      TEXT NOT NULL,
    related_commission_entry_id TEXT REFERENCES commission_entry(id),
    related_invoice_id          TEXT REFERENCES invoice(id),
    related_failure_id          TEXT REFERENCES treatment_failure(id),
    payroll_record_id           TEXT REFERENCES payroll_record(id),
    status                      TEXT NOT NULL DEFAULT 'Pending' CHECK (status IN ('Pending','IncludedInPayroll')),
    created_by                  TEXT NOT NULL REFERENCES app_user(id),
    created_at                  TEXT NOT NULL DEFAULT (datetime('now')),

    CONSTRAINT ck_adj_reason   CHECK (length(trim(reason)) > 0),
    CONSTRAINT ck_adj_settled  CHECK ((status = 'Pending') = (payroll_record_id IS NULL))
);


CREATE INDEX idx_wage_lookup      ON wage_rate(staff_id, effective_from DESC);
CREATE INDEX idx_att_staff_date   ON attendance_log(staff_id, date);
CREATE INDEX idx_att_open         ON attendance_log(staff_id) WHERE clock_out IS NULL;
CREATE INDEX idx_att_payroll      ON attendance_log(payroll_record_id);
CREATE INDEX idx_rule_lookup      ON commission_rule(role, effective_from DESC);
CREATE INDEX idx_rule_staff       ON commission_rule(staff_id);
CREATE INDEX idx_rule_category    ON commission_rule(service_category_id);
CREATE INDEX idx_rpl_receptionist ON receptionist_performance_log(receptionist_id, occurred_at);
CREATE INDEX idx_rpl_patient      ON receptionist_performance_log(patient_id);
CREATE INDEX idx_ce_staff         ON commission_entry(staff_id, earned_at);
CREATE INDEX idx_ce_status        ON commission_entry(status);
CREATE INDEX idx_ce_payroll       ON commission_entry(payroll_record_id);
CREATE INDEX idx_adj_staff        ON payroll_adjustment(staff_id, status);
CREATE INDEX idx_adj_payroll      ON payroll_adjustment(payroll_record_id);
CREATE INDEX idx_payroll_staff    ON payroll_record(staff_id, period_start DESC);


-- =============================================================================
-- TRIGGERS
-- =============================================================================

-- THE RULE THAT MATTERS MOST HERE: nobody is paid for treating themselves.
-- Consolidating staff and patients onto one app_user row is what made this
-- possible to check at all — and necessary to check, since without it a doctor
-- could quietly bill the clinic for their own treatment.
CREATE TRIGGER trg_ce_not_own_treatment BEFORE INSERT ON commission_entry
WHEN NEW.session_id IS NOT NULL
BEGIN
    SELECT RAISE(ABORT, 'no commission on your own treatment: the staff member is the patient')
    WHERE (SELECT sp.user_id FROM staff_profile sp WHERE sp.id = NEW.staff_id)
        = (SELECT pp.user_id
             FROM procedure_session s
             JOIN treatment_procedure pr ON pr.id = s.procedure_id
             JOIN treatment_plan tp      ON tp.id = pr.treatment_plan_id
             JOIN patient_profile pp     ON pp.id = tp.patient_id
            WHERE s.id = NEW.session_id);
END;

-- Commission credits the people who did THAT session's work, and only them.
-- TreatmentPlan.doctor_id owns the case but may not have been in the room.
CREATE TRIGGER trg_ce_must_have_worked BEFORE INSERT ON commission_entry
WHEN NEW.session_id IS NOT NULL
BEGIN
    SELECT RAISE(ABORT, 'that staff member did not work this session')
    WHERE NEW.staff_id NOT IN (
        SELECT performed_by FROM procedure_session WHERE id = NEW.session_id
        UNION ALL
        SELECT assistant_id FROM procedure_session WHERE id = NEW.session_id AND assistant_id IS NOT NULL);

    SELECT RAISE(ABORT, 'commission is earned on completed work only')
    WHERE (SELECT status FROM procedure_session WHERE id = NEW.session_id) <> 'Completed';

    -- free rework bills nothing, so it earns nothing. This falls out of the
    -- arithmetic rather than needing a rule, but stating it makes the intent
    -- explicit and catches a zero-base entry written by mistake.
    SELECT RAISE(ABORT, 'free rework earns no commission: the clinic was at fault')
    WHERE (SELECT pr.remedy_for_failure_id FROM procedure_session s
             JOIN treatment_procedure pr ON pr.id = s.procedure_id
            WHERE s.id = NEW.session_id) IS NOT NULL;
END;

-- The amount must be what the cited rule actually grants.
CREATE TRIGGER trg_ce_amount_matches_rule BEFORE INSERT ON commission_entry
BEGIN
    SELECT RAISE(ABORT, 'commission amount does not match the rule it cites')
    WHERE NEW.amount <> (
        SELECT CASE r.commission_type
                   WHEN 'Percentage'  THEN CAST(ROUND(NEW.commission_base * r.commission_value / 100.0) AS INTEGER)
                   WHEN 'FixedAmount' THEN r.commission_value
               END
        FROM commission_rule r WHERE r.id = NEW.commission_rule_id);

    SELECT RAISE(ABORT, 'that rule was not yet in force when the commission was earned')
    WHERE (SELECT effective_from FROM commission_rule WHERE id = NEW.commission_rule_id) > date(NEW.earned_at);
END;

-- The base must be the session's own value, not an invented figure.
CREATE TRIGGER trg_ce_base_is_session_value BEFORE INSERT ON commission_entry
WHEN NEW.session_id IS NOT NULL
BEGIN
    SELECT RAISE(ABORT, 'commission_base must equal the session''s billable_amount')
    WHERE NEW.commission_base <> COALESCE((SELECT billable_amount FROM procedure_session WHERE id = NEW.session_id), -1);
END;

-- Attendance: minutes must match the clock.
CREATE TRIGGER trg_att_minutes_match BEFORE INSERT ON attendance_log
WHEN NEW.clock_out IS NOT NULL
BEGIN
    SELECT RAISE(ABORT, 'total_minutes does not match clock_in and clock_out')
    WHERE NEW.total_minutes
       <> CAST(ROUND((julianday(NEW.clock_out) - julianday(NEW.clock_in)) * 1440) AS INTEGER);
END;

-- Settled payroll is immutable. A correction is a new adjustment in the next
-- period, never an edit — the same rule that governs invoices and the clinical
-- record.
CREATE TRIGGER trg_payroll_locked_once_approved BEFORE UPDATE ON payroll_record
WHEN OLD.status IN ('Approved','Paid')
     AND (NEW.base_pay <> OLD.base_pay OR NEW.commission_total <> OLD.commission_total
       OR NEW.total_credits <> OLD.total_credits OR NEW.total_debits <> OLD.total_debits
       OR NEW.net_pay <> OLD.net_pay)
BEGIN
    SELECT RAISE(ABORT, 'an approved payroll record is immutable: raise a new adjustment instead');
END;

CREATE TRIGGER trg_adj_locked_once_settled BEFORE UPDATE ON payroll_adjustment
WHEN OLD.status = 'IncludedInPayroll'
BEGIN
    SELECT RAISE(ABORT, 'a settled adjustment is immutable: raise an offsetting one instead');
END;

CREATE TRIGGER trg_ce_locked_once_settled BEFORE UPDATE ON commission_entry
WHEN OLD.status = 'IncludedInPayroll' AND NEW.amount <> OLD.amount
BEGIN
    SELECT RAISE(ABORT, 'a settled commission entry is immutable: clawback with an adjustment');
END;


-- =============================================================================
-- VIEWS
-- =============================================================================

-- The wage rate in force for a staff member on any given date.
CREATE VIEW v_current_wage AS
SELECT s.id AS staff_id, u.full_name AS staff, u.role, sp.employment_status,
       w.wage_type, w.rate, w.effective_from, w.reason
FROM staff_profile s
JOIN staff_profile sp ON sp.id = s.id
JOIN app_user u       ON u.id = s.user_id
JOIN wage_rate w ON w.id = (
    SELECT id FROM wage_rate x WHERE x.staff_id = s.id AND x.effective_from <= date('now')
    ORDER BY x.effective_from DESC LIMIT 1)
ORDER BY u.full_name;

-- Hours worked, priced at the rate in force ON EACH DAY. A rate change
-- mid-period therefore needs no special handling: every day finds its own rate.
CREATE VIEW v_attendance_priced AS
SELECT a.id, u.full_name AS staff, a.date, a.total_minutes,
       ROUND(a.total_minutes / 60.0, 2) AS hours,
       w.rate AS rate_that_day,
       CAST(ROUND(a.total_minutes / 60.0 * w.rate) AS INTEGER) AS pay,
       a.payroll_record_id
FROM attendance_log a
JOIN staff_profile s ON s.id = a.staff_id
JOIN app_user u      ON u.id = s.user_id
JOIN wage_rate w ON w.id = (
    SELECT id FROM wage_rate x WHERE x.staff_id = a.staff_id AND x.effective_from <= a.date
    ORDER BY x.effective_from DESC LIMIT 1)
WHERE a.total_minutes IS NOT NULL
ORDER BY u.full_name, a.date;

-- The manager's commission dashboard. MANAGER-ONLY.
CREATE VIEW v_commission_dashboard AS
SELECT u.full_name AS staff, u.role, ce.status,
       COUNT(*) AS entries,
       SUM(ce.commission_base) AS total_base,
       SUM(ce.amount)          AS commission
FROM commission_entry ce
JOIN staff_profile s ON s.id = ce.staff_id
JOIN app_user u      ON u.id = s.user_id
GROUP BY u.full_name, u.role, ce.status
ORDER BY commission DESC;

-- Every commission entry with the work behind it, so an amount can be traced.
CREATE VIEW v_commission_detail AS
SELECT u.full_name AS staff, u.role, ce.source_type,
       COALESCE(sc.name, rpl.event_type) AS earned_on,
       COALESCE(pu.full_name, ru.full_name) AS patient,
       CASE WHEN s.performed_by = ce.staff_id THEN 'performed'
            WHEN s.assistant_id = ce.staff_id THEN 'assisted'
            ELSE 'event' END AS worked_as,
       ce.commission_base,
       r.commission_type, r.commission_value,
       COALESCE(cs.name, 'catch-all') AS rule_scope,
       CASE WHEN r.staff_id IS NOT NULL THEN 'contract rate' ELSE 'role rate' END AS rule_kind,
       ce.amount, ce.status, ce.earned_at
FROM commission_entry ce
JOIN staff_profile st ON st.id = ce.staff_id
JOIN app_user u       ON u.id = st.user_id
JOIN commission_rule r ON r.id = ce.commission_rule_id
LEFT JOIN service_category cs ON cs.id = r.service_category_id
LEFT JOIN procedure_session s ON s.id = ce.session_id
LEFT JOIN treatment_procedure pr ON pr.id = s.procedure_id
LEFT JOIN service_category sc ON sc.id = pr.service_category_id
LEFT JOIN treatment_plan tp ON tp.id = pr.treatment_plan_id
LEFT JOIN patient_profile pp ON pp.id = tp.patient_id
LEFT JOIN app_user pu ON pu.id = pp.user_id
LEFT JOIN receptionist_performance_log rpl ON rpl.id = ce.performance_log_id
LEFT JOIN patient_profile rp ON rp.id = rpl.patient_id
LEFT JOIN app_user ru ON ru.id = rp.user_id
ORDER BY u.full_name, ce.earned_at;

-- The payslip: three streams, and what they net to.
CREATE VIEW v_payslip AS
SELECT u.full_name AS staff, u.role, p.period_start, p.period_end,
       p.total_hours_worked AS hours, p.base_pay,
       p.commission_total AS commission, p.total_credits AS credits, p.total_debits AS debits,
       p.net_pay, p.status, m.full_name AS approved_by
FROM payroll_record p
JOIN staff_profile s ON s.id = p.staff_id
JOIN app_user u      ON u.id = s.user_id
LEFT JOIN app_user m ON m.id = p.approved_by
ORDER BY p.period_start DESC, u.full_name;

-- What is earned but not yet settled — the next payroll run's input.
CREATE VIEW v_unsettled AS
SELECT u.full_name AS staff, 'commission' AS kind, ce.amount, ce.earned_at AS dated, NULL AS reason
FROM commission_entry ce
JOIN staff_profile s ON s.id = ce.staff_id JOIN app_user u ON u.id = s.user_id
WHERE ce.status = 'Pending'
UNION ALL
SELECT u.full_name, CASE a.direction WHEN 'Credit' THEN 'credit' ELSE 'DEBIT' END,
       CASE a.direction WHEN 'Credit' THEN a.amount ELSE -a.amount END, a.created_at, a.reason
FROM payroll_adjustment a
JOIN staff_profile s ON s.id = a.staff_id JOIN app_user u ON u.id = s.user_id
WHERE a.status = 'Pending'
ORDER BY staff, dated;
