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
    -- Written as an equality this passed a Paid record that had an approved_at
    -- but no approver: both sides were simply false. A CASE says what is meant.
    CONSTRAINT ck_pay_approved CHECK (
        CASE status WHEN 'Draft' THEN approved_by IS NULL     AND approved_at IS NULL
                    ELSE              approved_by IS NOT NULL AND approved_at IS NOT NULL END),
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
    CONSTRAINT ck_att_out_after_in    CHECK (clock_out IS NULL OR clock_out > clock_in),
    -- `date` is what the wage lookup joins on, so a date that disagrees with the
    -- clock would price the shift at some other day's rate.
    CONSTRAINT ck_att_date_is_clock_in CHECK (date = date(clock_in))
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
    -- RESTRICT, not SET NULL: an appointment that paid a bounty cannot be
    -- deleted out from under it.
    appointment_id  TEXT REFERENCES appointment(id) ON DELETE RESTRICT,
    occurred_at     TEXT NOT NULL DEFAULT (datetime('now')),

    -- A follow-up IS an appointment; without one there is nothing to have
    -- succeeded at, and nothing to make the event unique.
    CONSTRAINT ck_rpl_followup_has_appt CHECK (event_type <> 'SuccessfulFollowUp' OR appointment_id IS NOT NULL)
);

-- The old UNIQUE spanned appointment_id, and SQLite treats NULLs as distinct —
-- so the same registration logged twice with no appointment slipped through and
-- was paid twice. The uniqueness is different per event type anyway:
--   a patient is registered new exactly ONCE, by whoever did it;
--   a follow-up is unique to the APPOINTMENT it brought the patient back for.
CREATE UNIQUE INDEX uq_rpl_new_patient ON receptionist_performance_log(patient_id)
    WHERE event_type = 'NewPatientRegistered';
CREATE UNIQUE INDEX uq_rpl_follow_up   ON receptionist_performance_log(appointment_id)
    WHERE event_type = 'SuccessfulFollowUp';


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
-- At most one shift open at a time: you cannot clock in while already in.
CREATE UNIQUE INDEX idx_att_open  ON attendance_log(staff_id) WHERE clock_out IS NULL;
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
-- VIEWS
-- =============================================================================

-- The wage rate in force for a staff member on any given date.
CREATE VIEW v_current_wage AS
SELECT s.id AS staff_id, u.full_name AS staff, u.role, s.employment_status,
       w.wage_type, w.rate, w.effective_from, w.reason
FROM staff_profile s
JOIN app_user u ON u.id = s.user_id
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
  AND w.wage_type = 'Hourly'   -- belt and braces; trg_att_hourly_only keeps the log clean
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
