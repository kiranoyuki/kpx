-- =============================================================================
-- KPX — MODULE 6: Billing
-- treatment_failure · invoice · invoice_line · payment
-- plus the ALTER that closes the one circular dependency
--
-- Source of truth: Design/core-entities/entities.md
-- Build order:     Design/build-plan.md  (module 6 of 9; depends on 1,2,4,5)
-- =============================================================================

PRAGMA foreign_keys = ON;


-- -----------------------------------------------------------------------------
-- Completed work that failed. One case file carrying the claim, the manager's
-- fault judgment, the remedy, and the link to whatever the staff are charged.
-- -----------------------------------------------------------------------------
CREATE TABLE treatment_failure (
    id                  TEXT PRIMARY KEY,
    procedure_id        TEXT NOT NULL REFERENCES treatment_procedure(id),
    tooth_code          TEXT REFERENCES tooth(code),
    reported_at         TEXT NOT NULL DEFAULT (datetime('now')),
    patient_account     TEXT NOT NULL,          -- what the patient says happened
    clinical_finding    TEXT,                   -- what the examining clinician found
    examined_by         TEXT NOT NULL REFERENCES app_user(id),
    status              TEXT NOT NULL DEFAULT 'Reported'
                            CHECK (status IN ('Reported','UnderReview','Resolved','Rejected')),
    -- the gate on refunding. A recorded human judgment, never an automatic rule.
    fault_attribution   TEXT CHECK (fault_attribution IS NULL OR fault_attribution IN (
                            'ClinicTechnique','MaterialDefect','PatientFactor','Inconclusive')),
    remedy              TEXT CHECK (remedy IS NULL OR remedy IN ('Refund','FreeRework','Both','None')),
    determined_by       TEXT REFERENCES app_user(id),
    determined_at       TEXT,
    determination_note  TEXT,

    CONSTRAINT ck_failure_resolved_complete CHECK (
        status <> 'Resolved' OR (fault_attribution IS NOT NULL AND remedy IS NOT NULL
                                 AND determined_by IS NOT NULL AND determined_at IS NOT NULL))
);


-- -----------------------------------------------------------------------------
-- CLOSING THE CIRCULAR DEPENDENCY
--
-- treatment_procedure.remedy_for_failure_id -> treatment_failure -> back again.
-- Module 4 could not declare this forward FK: CREATE TABLE accepts a forward
-- reference, but with foreign_keys = ON the first INSERT fails with "no such
-- table", even inserting NULL. Disabling the pragma would defeat the point.
--
-- ALTER TABLE ADD COLUMN may carry a REFERENCES clause, and enforces normally
-- afterwards. When set, the procedure is FREE REWORK: it produces no invoice
-- line, and therefore no commission.
-- -----------------------------------------------------------------------------
ALTER TABLE treatment_procedure
    ADD COLUMN remedy_for_failure_id TEXT REFERENCES treatment_failure(id);


-- -----------------------------------------------------------------------------
-- A financial document. No longer 1:1 with a plan — a long course bills in
-- stages. Totals are DERIVED from the lines by trigger, never asserted.
-- -----------------------------------------------------------------------------
CREATE TABLE invoice (
    id                   TEXT PRIMARY KEY,
    treatment_plan_id    TEXT NOT NULL REFERENCES treatment_plan(id),   -- deliberately not UNIQUE
    patient_id           TEXT NOT NULL REFERENCES patient_profile(id),
    -- Vietnamese legal numbering: taken on ISSUE, never while Draft, never reused
    invoice_serial       TEXT,                  -- ký hiệu hóa đơn
    invoice_number       TEXT,                  -- số hóa đơn
    tax_authority_code   TEXT,                  -- returned on e-invoice registration
    issued_at            TEXT,
    subtotal             NUMERIC NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
    discount_amount      NUMERIC NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    vat_total            NUMERIC NOT NULL DEFAULT 0 CHECK (vat_total >= 0),
    total                NUMERIC NOT NULL DEFAULT 0,
    status               TEXT NOT NULL DEFAULT 'Draft' CHECK (status IN (
                             'Draft','Issued','PartiallyPaid','Paid','Overdue','Voided')),
    due_date             TEXT,
    -- at most ONE discount source: a voucher code OR an approved proposal
    promotion_id         TEXT REFERENCES promotion(id),
    promotion_code       TEXT,                  -- snapshot as redeemed
    discount_proposal_id TEXT REFERENCES discount_proposal(id),

    CONSTRAINT ck_inv_one_discount_source CHECK (
        promotion_id IS NULL OR discount_proposal_id IS NULL),
    -- A draft carries NO number; anything else carries a COMPLETE one. Stating
    -- this as an equality was a bug: it only forced the three to be NULL
    -- together, so an Issued invoice with issued_at but no number slipped past.
    CONSTRAINT ck_inv_number_only_when_issued CHECK (
        CASE WHEN status = 'Draft'
             THEN invoice_number IS NULL     AND invoice_serial IS NULL     AND issued_at IS NULL
             ELSE invoice_number IS NOT NULL AND invoice_serial IS NOT NULL AND issued_at IS NOT NULL
        END),
    CONSTRAINT ck_inv_total CHECK (total = subtotal - discount_amount + vat_total)
);

-- A number is never reused: a Voided invoice keeps its own.
CREATE UNIQUE INDEX uq_invoice_number ON invoice(invoice_serial, invoice_number)
    WHERE invoice_number IS NOT NULL;


-- One billable item, FROZEN when the invoice is issued.
CREATE TABLE invoice_line (
    id               TEXT PRIMARY KEY,
    invoice_id       TEXT NOT NULL REFERENCES invoice(id) ON DELETE CASCADE,
    -- exactly one source: a completed session (PerSession) or a whole
    -- accepted procedure (Upfront)
    session_id       TEXT REFERENCES procedure_session(id),
    procedure_id     TEXT REFERENCES treatment_procedure(id),
    -- every descriptive field is a SNAPSHOT: clinical records get amended, and
    -- a bill already issued must not move when a tooth number is corrected
    description      TEXT NOT NULL,
    tooth_codes      TEXT,
    surfaces         TEXT,
    unit_price       NUMERIC NOT NULL,
    quantity         NUMERIC NOT NULL DEFAULT 1 CHECK (quantity > 0),
    discount_amount  NUMERIC NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    vat_rate         NUMERIC NOT NULL DEFAULT 0 CHECK (vat_rate BETWEEN 0 AND 100),
    vat_amount       NUMERIC NOT NULL DEFAULT 0,
    line_total       NUMERIC NOT NULL,
    credits_line_id  TEXT REFERENCES invoice_line(id),
    issued_at        TEXT NOT NULL DEFAULT (datetime('now')),

    CONSTRAINT ck_line_one_source CHECK (
        (session_id IS NULL) <> (procedure_id IS NULL)),
    -- VAT is charged on the DISCOUNTED amount, never on the gross. Charging it
    -- before the discount overcharges the patient and misstates the tax.
    CONSTRAINT ck_line_vat_after_discount CHECK (
        vat_amount = CAST(ROUND((line_total - discount_amount) * vat_rate / 100.0) AS INTEGER)),
    CONSTRAINT ck_line_discount_within CHECK (
        line_total < 0 OR discount_amount <= line_total),
    -- a line must agree with its own arithmetic. Without this, unit_price 100
    -- at quantity 3 could be billed as anything at all.
    CONSTRAINT ck_line_total_is_price_times_qty CHECK (
        line_total = CASE WHEN credits_line_id IS NULL
                          THEN unit_price * quantity
                          ELSE -(unit_price * quantity) END)
);

-- A completed session is billed exactly once.
CREATE UNIQUE INDEX uq_line_session ON invoice_line(session_id) WHERE session_id IS NOT NULL;


CREATE TABLE payment (
    id               TEXT PRIMARY KEY,
    invoice_id       TEXT NOT NULL REFERENCES invoice(id) ON DELETE CASCADE,
    -- In is money received; Out is a refund returned to the patient
    direction        TEXT NOT NULL DEFAULT 'In' CHECK (direction IN ('In','Out')),
    amount           NUMERIC NOT NULL CHECK (amount > 0),   -- direction carries the sign
    method           TEXT NOT NULL CHECK (method IN ('Cash','BankTransfer','Card','Other')),
    paid_at          TEXT NOT NULL DEFAULT (datetime('now')),
    received_by      TEXT NOT NULL REFERENCES app_user(id),
    reference_number TEXT,
    notes            TEXT
);


CREATE INDEX idx_failure_procedure ON treatment_failure(procedure_id);
CREATE INDEX idx_failure_status    ON treatment_failure(status);
CREATE INDEX idx_invoice_plan      ON invoice(treatment_plan_id);
CREATE INDEX idx_invoice_patient   ON invoice(patient_id);
CREATE INDEX idx_invoice_status    ON invoice(status);
CREATE INDEX idx_line_invoice      ON invoice_line(invoice_id);
CREATE INDEX idx_line_procedure    ON invoice_line(procedure_id);
CREATE INDEX idx_payment_invoice   ON payment(invoice_id);
CREATE INDEX idx_payment_when      ON payment(paid_at);

-- =============================================================================
-- VIEWS
-- =============================================================================

-- What each invoice owes, netting refunds against receipts.
CREATE VIEW v_invoice_balance AS
SELECT i.id AS invoice_id,
       COALESCE(i.invoice_serial || '-' || i.invoice_number, '(draft)') AS legal_number,
       u.full_name AS patient, tp.title AS plan,
       i.subtotal, i.discount_amount AS discount, i.vat_total AS vat, i.total,
       COALESCE(SUM(CASE WHEN p.direction='In'  THEN p.amount END),0) AS received,
       COALESCE(SUM(CASE WHEN p.direction='Out' THEN p.amount END),0) AS refunded,
       i.total - COALESCE(SUM(CASE WHEN p.direction='In' THEN p.amount ELSE -p.amount END),0) AS balance_due,
       i.status
FROM invoice i
JOIN patient_profile pp ON pp.id = i.patient_id
JOIN app_user u         ON u.id = pp.user_id
JOIN treatment_plan tp  ON tp.id = i.treatment_plan_id
LEFT JOIN payment p     ON p.invoice_id = i.id
GROUP BY i.id;

-- The itemised bill a patient actually receives, with the tax working shown.
CREATE VIEW v_invoice_detail AS
SELECT i.id AS invoice_id, u.full_name AS patient,
       l.description, COALESCE(l.tooth_codes,'—') AS teeth, COALESCE(l.surfaces,'—') AS surfaces,
       l.unit_price, l.quantity, l.line_total AS gross,
       l.discount_amount AS discount, (l.line_total - l.discount_amount) AS net,
       l.vat_rate || '%' AS vat_rate, l.vat_amount AS vat,
       (l.line_total - l.discount_amount + l.vat_amount) AS line_charge,
       CASE WHEN l.credits_line_id IS NOT NULL THEN 'credit' ELSE '' END AS kind
FROM invoice_line l
JOIN invoice i           ON i.id = l.invoice_id
JOIN patient_profile pp  ON pp.id = i.patient_id
JOIN app_user u          ON u.id = pp.user_id
ORDER BY i.id, l.issued_at, l.id;

-- Proof the discount was allocated before VAT, per invoice.
CREATE VIEW v_vat_check AS
SELECT i.id AS invoice_id,
       SUM(l.line_total)                                       AS gross,
       SUM(l.discount_amount)                                  AS discount,
       SUM(l.vat_amount)                                       AS vat_charged,
       SUM(CAST(ROUND(l.line_total * l.vat_rate / 100.0) AS INTEGER)) AS vat_if_charged_on_gross,
       SUM(CAST(ROUND(l.line_total * l.vat_rate / 100.0) AS INTEGER)) - SUM(l.vat_amount) AS overcharge_avoided
FROM invoice_line l JOIN invoice i ON i.id = l.invoice_id
GROUP BY i.id HAVING SUM(l.discount_amount) > 0;

-- Failed work, the judgment, and everything that followed from it.
CREATE VIEW v_treatment_failure AS
SELECT f.id, u.full_name AS patient, sc.name AS failed_service, f.tooth_code AS tooth,
       f.reported_at, f.status, f.fault_attribution, f.remedy,
       m.full_name AS determined_by, f.determination_note,
       (SELECT COUNT(*) FROM treatment_procedure r WHERE r.remedy_for_failure_id = f.id) AS rework_procedures,
       (SELECT COALESCE(SUM(-l.line_total),0) FROM invoice_line l
        WHERE l.credits_line_id IS NOT NULL AND l.procedure_id = f.procedure_id) AS credited
FROM treatment_failure f
JOIN treatment_procedure pr ON pr.id = f.procedure_id
JOIN treatment_plan tp      ON tp.id = pr.treatment_plan_id
JOIN patient_profile pp     ON pp.id = tp.patient_id
JOIN app_user u             ON u.id = pp.user_id
JOIN service_category sc    ON sc.id = pr.service_category_id
LEFT JOIN app_user m        ON m.id = f.determined_by;


-- =============================================================================
-- TRIGGERS ADDED AFTER REVIEW
--
-- Three gaps an audit of this module turned up, all of which let wrong data in:
--   1. invoice.status never moved when money arrived, so a fully settled
--      invoice still read PartiallyPaid.
--   2. A line's total was not tied to its own unit_price x quantity.  (fixed
--      above as ck_line_total_is_price_times_qty)
--   3. An invoice could name a 10% voucher and then discount any amount at all.
-- =============================================================================
