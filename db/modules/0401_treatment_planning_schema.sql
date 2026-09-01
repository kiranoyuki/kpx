-- =============================================================================
-- KPX — MODULE 4: Treatment Planning
-- treatment_plan · procedure_instruction · treatment_procedure
-- procedure_decision · discount_proposal · special_procedure_proposal
--
-- Source of truth: Design/core-entities/entities.md
-- Build order:     Design/build-plan.md  (module 4 of 9; depends on 1 and 2)
--
-- NOTE ON THE ONE CIRCULAR DEPENDENCY
-- treatment_procedure.remedy_for_failure_id points at treatment_failure, which
-- points back at treatment_procedure. Declaring the forward FK here does not
-- work: CREATE TABLE accepts it, but with foreign_keys = ON the first INSERT
-- fails with "no such table", even inserting NULL. So the column is NOT created
-- here. Module 6 adds it once treatment_failure exists:
--
--     ALTER TABLE treatment_procedure
--         ADD COLUMN remedy_for_failure_id TEXT REFERENCES treatment_failure(id);
--
-- SQLite permits a REFERENCES clause on ADD COLUMN, and the constraint enforces
-- normally afterwards. No pragma is ever disabled.
-- =============================================================================

PRAGMA foreign_keys = ON;


CREATE TABLE treatment_plan (
    id                 TEXT PRIMARY KEY,
    patient_id         TEXT NOT NULL REFERENCES patient_profile(id) ON DELETE CASCADE,
    -- the doctor RESPONSIBLE for the case. Ownership only: this earns nothing.
    -- Commission follows whoever actually worked each session.
    doctor_id          TEXT NOT NULL REFERENCES staff_profile(id),
    title              TEXT NOT NULL,
    status             TEXT NOT NULL DEFAULT 'Draft' CHECK (status IN (
                           'Draft','PendingApproval','Active','Completed','Cancelled')),
    is_special         INTEGER NOT NULL DEFAULT 0 CHECK (is_special IN (0,1)),
    payment_mode       TEXT NOT NULL DEFAULT 'PerSession'
                           CHECK (payment_mode IN ('Upfront','PerSession')),
    start_date         TEXT,
    estimated_end_date TEXT,
    notes              TEXT,
    created_at         TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at         TEXT NOT NULL DEFAULT (datetime('now')),

    CONSTRAINT ck_plan_dates CHECK (
        estimated_end_date IS NULL OR start_date IS NULL OR estimated_end_date >= start_date)
);


-- Reusable clinical instruction templates a doctor authors per procedure type.
CREATE TABLE procedure_instruction (
    id                  TEXT PRIMARY KEY,
    created_by          TEXT NOT NULL REFERENCES staff_profile(id),
    service_category_id TEXT NOT NULL REFERENCES service_category(id),
    title               TEXT NOT NULL,
    instructions        TEXT,
    supplies_required   TEXT,
    version             INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);


CREATE TABLE treatment_procedure (
    id                  TEXT PRIMARY KEY,
    treatment_plan_id   TEXT NOT NULL REFERENCES treatment_plan(id) ON DELETE CASCADE,
    service_category_id TEXT NOT NULL REFERENCES service_category(id),
    -- the patient's material choice; required where the category demands one
    material_option_id  TEXT REFERENCES material_option(id),
    instruction_set_id  TEXT REFERENCES procedure_instruction(id) ON DELETE SET NULL,
    sequence            INTEGER NOT NULL,
    status              TEXT NOT NULL DEFAULT 'Proposed' CHECK (status IN (
                            'Proposed','Accepted','Declined','Scheduled',
                            'InProgress','Completed','Skipped')),
    planned_sessions    INTEGER NOT NULL DEFAULT 1 CHECK (planned_sessions > 0),
    -- NULL until the procedure is first invoiced (module 6). Before that there
    -- is no stored price at all, only an estimate regenerated on demand.
    unit_price          NUMERIC CHECK (unit_price IS NULL OR unit_price >= 0),
    doctor_note         TEXT,
    completed_date      TEXT,

    UNIQUE (treatment_plan_id, sequence),
    CONSTRAINT ck_proc_completed_has_date CHECK (
        (status = 'Completed') = (completed_date IS NOT NULL))
);


-- Append-only log of every status change: who decided, when, and why.
-- The clinic's defensive record — what did we recommend, what did the patient
-- agree to, and what did they refuse.
CREATE TABLE procedure_decision (
    id             TEXT PRIMARY KEY,
    procedure_id   TEXT NOT NULL REFERENCES treatment_procedure(id) ON DELETE CASCADE,
    from_status    TEXT CHECK (from_status IS NULL OR from_status IN (
                       'Proposed','Accepted','Declined','Scheduled','InProgress','Completed','Skipped')),
    to_status      TEXT NOT NULL CHECK (to_status IN (
                       'Proposed','Accepted','Declined','Scheduled','InProgress','Completed','Skipped')),
    decided_by     TEXT NOT NULL REFERENCES app_user(id),
    decided_at     TEXT NOT NULL DEFAULT (datetime('now')),
    -- a refusal without a reason is a status; with a reason and an explained
    -- risk it is a defence
    reason         TEXT,
    risk_explained INTEGER CHECK (risk_explained IS NULL OR risk_explained IN (0,1)),
    note           TEXT,

    CONSTRAINT ck_decision_reason_required CHECK (
        to_status NOT IN ('Declined','Skipped') OR (reason IS NOT NULL AND length(trim(reason)) > 0))
);


-- Doctor-requested discount on a plan; requires manager approval.
CREATE TABLE discount_proposal (
    id                TEXT PRIMARY KEY,
    treatment_plan_id TEXT NOT NULL REFERENCES treatment_plan(id) ON DELETE CASCADE,
    proposed_by       TEXT NOT NULL REFERENCES app_user(id),
    discount_type     TEXT NOT NULL CHECK (discount_type IN ('Percentage','FixedAmount')),
    discount_value    NUMERIC NOT NULL CHECK (discount_value > 0),
    reason            TEXT NOT NULL,
    status            TEXT NOT NULL DEFAULT 'Pending'
                          CHECK (status IN ('Pending','Approved','Rejected')),
    reviewed_by       TEXT REFERENCES app_user(id),
    reviewed_at       TEXT,
    review_note       TEXT,

    CONSTRAINT ck_discount_pct_max_100 CHECK (
        discount_type <> 'Percentage' OR discount_value <= 100),
    CONSTRAINT ck_discount_reviewed CHECK (
        (status = 'Pending') = (reviewed_by IS NULL AND reviewed_at IS NULL))
);


-- Doctor's request to include a service flagged is_special; manager approves.
CREATE TABLE special_procedure_proposal (
    id                     TEXT PRIMARY KEY,
    treatment_plan_id      TEXT NOT NULL REFERENCES treatment_plan(id) ON DELETE CASCADE,
    proposed_by            TEXT NOT NULL REFERENCES app_user(id),
    service_category_id    TEXT NOT NULL REFERENCES service_category(id),
    clinical_justification TEXT NOT NULL,
    estimated_cost         NUMERIC CHECK (estimated_cost IS NULL OR estimated_cost >= 0),
    status                 TEXT NOT NULL DEFAULT 'Pending'
                               CHECK (status IN ('Pending','Approved','Rejected')),
    reviewed_by            TEXT REFERENCES app_user(id),
    reviewed_at            TEXT,
    review_note            TEXT,

    CONSTRAINT ck_special_reviewed CHECK (
        (status = 'Pending') = (reviewed_by IS NULL AND reviewed_at IS NULL))
);


CREATE INDEX idx_plan_patient        ON treatment_plan(patient_id);
CREATE INDEX idx_plan_doctor         ON treatment_plan(doctor_id);
CREATE INDEX idx_plan_status         ON treatment_plan(status);
CREATE INDEX idx_instr_category      ON procedure_instruction(service_category_id);
CREATE INDEX idx_proc_plan           ON treatment_procedure(treatment_plan_id, sequence);
CREATE INDEX idx_proc_category       ON treatment_procedure(service_category_id);
CREATE INDEX idx_proc_material       ON treatment_procedure(material_option_id);
CREATE INDEX idx_proc_status         ON treatment_procedure(status);
CREATE INDEX idx_decision_procedure  ON procedure_decision(procedure_id, decided_at);
CREATE INDEX idx_discount_plan       ON discount_proposal(treatment_plan_id);
CREATE INDEX idx_special_plan        ON special_procedure_proposal(treatment_plan_id);


-- =============================================================================
-- TRIGGERS
-- =============================================================================

-- The material rules cross tables, so a CHECK cannot express them.
CREATE TRIGGER trg_proc_material_required BEFORE INSERT ON treatment_procedure
BEGIN
    SELECT RAISE(ABORT, 'this service requires a material choice')
    WHERE NEW.material_option_id IS NULL
      AND (SELECT requires_material_choice FROM service_category WHERE id = NEW.service_category_id) = 1;

    SELECT RAISE(ABORT, 'material does not belong to this service category')
    WHERE NEW.material_option_id IS NOT NULL
      AND (SELECT service_category_id FROM material_option WHERE id = NEW.material_option_id)
          <> NEW.service_category_id;
END;

-- The decision log is APPEND-ONLY. A clinical record must show what was
-- believed at the time; an error is corrected by a further decision, never by
-- rewriting one.
CREATE TRIGGER trg_decision_no_update BEFORE UPDATE ON procedure_decision
BEGIN
    SELECT RAISE(ABORT, 'procedure_decision is append-only: it cannot be updated');
END;

CREATE TRIGGER trg_decision_no_delete BEFORE DELETE ON procedure_decision
BEGIN
    SELECT RAISE(ABORT, 'procedure_decision is append-only: it cannot be deleted');
END;

-- from_status must match where the procedure actually is, so the log is a
-- coherent chain rather than a set of disconnected claims.
CREATE TRIGGER trg_decision_chain BEFORE INSERT ON procedure_decision
BEGIN
    SELECT RAISE(ABORT, 'from_status does not match the procedure''s current status')
    WHERE NEW.from_status IS NOT (
        SELECT CASE WHEN EXISTS (SELECT 1 FROM procedure_decision d WHERE d.procedure_id = NEW.procedure_id)
                    THEN (SELECT status FROM treatment_procedure WHERE id = NEW.procedure_id)
                    ELSE NULL END);

    -- only these transitions are clinically meaningful
    SELECT RAISE(ABORT, 'illegal status transition')
    WHERE NOT (
        (NEW.from_status IS NULL     AND NEW.to_status = 'Proposed') OR
        (NEW.from_status = 'Proposed'   AND NEW.to_status IN ('Accepted','Declined','Skipped')) OR
        (NEW.from_status = 'Declined'   AND NEW.to_status = 'Proposed') OR   -- re-proposal
        (NEW.from_status = 'Accepted'   AND NEW.to_status IN ('Scheduled','Skipped')) OR
        (NEW.from_status = 'Scheduled'  AND NEW.to_status IN ('InProgress','Accepted','Skipped')) OR
        (NEW.from_status = 'InProgress' AND NEW.to_status IN ('Completed','Skipped')));
END;

-- treatment_procedure.status is a CACHE of this log's head.
CREATE TRIGGER trg_decision_applies AFTER INSERT ON procedure_decision
BEGIN
    UPDATE treatment_procedure
    SET status = NEW.to_status,
        completed_date = CASE WHEN NEW.to_status = 'Completed'
                              THEN date(NEW.decided_at) ELSE NULL END
    WHERE id = NEW.procedure_id;
END;


-- =============================================================================
-- VIEWS
-- =============================================================================

-- One line per procedure: what it is, who it is for, and where it stands.
CREATE VIEW v_plan_detail AS
SELECT tp.id AS plan_id, pu.full_name AS patient, du.full_name AS lead_doctor,
       tp.title, tp.status AS plan_status, tp.payment_mode,
       pr.sequence, sc.name AS service, COALESCE(mo.name, '—') AS material,
       pr.status AS procedure_status, pr.planned_sessions, pr.completed_date
FROM treatment_plan tp
JOIN patient_profile pp ON pp.id = tp.patient_id
JOIN app_user pu        ON pu.id = pp.user_id
JOIN staff_profile sd   ON sd.id = tp.doctor_id
JOIN app_user du        ON du.id = sd.user_id
LEFT JOIN treatment_procedure pr ON pr.treatment_plan_id = tp.id
LEFT JOIN service_category sc    ON sc.id = pr.service_category_id
LEFT JOIN material_option mo     ON mo.id = pr.material_option_id
ORDER BY tp.id, pr.sequence;

-- The full decision trail for a procedure, in order.
CREATE VIEW v_procedure_trail AS
SELECT d.procedure_id, sc.name AS service,
       COALESCE(d.from_status,'—') || ' -> ' || d.to_status AS transition,
       u.full_name AS decided_by, d.decided_at,
       COALESCE(d.reason,'') AS reason,
       CASE d.risk_explained WHEN 1 THEN 'yes' WHEN 0 THEN 'no' ELSE '' END AS risk_explained
FROM procedure_decision d
JOIN treatment_procedure pr ON pr.id = d.procedure_id
JOIN service_category sc    ON sc.id = pr.service_category_id
JOIN app_user u             ON u.id = d.decided_by
ORDER BY d.procedure_id, d.decided_at;

-- Everything waiting on the manager, both proposal types in one queue.
CREATE VIEW v_pending_approvals AS
SELECT 'SpecialProcedure' AS kind, sp.id, tp.title AS plan,
       pu.full_name AS patient, sc.name AS detail, sp.estimated_cost AS amount, u.full_name AS proposed_by
FROM special_procedure_proposal sp
JOIN treatment_plan tp   ON tp.id = sp.treatment_plan_id
JOIN patient_profile pp  ON pp.id = tp.patient_id
JOIN app_user pu         ON pu.id = pp.user_id
JOIN service_category sc ON sc.id = sp.service_category_id
JOIN app_user u          ON u.id = sp.proposed_by
WHERE sp.status = 'Pending'
UNION ALL
SELECT 'Discount', dp.id, tp.title, pu.full_name, dp.reason, dp.discount_value, u.full_name
FROM discount_proposal dp
JOIN treatment_plan tp  ON tp.id = dp.treatment_plan_id
JOIN patient_profile pp ON pp.id = tp.patient_id
JOIN app_user pu        ON pu.id = pp.user_id
JOIN app_user u         ON u.id = dp.proposed_by
WHERE dp.status = 'Pending';

-- Informed refusal: work the patient declined, with the reason on record.
CREATE VIEW v_declined_work AS
SELECT pu.full_name AS patient, sc.name AS service, d.decided_at AS declined_at,
       d.reason, CASE d.risk_explained WHEN 1 THEN 'yes' ELSE 'NO' END AS risk_explained,
       u.full_name AS recorded_by
FROM treatment_procedure pr
JOIN procedure_decision d ON d.procedure_id = pr.id AND d.to_status = 'Declined'
JOIN treatment_plan tp    ON tp.id = pr.treatment_plan_id
JOIN patient_profile pp   ON pp.id = tp.patient_id
JOIN app_user pu          ON pu.id = pp.user_id
JOIN service_category sc  ON sc.id = pr.service_category_id
JOIN app_user u           ON u.id = d.decided_by
ORDER BY d.decided_at DESC;
