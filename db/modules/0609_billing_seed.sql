-- =============================================================================
-- KPX — MODULE 6 seed: Billing
--
-- Invoices are built the way the clinic actually builds them:
--   1. open a DRAFT (no legal number — a draft is not an invoice)
--   2. add the lines
--   3. ISSUE it, which takes a number and validates the figures
--   4. take payment, which settles the status
--
-- The cases that matter:
--   · inv-04 — MIXED VAT with a voucher. Whitening at 10% and a scaling at 0%,
--     XASH 10% off, allocated PRO-RATA before VAT. Charging VAT on the gross
--     would overcharge by 30,000.
--   · inv-05 — a THREE-SURFACE filling billed PerSurface at quantity 3, with an
--     approved 10% discount proposal. Left PartiallyPaid.
--   · inv-01 — a failed extraction: credit line, refund paid Out, free rework.
-- =============================================================================

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- ============================ inv-01 — Hoàng Văn Tuấn, PerSession ============
INSERT INTO invoice (id, treatment_plan_id, patient_id, status, due_date) VALUES
('inv-01','tp-01','pp-01','Draft','2026-09-27');

INSERT INTO invoice_line (id, invoice_id, session_id, description, tooth_codes, unit_price, quantity, discount_amount, vat_rate, vat_amount, line_total, issued_at) VALUES
('il-01','inv-01','ps-01','Consultation',                NULL, 200000,1,0,0,0, 200000,'2026-08-25 09:50:00'),
('il-02','inv-01','ps-02','Tooth extraction — tooth 46', '46',1200000,1,0,0,0,1200000,'2026-08-28 15:00:00');

UPDATE invoice SET status='Issued', invoice_serial='1C26TAA', invoice_number='0000001', issued_at='2026-08-28 15:00:00' WHERE id='inv-01';

INSERT INTO payment (id, invoice_id, direction, amount, method, paid_at, received_by, reference_number, notes) VALUES
('pay-01','inv-01','In', 200000,'Cash',        '2026-08-25 09:55:00','u-rec01',NULL,'Consultation settled on the day.'),
('pay-02','inv-01','In',1200000,'BankTransfer','2026-08-28 15:30:00','u-rec01','VCB-20260828-0417','Extraction settled.');

-- ============================ inv-02 — Lan Anh, UPFRONT ======================
-- Upfront bills the PROCEDURE, not a session: money before the work.
INSERT INTO invoice (id, treatment_plan_id, patient_id, status, due_date) VALUES
('inv-02','tp-02','pp-02','Draft','2026-08-25');

INSERT INTO invoice_line (id, invoice_id, procedure_id, description, unit_price, quantity, discount_amount, vat_rate, vat_amount, line_total, issued_at) VALUES
('il-03','inv-02','pr-05','Consultation and orthodontic records',200000,1,0,0,0,200000,'2026-08-25 10:10:00');

UPDATE invoice SET status='Issued', invoice_serial='1C26TAA', invoice_number='0000002', issued_at='2026-08-25 10:10:00' WHERE id='inv-02';

INSERT INTO payment (id, invoice_id, direction, amount, method, paid_at, received_by, reference_number, notes) VALUES
('pay-03','inv-02','In',200000,'Card','2026-08-25 10:15:00','u-rec01','POS-771204','Paid before records were taken.');

-- ============================ inv-03 — Lý Văn Hùng ==========================
INSERT INTO invoice (id, treatment_plan_id, patient_id, status, due_date) VALUES
('inv-03','tp-04','pp-04','Draft','2026-09-02');

INSERT INTO invoice_line (id, invoice_id, session_id, description, unit_price, quantity, discount_amount, vat_rate, vat_amount, line_total, issued_at) VALUES
('il-04','inv-03','ps-06','Scale and polish — full mouth',500000,1,0,0,0,500000,'2026-09-02 14:35:00');

UPDATE invoice SET status='Issued', invoice_serial='1C26TAA', invoice_number='0000003', issued_at='2026-09-02 14:35:00' WHERE id='inv-03';

INSERT INTO payment (id, invoice_id, direction, amount, method, paid_at, received_by, notes) VALUES
('pay-04','inv-03','In',500000,'Cash','2026-09-02 14:40:00','u-rec01',NULL);

-- ============================ inv-04 — THE MIXED-VAT CASE ===================
--   Whitening 3,000,000 @ 10% VAT (cosmetic) + Scaling 500,000 @ 0% (medical)
--   XASH, 10% of 3,500,000 = 350,000, ALLOCATED PRO-RATA:
--     whitening 3,000,000/3,500,000 x 350,000 = 300,000
--     scaling   absorbs the remainder         =  50,000
--   VAT then falls on the NET of each line: 270,000 and 0.
--   Total = 3,500,000 - 350,000 + 270,000 = 3,420,000
--   VAT on the gross would have billed 3,450,000 — 30,000 too much.
INSERT INTO invoice (id, treatment_plan_id, patient_id, status, due_date, promotion_id, promotion_code) VALUES
('inv-04','tp-05','pp-05','Draft','2026-09-01','pr-01','XASH');

INSERT INTO invoice_line (id, invoice_id, session_id, description, unit_price, quantity, discount_amount, vat_rate, vat_amount, line_total, issued_at) VALUES
('il-05','inv-04','ps-07','In-clinic teeth whitening',3000000,1,300000,10,270000,3000000,'2026-09-01 16:40:00'),
('il-06','inv-04','ps-08','Scale and polish',           500000,1, 50000, 0,     0, 500000,'2026-09-01 16:40:00');

UPDATE invoice SET status='Issued', invoice_serial='1C26TAA', invoice_number='0000004', issued_at='2026-09-01 16:40:00' WHERE id='inv-04';

INSERT INTO payment (id, invoice_id, direction, amount, method, paid_at, received_by, reference_number, notes) VALUES
('pay-05','inv-04','In',3420000,'BankTransfer','2026-09-01 16:45:00','u-rec01','TCB-20260901-0088','Staff rate, XASH voucher applied.');

-- ============================ inv-05 — PerSurface at quantity 3 =============
-- A three-surface (MOD) composite on tooth 37. pricing_basis is PerSurface, so
-- the unit price is charged three times. dp-01 is an approved 10% discount.
--   3 x 800,000 = 2,400,000, less 240,000 = 2,160,000. Filling is zero-rated.
-- Partly paid, so the invoice sits PartiallyPaid.
INSERT INTO invoice (id, treatment_plan_id, patient_id, status, due_date, discount_proposal_id) VALUES
('inv-05','tp-03','pp-03','Draft','2026-10-03','dp-01');

INSERT INTO invoice_line (id, invoice_id, session_id, description, tooth_codes, surfaces, unit_price, quantity, discount_amount, vat_rate, vat_amount, line_total, issued_at) VALUES
('il-08','inv-05','ps-09','Composite filling — tooth 37, three surfaces','37','MOD',800000,3,240000,0,0,2400000,'2026-09-03 10:35:00');

UPDATE invoice SET status='Issued', invoice_serial='1C26TAA', invoice_number='0000005', issued_at='2026-09-03 10:35:00' WHERE id='inv-05';

INSERT INTO payment (id, invoice_id, direction, amount, method, paid_at, received_by, notes) VALUES
('pay-07','inv-05','In',1000000,'Cash','2026-09-03 10:40:00','u-rec01','Part payment; balance agreed for the next visit.');

-- ============================ THE FAILED EXTRACTION =========================
-- Tuấn returns four days later in pain. A retained root fragment is found —
-- the clinic's own technique. Refund the extraction AND redo it free.
INSERT INTO treatment_failure (id, procedure_id, tooth_code, reported_at, patient_account, clinical_finding, examined_by, status, fault_attribution, remedy, determined_by, determined_at, determination_note) VALUES
('tf-01','pr-02','46','2026-09-01 09:00:00',
 'Ongoing pain and swelling at the extraction site four days after the tooth was removed.',
 'Periapical shows a retained mesial root fragment approximately 4mm. Socket inflamed.',
 'u-doc04','Resolved','ClinicTechnique','Both','u-mgr01','2026-09-01 11:30:00',
 'Fragment left at the original extraction. Clinic technique. Refund the extraction fee and remove the fragment at no charge. Charge the loss back to the operating dentist.');

-- the credit line reverses the charge; the refund follows it
INSERT INTO invoice_line (id, invoice_id, procedure_id, description, tooth_codes, unit_price, quantity, discount_amount, vat_rate, vat_amount, line_total, credits_line_id, issued_at) VALUES
('il-07','inv-01','pr-02','CREDIT — extraction refunded, retained root fragment (tf-01)','46',1200000,1,0,0,0,-1200000,'il-02','2026-09-01 11:45:00');

INSERT INTO payment (id, invoice_id, direction, amount, method, paid_at, received_by, reference_number, notes) VALUES
('pay-06','inv-01','Out',1200000,'BankTransfer','2026-09-01 12:00:00','u-rec01','VCB-20260901-0902','Refund of extraction fee, tf-01.');

-- the free rework: a real procedure that bills nothing
INSERT INTO treatment_procedure (id, treatment_plan_id, service_category_id, sequence, planned_sessions, doctor_note, remedy_for_failure_id) VALUES
('pr-13','tp-01','sc-04',5,1,'Surgical removal of the retained root fragment. No charge — clinic remedy for tf-01.','tf-01');

INSERT INTO procedure_decision (id, procedure_id, from_status, to_status, decided_by, decided_at, note) VALUES
('d-45','pr-13',NULL,      'Proposed','u-doc04','2026-09-01 11:40:00','Remedy for tf-01, at no charge.'),
('d-46','pr-13','Proposed','Accepted','u-rec01','2026-09-01 11:45:00','Patient accepted the free rework.');

INSERT INTO procedure_tooth (id, procedure_id, tooth_code, addresses_condition_id, note) VALUES
('pt-13','pr-13','46','tc-02','Retained fragment from the original extraction.');

COMMIT;
