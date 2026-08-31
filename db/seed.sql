-- =============================================================================
-- KPX — mock data for the "patient becomes revenue" spine
--
-- Identity lifecycle covered end to end:
--   6 staff        Active, CCCD on file, all can log in
--   4 patients     Active, CCCD on file, can log in
--   2 patients     Active, CCCD on file, NO login  (walk-ins, verified in person)
--   2 people       Provisional, no CCCD, no login  (booked online, not yet arrived)
--
-- Six revenue cases:
--   Hoàng Văn Tuấn      implant, in progress      invoice PartiallyPaid
--   Nguyễn Thị Lan Anh  orthodontics, in progress invoice PartiallyPaid + discount
--   Trần Minh Đức       crown, 2025               invoice Paid, OLD price version
--   Phạm Thị Ngọc       root canal + crown        invoice PartiallyPaid, walk-in
--   Lý Văn Hùng         consultation only         invoice Paid, walk-in
--   Đặng Thu Trang      new patient scaling       invoice Paid, referral
--
-- CCCD values follow the real format: 079 (TP.HCM) + century/gender digit
-- + 2-digit birth year + 6 digits. They are fabricated, not real numbers.
-- Money is VND. password_hash values are placeholders, not real hashes.
-- Run after schema.sql.
-- =============================================================================

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- -----------------------------------------------------------------------------
-- People — staff. The manager self-verifies: bootstrap case, the owner set up
-- the system before anyone else existed to check her documents.
-- -----------------------------------------------------------------------------
INSERT INTO app_user
    (id, full_name, phone, email, date_of_birth, address, national_id,
     status, verified_at, verified_by, password_hash, role, created_at) VALUES
('u-mgr01', 'Nguyễn Thị Hương', '0901234501', 'huong.nguyen@kpx.vn', '1985-03-14', '12 Nguyễn Huệ, Quận 1, TP.HCM',   '079185001234', 'Active', '2024-06-01 08:00:00', 'u-mgr01', '$2b$12$seed.placeholder.mgr01', 'Manager',      '2024-06-01 08:00:00'),
('u-doc01', 'Trần Văn Minh',    '0901234502', 'bs.minh@kpx.vn',      '1980-11-02', '45 Lê Lợi, Quận 1, TP.HCM',       '079080004471', 'Active', '2024-06-01 08:30:00', 'u-mgr01', '$2b$12$seed.placeholder.doc01', 'Doctor',       '2024-06-01 08:30:00'),
('u-doc02', 'Lê Thị Mai',       '0901234503', 'bs.mai@kpx.vn',       '1988-07-21', '78 Hai Bà Trưng, Quận 3, TP.HCM', '079188005218', 'Active', '2024-09-15 08:00:00', 'u-mgr01', '$2b$12$seed.placeholder.doc02', 'Doctor',       '2024-09-15 08:00:00'),
('u-rec01', 'Phạm Thu Hà',      '0901234504', 'letan.ha@kpx.vn',     '1996-01-30', '23 Võ Văn Tần, Quận 3, TP.HCM',   '079196007742', 'Active', '2024-06-10 08:00:00', 'u-mgr01', '$2b$12$seed.placeholder.rec01', 'Receptionist', '2024-06-10 08:00:00'),
('u-ast01', 'Đỗ Văn Nam',       '0901234505', 'trolyi.nam@kpx.vn',   '1998-05-18', '9 Cách Mạng Tháng 8, Quận 10',    '079098003310', 'Active', '2024-07-01 08:00:00', 'u-mgr01', '$2b$12$seed.placeholder.ast01', 'Assistant',    '2024-07-01 08:00:00'),
('u-acc01', 'Vũ Thị Lan',       '0901234506', 'ketoan.lan@kpx.vn',   '1990-09-09', '56 Điện Biên Phủ, Bình Thạnh',    '079190006654', 'Active', '2024-06-20 08:00:00', 'u-mgr01', '$2b$12$seed.placeholder.acc01', 'Accountant',   '2024-06-20 08:00:00');

-- -----------------------------------------------------------------------------
-- People — patients. All Active: each was verified in person on arrival.
-- u-pat04 and u-pat05 are walk-ins: verified, CCCD on file, but no email and
-- no password_hash — they are real patients who simply cannot log in.
-- -----------------------------------------------------------------------------
INSERT INTO app_user
    (id, full_name, phone, email, date_of_birth, address, national_id,
     status, verified_at, verified_by, password_hash, role, created_at) VALUES
('u-pat01', 'Hoàng Văn Tuấn',     '0912000101', 'tuan.hoang@gmail.com',    '1979-04-12', '102 Trần Hưng Đạo, Quận 5, TP.HCM', '079079101122', 'Active', '2026-03-02 09:15:00', 'u-rec01', '$2b$12$seed.placeholder.pat01', 'Patient', '2026-02-26 09:50:00'),
('u-pat02', 'Nguyễn Thị Lan Anh', '0912000201', 'lananh.nguyen@gmail.com', '2003-08-25', '17 Nguyễn Đình Chiểu, Quận 3',      '079303202233', 'Active', '2026-01-12 10:00:00', 'u-rec01', '$2b$12$seed.placeholder.pat02', 'Patient', '2026-01-05 16:10:00'),
('u-pat03', 'Trần Minh Đức',      '0912000301', 'duc.tran@gmail.com',      '1991-12-03', '88 Lý Thường Kiệt, Tân Bình',       '079091303344', 'Active', '2025-11-10 14:30:00', 'u-rec01', '$2b$12$seed.placeholder.pat03', 'Patient', '2025-11-10 14:30:00'),
('u-pat04', 'Phạm Thị Ngọc',      '0912000401', NULL,                      '1986-06-19', '210 Nguyễn Trãi, Quận 5, TP.HCM',   '079186404455', 'Active', '2026-07-06 11:20:00', 'u-rec01', NULL,                           'Patient', '2026-07-06 11:20:00'),
('u-pat05', 'Lý Văn Hùng',        '0912000501', NULL,                      '1972-02-28', '34 Pasteur, Quận 1, TP.HCM',        '079072505566', 'Active', '2026-08-03 15:40:00', 'u-rec01', NULL,                           'Patient', '2026-08-03 15:40:00'),
('u-pat06', 'Đặng Thu Trang',     '0912000601', 'trang.dang@gmail.com',    '1999-10-07', '5 Nguyễn Thị Minh Khai, Quận 1',    '079199606677', 'Active', '2026-08-17 08:45:00', 'u-rec01', '$2b$12$seed.placeholder.pat06', 'Patient', '2026-08-14 13:05:00');

-- -----------------------------------------------------------------------------
-- People — Provisional. Booked online, never arrived, so never verified:
-- no CCCD, no credentials, and deliberately NO patient_profile row.
-- These are the rows v_reschedule_followup chases.
-- -----------------------------------------------------------------------------
INSERT INTO app_user
    (id, full_name, phone, email, date_of_birth, address, national_id,
     status, verified_at, verified_by, password_hash, role, created_at) VALUES
('u-prv01', 'Bùi Thị Hạnh',   '0912000701', 'hanh.bui@gmail.com',  '1994-04-02', NULL, NULL, 'Provisional', NULL, NULL, NULL, 'Patient', '2026-08-26 20:14:00'),
('u-prv02', 'Ngô Quang Huy',  '0912000801', 'huy.ngo@gmail.com',   '1987-09-16', NULL, NULL, 'Provisional', NULL, NULL, NULL, 'Patient', '2026-08-11 21:47:00');

-- -----------------------------------------------------------------------------
-- Employment records
-- -----------------------------------------------------------------------------
INSERT INTO staff_profile (id, user_id, join_date, specialty, license_number, wage_type, hourly_rate) VALUES
('st-mgr01', 'u-mgr01', '2024-06-01', NULL,           NULL,          'Monthly', NULL),
('st-doc01', 'u-doc01', '2024-06-01', 'Implantology', 'VN-DDS-4471', 'Monthly', NULL),
('st-doc02', 'u-doc02', '2024-09-15', 'Orthodontics', 'VN-DDS-5218', 'Monthly', NULL),
('st-rec01', 'u-rec01', '2024-06-10', NULL,           NULL,          'Monthly', NULL),
('st-ast01', 'u-ast01', '2024-07-01', NULL,           NULL,          'Hourly',  45000),
('st-acc01', 'u-acc01', '2024-06-20', NULL,           NULL,          'Monthly', NULL);

-- -----------------------------------------------------------------------------
-- Care records — created on arrival, one per verified patient
-- -----------------------------------------------------------------------------
INSERT INTO patient_profile (id, user_id, emergency_contact, referral_source, created_by, created_at) VALUES
('pp-01', 'u-pat01', 'Hoàng Thị Yến — 0912000102',  'Google search',      'u-rec01', '2026-03-02 09:15:00'),
('pp-02', 'u-pat02', 'Nguyễn Văn Bảo — 0912000202', 'Referral — patient', 'u-rec01', '2026-01-12 10:00:00'),
('pp-03', 'u-pat03', 'Trần Thị Hoa — 0912000302',   'Walk-in',            'u-rec01', '2025-11-10 14:30:00'),
('pp-04', 'u-pat04', 'Phạm Văn Sơn — 0912000402',   'Facebook ad',        'u-rec01', '2026-07-06 11:20:00'),
('pp-05', 'u-pat05', NULL,                          'Walk-in',            'u-rec01', '2026-08-03 15:40:00'),
('pp-06', 'u-pat06', 'Đặng Văn Kiên — 0912000602',  'Referral — patient', 'u-rec01', '2026-08-17 08:45:00');

-- -----------------------------------------------------------------------------
-- Service catalog
-- -----------------------------------------------------------------------------
INSERT INTO service_category (id, name, description, is_special, is_active, display_order) VALUES
('sc-01', 'Consultation',        'Khám và tư vấn — examination, diagnosis and treatment planning.',   0, 1, 1),
('sc-02', 'Scaling & Polishing', 'Cạo vôi răng — plaque and tartar removal with polish.',             0, 1, 2),
('sc-03', 'Composite Filling',   'Trám răng — tooth-coloured composite restoration.',                 0, 1, 3),
('sc-04', 'Tooth Extraction',    'Nhổ răng — simple or surgical extraction.',                         0, 1, 4),
('sc-05', 'Root Canal Therapy',  'Điều trị tủy — endodontic treatment, per tooth.',                   0, 1, 5),
('sc-06', 'Porcelain Crown',     'Bọc răng sứ — full-coverage porcelain crown.',                      0, 1, 6),
('sc-07', 'Dental Implant',      'Cấy ghép Implant — titanium fixture with abutment.',                1, 1, 7),
('sc-08', 'Orthodontic Braces',  'Niềng răng — full fixed appliance course, 18–24 months.',           1, 1, 8),
('sc-09', 'Teeth Whitening',     'Tẩy trắng răng — in-clinic LED whitening session.',                 0, 1, 9);

-- Porcelain Crown carries two versions: the 2025 price is what Trần Minh Đức's
-- November 2025 invoice was built from, and it must stay correct.
INSERT INTO price_list (id, service_category_id, unit_price, currency, effective_from, set_by, notes) VALUES
('pl-01', 'sc-01',    200000, 'VND', '2025-01-01', 'u-mgr01', 'Opening price list'),
('pl-02', 'sc-02',    500000, 'VND', '2025-01-01', 'u-mgr01', 'Opening price list'),
('pl-03', 'sc-03',    800000, 'VND', '2025-01-01', 'u-mgr01', 'Opening price list'),
('pl-04', 'sc-04',   1200000, 'VND', '2025-01-01', 'u-mgr01', 'Opening price list'),
('pl-05', 'sc-05',   3500000, 'VND', '2025-01-01', 'u-mgr01', 'Opening price list'),
('pl-06', 'sc-06',   5500000, 'VND', '2025-01-01', 'u-mgr01', 'Opening price list'),
('pl-07', 'sc-06',   6000000, 'VND', '2026-01-01', 'u-mgr01', 'Lab cost increase — supersedes pl-06'),
('pl-08', 'sc-07',  25000000, 'VND', '2025-01-01', 'u-mgr01', 'Opening price list'),
('pl-09', 'sc-08',  45000000, 'VND', '2025-01-01', 'u-mgr01', 'Full course, payable in instalments'),
('pl-10', 'sc-09',   3000000, 'VND', '2025-01-01', 'u-mgr01', 'Opening price list');

-- -----------------------------------------------------------------------------
-- Treatment plans
-- -----------------------------------------------------------------------------
INSERT INTO treatment_plan
    (id, patient_id, doctor_id, title, status, is_special, start_date, estimated_end_date, notes, created_at, updated_at) VALUES
('tp-01', 'pp-01', 'st-doc01', 'Lower right molar implant — #46', 'Active',    1, '2026-03-02', '2026-11-30', 'Bone density adequate on CBCT. Staged: extract, heal 8 weeks, place fixture, crown at 4 months.', '2026-03-02 09:40:00', '2026-05-11 16:20:00'),
('tp-02', 'pp-02', 'st-doc02', 'Full fixed orthodontic course',   'Active',    1, '2026-01-12', '2027-09-30', 'Class II div 1. Estimated 20 months in appliance. Monthly adjustment visits.',                     '2026-01-12 10:30:00', '2026-03-10 11:05:00'),
('tp-03', 'pp-03', 'st-doc01', 'Upper left premolar crown — #24', 'Completed', 0, '2025-11-10', '2025-11-24', 'Cracked cusp, restored with porcelain crown. Completed without complication.',                     '2025-11-10 14:45:00', '2025-11-24 17:00:00'),
('tp-04', 'pp-04', 'st-doc01', 'Root canal and crown — #36',      'Active',    0, '2026-07-06', '2026-09-30', 'Irreversible pulpitis. RCT completed; crown prep booked.',                                         '2026-07-06 11:40:00', '2026-07-06 15:30:00'),
('tp-05', 'pp-05', 'st-doc02', 'Initial consultation',            'Completed', 0, '2026-08-03', '2026-08-03', 'Walk-in. General check, no active pathology. Advised 6-month recall.',                             '2026-08-03 15:50:00', '2026-08-03 16:20:00'),
('tp-06', 'pp-06', 'st-doc02', 'New patient exam and hygiene',    'Completed', 0, '2026-08-17', '2026-08-17', 'Referred by existing patient. Generalised mild calculus, scaled same visit.',                      '2026-08-17 09:00:00', '2026-08-17 10:30:00');

-- -----------------------------------------------------------------------------
-- Treatment procedures — the ordered steps within each plan
-- -----------------------------------------------------------------------------
INSERT INTO treatment_procedure
    (id, treatment_plan_id, service_category_id, sequence, status, doctor_note, assistant_id, scheduled_date, completed_date) VALUES
('proc-01', 'tp-01', 'sc-01', 1, 'Completed', 'CBCT ordered. Discussed staged implant plan and costs with patient.', NULL,       '2026-03-02', '2026-03-02'),
('proc-02', 'tp-01', 'sc-04', 2, 'Completed', 'Atraumatic extraction #46. Socket preserved. Review in 8 weeks.',     'st-ast01', '2026-03-16', '2026-03-16'),
('proc-03', 'tp-01', 'sc-07', 3, 'Completed', 'Fixture placed, good primary stability (35 Ncm). Heal 4 months.',     'st-ast01', '2026-05-11', '2026-05-11'),
('proc-04', 'tp-01', 'sc-06', 4, 'Planned',   'Crown once osseointegration confirmed. Book impression late Sept.',   NULL,       NULL,         NULL),
('proc-05', 'tp-02', 'sc-01', 1, 'Completed', 'Records taken, Class II div 1 confirmed. Treatment plan accepted.',   NULL,       '2026-01-12', '2026-01-12'),
('proc-06', 'tp-02', 'sc-02', 2, 'Completed', 'Pre-appliance hygiene. OHI given.',                                   'st-ast01', '2026-01-12', '2026-01-12'),
('proc-07', 'tp-02', 'sc-08', 3, 'InProgress','Upper and lower bonded 2026-02-09. Monthly adjustments ongoing.',     'st-ast01', '2026-02-09', NULL),
('proc-08', 'tp-03', 'sc-02', 1, 'Completed', 'Scaled prior to crown prep.',                                         NULL,       '2025-11-10', '2025-11-10'),
('proc-09', 'tp-03', 'sc-06', 2, 'Completed', 'Crown #24 cemented. Occlusion checked, patient comfortable.',         'st-ast01', '2025-11-24', '2025-11-24'),
('proc-10', 'tp-04', 'sc-05', 1, 'Completed', 'RCT #36 completed in one visit. Temporary placed.',                   'st-ast01', '2026-07-06', '2026-07-06'),
('proc-11', 'tp-04', 'sc-06', 2, 'Scheduled', 'Crown prep and impression. Patient to confirm date.',                 NULL,       '2026-09-14', NULL),
('proc-12', 'tp-05', 'sc-01', 1, 'Completed', 'No active caries or periodontal disease. Recall in 6 months.',        NULL,       '2026-08-03', '2026-08-03'),
('proc-13', 'tp-06', 'sc-01', 1, 'Completed', 'Full exam and radiographs. Generalised mild calculus.',               NULL,       '2026-08-17', '2026-08-17'),
('proc-14', 'tp-06', 'sc-02', 2, 'Completed', 'Scaled and polished same visit. Recall 6 months.',                    'st-ast01', '2026-08-17', '2026-08-17');

-- -----------------------------------------------------------------------------
-- Appointments — person_id points at app_user, so a Provisional person can
-- hold a booking before they have ever arrived. created_by is NULL when the
-- patient booked themselves online.
-- -----------------------------------------------------------------------------
INSERT INTO appointment
    (id, person_id, doctor_id, scheduled_at, duration_minutes, type, status, booking_channel,
     treatment_procedure_id, assistant_id, followed_up_by, notes, created_by, created_at) VALUES
('ap-01', 'u-pat01', 'st-doc01', '2026-03-02 09:30:00', 45, 'Consultation', 'Completed', 'Online',    'proc-01', NULL,       NULL,      'Booked online after Google search; verified and converted on arrival.', NULL,      '2026-02-26 09:50:00'),
('ap-02', 'u-pat01', 'st-doc01', '2026-03-16 14:00:00', 60, 'Procedure',    'Completed', 'FrontDesk', 'proc-02', 'st-ast01', NULL,      'Extraction #46.',                              'u-rec01', '2026-03-02 10:15:00'),
('ap-03', 'u-pat01', 'st-doc01', '2026-05-11 08:30:00', 90, 'Procedure',    'Completed', 'Phone',     'proc-03', 'st-ast01', 'u-rec01', 'Implant placement. Booked after recall call.', 'u-rec01', '2026-04-28 09:00:00'),
('ap-04', 'u-pat01', 'st-doc01', '2026-09-21 10:00:00', 60, 'Procedure',    'Scheduled', 'FrontDesk', 'proc-04', NULL,       NULL,      'Crown impression, pending osseointegration.',  'u-rec01', '2026-08-25 11:30:00'),

('ap-05', 'u-pat02', 'st-doc02', '2026-01-12 10:00:00', 60, 'Consultation', 'Completed', 'Online',    'proc-05', NULL,       NULL,      'Orthodontic assessment, records taken.',       NULL,      '2026-01-05 16:10:00'),
('ap-06', 'u-pat02', 'st-doc02', '2026-01-12 11:00:00', 30, 'Procedure',    'Completed', 'FrontDesk', 'proc-06', 'st-ast01', NULL,      'Hygiene before bonding.',                      'u-rec01', '2026-01-12 10:50:00'),
('ap-07', 'u-pat02', 'st-doc02', '2026-02-09 09:00:00', 90, 'Procedure',    'Completed', 'FrontDesk', 'proc-07', 'st-ast01', NULL,      'Bond upper and lower appliances.',             'u-rec01', '2026-01-12 12:00:00'),
('ap-08', 'u-pat02', 'st-doc02', '2026-08-10 09:00:00', 30, 'Followup',     'NoShow',    'FrontDesk', 'proc-07', NULL,       NULL,      'Monthly adjustment — patient did not attend.', 'u-rec01', '2026-07-13 09:00:00'),
('ap-09', 'u-pat02', 'st-doc02', '2026-09-07 09:00:00', 30, 'Followup',     'Confirmed', 'Phone',     'proc-07', 'st-ast01', 'u-rec01', 'Rebooked after missed visit — confirmed.',     'u-rec01', '2026-08-12 10:40:00'),

('ap-10', 'u-pat03', 'st-doc01', '2025-11-10 14:30:00', 45, 'Consultation', 'Completed', 'FrontDesk', 'proc-08', NULL,       NULL,      'Walk-in, cracked cusp #24, scaled same visit.','u-rec01', '2025-11-10 14:25:00'),
('ap-11', 'u-pat03', 'st-doc01', '2025-11-24 15:00:00', 60, 'Procedure',    'Completed', 'FrontDesk', 'proc-09', 'st-ast01', NULL,      'Crown fit and cement.',                        'u-rec01', '2025-11-10 15:30:00'),

('ap-12', 'u-pat04', 'st-doc01', '2026-07-06 11:30:00', 90, 'Procedure',    'Completed', 'FrontDesk', 'proc-10', 'st-ast01', NULL,      'Emergency walk-in — irreversible pulpitis #36.','u-rec01','2026-07-06 11:25:00'),
('ap-13', 'u-pat04', 'st-doc01', '2026-08-24 14:00:00', 60, 'Procedure',    'Cancelled', 'FrontDesk', 'proc-11', NULL,       NULL,      'Patient cancelled, work commitment.',          'u-rec01', '2026-07-06 15:45:00'),
('ap-14', 'u-pat04', 'st-doc01', '2026-09-14 14:00:00', 60, 'Procedure',    'Scheduled', 'Phone',     'proc-11', NULL,       'u-rec01', 'Rebooked crown prep after follow-up call.',    'u-rec01', '2026-08-28 09:20:00'),

('ap-15', 'u-pat05', 'st-doc02', '2026-08-03 15:45:00', 30, 'Consultation', 'Completed', 'FrontDesk', 'proc-12', NULL,       NULL,      'Walk-in general check.',                       'u-rec01', '2026-08-03 15:40:00'),

('ap-16', 'u-pat06', 'st-doc02', '2026-08-17 09:00:00', 45, 'Consultation', 'Completed', 'Online',    'proc-13', NULL,       NULL,      'Booked online, referred by another patient.',  NULL,      '2026-08-14 13:05:00'),
('ap-17', 'u-pat06', 'st-doc02', '2026-08-17 09:45:00', 30, 'Procedure',    'Completed', 'FrontDesk', 'proc-14', 'st-ast01', NULL,      'Scale and polish same visit.',                 'u-rec01', '2026-08-17 09:40:00'),

-- Provisional people: booked online, no patient_profile, no CCCD.
('ap-18', 'u-prv01', 'st-doc02', '2026-09-05 16:00:00', 45, 'Consultation', 'Scheduled', 'Online',    NULL,      NULL,       NULL,      'New patient self-booked online. Verify CCCD on arrival.', NULL, '2026-08-26 20:14:00'),
('ap-19', 'u-prv02', 'st-doc01', '2026-08-20 10:00:00', 45, 'Consultation', 'NoShow',    'Online',    NULL,      NULL,       NULL,      'New patient self-booked online, did not attend. Needs reschedule contact.', NULL, '2026-08-11 21:47:00');

-- -----------------------------------------------------------------------------
-- Invoices — subtotal is the sum of each plan's procedures at the price in
-- effect on the day performed. total = subtotal - discount_amount.
-- -----------------------------------------------------------------------------
INSERT INTO invoice
    (id, treatment_plan_id, patient_id, issued_at, subtotal, discount_amount, total, status, due_date) VALUES
('inv-01', 'tp-01', 'pp-01', '2026-03-02 10:00:00', 32400000,       0, 32400000, 'PartiallyPaid', '2026-11-30'),
('inv-02', 'tp-02', 'pp-02', '2026-01-12 11:30:00', 45700000, 2000000, 43700000, 'PartiallyPaid', '2027-09-30'),
('inv-03', 'tp-03', 'pp-03', '2025-11-10 15:00:00',  6000000,       0,  6000000, 'Paid',          '2025-12-24'),
('inv-04', 'tp-04', 'pp-04', '2026-07-06 12:00:00',  9500000,       0,  9500000, 'PartiallyPaid', '2026-09-30'),
('inv-05', 'tp-05', 'pp-05', '2026-08-03 16:15:00',   200000,       0,   200000, 'Paid',          '2026-08-03'),
('inv-06', 'tp-06', 'pp-06', '2026-08-17 10:15:00',   700000,       0,   700000, 'Paid',          '2026-08-31');

INSERT INTO payment
    (id, invoice_id, amount, method, paid_at, received_by, reference_number, notes) VALUES
('pay-01', 'inv-01', 10000000, 'BankTransfer', '2026-03-02 10:20:00', 'u-rec01', 'VCB-20260302-0417', 'Deposit on treatment acceptance'),
('pay-02', 'inv-01', 10000000, 'BankTransfer', '2026-05-11 17:00:00', 'u-rec01', 'VCB-20260511-1183', 'Instalment 2, on fixture placement'),
('pay-03', 'inv-02', 15000000, 'BankTransfer', '2026-01-12 11:45:00', 'u-rec01', 'TCB-20260112-0092', 'Orthodontic down payment'),
('pay-04', 'inv-02', 10000000, 'Card',         '2026-03-10 11:00:00', 'u-rec01', 'POS-884120',        'Instalment 2'),
('pay-05', 'inv-03',  3000000, 'Cash',         '2025-11-10 15:10:00', 'u-rec01', NULL,                'Deposit at crown prep'),
('pay-06', 'inv-03',  3000000, 'Cash',         '2025-11-24 17:05:00', 'u-rec01', NULL,                'Balance on cementation'),
('pay-07', 'inv-04',  3500000, 'Cash',         '2026-07-06 15:30:00', 'u-rec01', NULL,                'Root canal settled; crown outstanding'),
('pay-08', 'inv-05',   200000, 'Cash',         '2026-08-03 16:20:00', 'u-rec01', NULL,                'Consultation fee'),
('pay-09', 'inv-06',   700000, 'Card',         '2026-08-17 10:20:00', 'u-rec01', 'POS-901744',        'Settled in full on the day');

-- -----------------------------------------------------------------------------
-- Commission rules — versioned, manager-set.
-- cr-05 is Dr. Minh's negotiated implant rate: staff + role + category beats
-- the role-level implant rate cr-03, which in turn beats the catch-all cr-01.
-- -----------------------------------------------------------------------------
INSERT INTO commission_rule
    (id, role, staff_id, service_category_id, event_type, commission_type, commission_value, effective_from, set_by, notes) VALUES
('cr-01', 'Doctor',       NULL,       NULL,    NULL, 'Percentage', 15, '2025-01-01', 'u-mgr01', 'Catch-all doctor rate'),
('cr-02', 'Assistant',    NULL,       NULL,    NULL, 'Percentage',  5, '2025-01-01', 'u-mgr01', 'Catch-all assistant rate'),
('cr-03', 'Doctor',       NULL,       'sc-07', NULL, 'Percentage', 20, '2025-01-01', 'u-mgr01', 'Implant — role-level uplift'),
('cr-04', 'Doctor',       NULL,       'sc-08', NULL, 'Percentage', 18, '2025-01-01', 'u-mgr01', 'Orthodontics — role-level uplift'),
('cr-05', 'Doctor',       'st-doc01', 'sc-07', NULL, 'Percentage', 22, '2025-01-01', 'u-mgr01', 'Dr. Minh implant contract rate'),
('cr-06', 'Receptionist', NULL,       NULL, 'NewPatientRegistered', 'FixedAmount', 100000, '2025-01-01', 'u-mgr01', 'Per new patient who completes a first visit'),
('cr-07', 'Receptionist', NULL,       NULL, 'SuccessfulFollowUp',   'FixedAmount',  50000, '2025-01-01', 'u-mgr01', 'Per completed follow-up booking');

-- -----------------------------------------------------------------------------
-- Commission entries — one per completed procedure, per credited staff member.
-- commission_base is the price snapshot at the time it was earned.
-- Nothing is generated for proc-04, proc-07 or proc-11: not Completed.
-- -----------------------------------------------------------------------------
INSERT INTO commission_entry
    (id, staff_id, source_type, procedure_id, commission_rule_id, commission_base, amount, status, earned_at) VALUES
('ce-01', 'st-doc01', 'ProcedureCompleted', 'proc-01', 'cr-01',   200000,    30000, 'Pending', '2026-03-02 10:00:00'),
('ce-02', 'st-doc01', 'ProcedureCompleted', 'proc-02', 'cr-01',  1200000,   180000, 'Pending', '2026-03-16 15:10:00'),
('ce-03', 'st-doc01', 'ProcedureCompleted', 'proc-03', 'cr-05', 25000000,  5500000, 'Pending', '2026-05-11 10:15:00'),
('ce-04', 'st-doc01', 'ProcedureCompleted', 'proc-08', 'cr-01',   500000,    75000, 'Pending', '2025-11-10 15:05:00'),
('ce-05', 'st-doc01', 'ProcedureCompleted', 'proc-09', 'cr-01',  5500000,   825000, 'Pending', '2025-11-24 16:50:00'),
('ce-06', 'st-doc01', 'ProcedureCompleted', 'proc-10', 'cr-01',  3500000,   525000, 'Pending', '2026-07-06 13:20:00'),
('ce-07', 'st-doc02', 'ProcedureCompleted', 'proc-05', 'cr-01',   200000,    30000, 'Pending', '2026-01-12 11:00:00'),
('ce-08', 'st-doc02', 'ProcedureCompleted', 'proc-06', 'cr-01',   500000,    75000, 'Pending', '2026-01-12 11:30:00'),
('ce-09', 'st-doc02', 'ProcedureCompleted', 'proc-12', 'cr-01',   200000,    30000, 'Pending', '2026-08-03 16:15:00'),
('ce-10', 'st-doc02', 'ProcedureCompleted', 'proc-13', 'cr-01',   200000,    30000, 'Pending', '2026-08-17 09:45:00'),
('ce-11', 'st-doc02', 'ProcedureCompleted', 'proc-14', 'cr-01',   500000,    75000, 'Pending', '2026-08-17 10:15:00'),
('ce-12', 'st-ast01', 'ProcedureCompleted', 'proc-02', 'cr-02',  1200000,    60000, 'Pending', '2026-03-16 15:10:00'),
('ce-13', 'st-ast01', 'ProcedureCompleted', 'proc-03', 'cr-02', 25000000,  1250000, 'Pending', '2026-05-11 10:15:00'),
('ce-14', 'st-ast01', 'ProcedureCompleted', 'proc-06', 'cr-02',   500000,    25000, 'Pending', '2026-01-12 11:30:00'),
('ce-15', 'st-ast01', 'ProcedureCompleted', 'proc-09', 'cr-02',  5500000,   275000, 'Pending', '2025-11-24 16:50:00'),
('ce-16', 'st-ast01', 'ProcedureCompleted', 'proc-10', 'cr-02',  3500000,   175000, 'Pending', '2026-07-06 13:20:00'),
('ce-17', 'st-ast01', 'ProcedureCompleted', 'proc-14', 'cr-02',   500000,    25000, 'Pending', '2026-08-17 10:15:00');

COMMIT;
