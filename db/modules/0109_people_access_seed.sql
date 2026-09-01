-- =============================================================================
-- KPX — MODULE 1 seed: People & Access
--
-- 13 people, chosen to exercise every edge the design cares about:
--
--   2  Provisional — booked online, never arrived: no CCCD, no verification,
--                    and deliberately NO patient_profile
--   4  Active patients — two with email, two walk-ins with none
--   7  Staff — one of each role, plus an Intern, one OnLeave, one Departed
--   2  DUAL PROFILE — a serving doctor and a departed doctor who are also
--                     patients at their own clinic
--
-- CCCD values follow the real format (079 = TP.HCM, then a century/gender
-- digit, then the 2-digit birth year, then six more). They are fabricated.
-- =============================================================================

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- -----------------------------------------------------------------------------
-- Staff. The manager self-verifies: a bootstrap case, since the owner set the
-- system up before anyone existed to check her documents.
-- -----------------------------------------------------------------------------
INSERT INTO app_user
    (id, full_name, phone, email, date_of_birth, address, national_id,
     status, verified_at, verified_by, role, created_at) VALUES
('u-mgr01', 'Nguyễn Thị Hương', '0901234501', 'huong.nguyen@kpx.vn', '1985-03-14', '12 Nguyễn Huệ, Quận 1, TP.HCM',   '079185001234', 'Active', '2024-06-01 08:00:00', 'u-mgr01', 'Manager',      '2024-06-01 08:00:00'),
('u-doc01', 'Trần Văn Minh',    '0901234502', 'bs.minh@kpx.vn',      '1980-11-02', '45 Lê Lợi, Quận 1, TP.HCM',       '079080004471', 'Active', '2024-06-01 08:30:00', 'u-mgr01', 'Doctor',       '2024-06-01 08:30:00'),
('u-doc02', 'Lê Thị Mai',       '0901234503', 'bs.mai@kpx.vn',       '1988-07-21', '78 Hai Bà Trưng, Quận 3, TP.HCM', '079188005218', 'Active', '2024-09-15 08:00:00', 'u-mgr01', 'Doctor',       '2024-09-15 08:00:00'),
('u-doc03', 'Ngô Bảo Châu',     '0901234507', 'bs.chau@kpx.vn',      '1983-02-11', '31 Nguyễn Du, Quận 1, TP.HCM',    '079083008890', 'Active', '2024-08-01 08:00:00', 'u-mgr01', 'Doctor',       '2024-08-01 08:00:00'),
('u-rec01', 'Phạm Thu Hà',      '0901234504', 'letan.ha@kpx.vn',     '1996-01-30', '23 Võ Văn Tần, Quận 3, TP.HCM',   '079196007742', 'Active', '2024-06-10 08:00:00', 'u-mgr01', 'Receptionist', '2024-06-10 08:00:00'),
('u-ast01', 'Đỗ Văn Nam',       '0901234505', 'trolyi.nam@kpx.vn',   '1998-05-18', '9 Cách Mạng Tháng 8, Quận 10',    '079098003310', 'Active', '2026-07-01 08:00:00', 'u-mgr01', 'Assistant',    '2026-07-01 08:00:00'),
('u-acc01', 'Vũ Thị Lan',       '0901234506', 'ketoan.lan@kpx.vn',   '1990-09-09', '56 Điện Biên Phủ, Bình Thạnh',    '079190006654', 'Active', '2024-06-20 08:00:00', 'u-mgr01', 'Accountant',   '2024-06-20 08:00:00');

-- -----------------------------------------------------------------------------
-- Patients. u-pat03 and u-pat04 are walk-ins with NO email — verified, CCCD on
-- file, fully Active patients who simply have no email address. Under the
-- deferred auth design they would sign in by one-time code to phone.
-- -----------------------------------------------------------------------------
INSERT INTO app_user
    (id, full_name, phone, email, date_of_birth, address, national_id,
     status, verified_at, verified_by, role, created_at) VALUES
('u-pat01', 'Hoàng Văn Tuấn',     '0912000101', 'tuan.hoang@gmail.com',    '1979-04-12', '102 Trần Hưng Đạo, Quận 5, TP.HCM', '079079101122', 'Active', '2026-03-02 09:15:00', 'u-rec01', 'Patient', '2026-02-26 09:50:00'),
('u-pat02', 'Nguyễn Thị Lan Anh', '0912000201', 'lananh.nguyen@gmail.com', '2003-08-25', '17 Nguyễn Đình Chiểu, Quận 3',      '079303202233', 'Active', '2026-01-12 10:00:00', 'u-rec01', 'Patient', '2026-01-05 16:10:00'),
('u-pat03', 'Phạm Thị Ngọc',      '0912000401', NULL,                      '1986-06-19', '210 Nguyễn Trãi, Quận 5, TP.HCM',   '079186404455', 'Active', '2026-07-06 11:20:00', 'u-rec01', 'Patient', '2026-07-06 11:20:00'),
('u-pat04', 'Lý Văn Hùng',        '0912000501', NULL,                      '1972-02-28', '34 Pasteur, Quận 1, TP.HCM',        '079072505566', 'Active', '2026-08-03 15:40:00', 'u-rec01', 'Patient', '2026-08-03 15:40:00');

-- -----------------------------------------------------------------------------
-- Provisional. Booked online, never arrived, so never verified: no CCCD, and
-- deliberately no patient_profile. These are not patients — they are people
-- holding a booking.
-- -----------------------------------------------------------------------------
INSERT INTO app_user
    (id, full_name, phone, email, date_of_birth, address, national_id,
     status, verified_at, verified_by, role, created_at) VALUES
('u-prv01', 'Bùi Thị Hạnh',  '0912000701', 'hanh.bui@gmail.com', '1994-04-02', NULL, NULL, 'Provisional', NULL, NULL, 'Patient', '2026-08-26 20:14:00'),
('u-prv02', 'Ngô Quang Huy', '0912000801', 'huy.ngo@gmail.com',  '1987-09-16', NULL, NULL, 'Provisional', NULL, NULL, 'Patient', '2026-08-11 21:47:00');

-- -----------------------------------------------------------------------------
-- Employment. One of each status the enum allows.
--   u-ast01 is an Intern — working, assignable, on trainee terms
--   u-doc02 is OnLeave  — maternity; not bookable, but not gone
--   u-doc03 is Departed — left the clinic, and is STILL A PATIENT below
-- -----------------------------------------------------------------------------
INSERT INTO staff_profile (id, user_id, join_date, employment_status, end_date, specialty, license_number) VALUES
('st-mgr01', 'u-mgr01', '2024-06-01', 'Active',   NULL,         NULL,           NULL),
('st-doc01', 'u-doc01', '2024-06-01', 'Active',   NULL,         'Implantology', 'VN-DDS-4471'),
('st-doc02', 'u-doc02', '2024-09-15', 'OnLeave',  NULL,         'Orthodontics', 'VN-DDS-5218'),
('st-doc03', 'u-doc03', '2024-08-01', 'Departed', '2026-06-30', 'Endodontics',  'VN-DDS-6612'),
('st-rec01', 'u-rec01', '2024-06-10', 'Active',   NULL,         NULL,           NULL),
('st-ast01', 'u-ast01', '2026-07-01', 'Intern',   NULL,         NULL,           NULL),
('st-acc01', 'u-acc01', '2024-06-20', 'Active',   NULL,         NULL,           NULL);

-- -----------------------------------------------------------------------------
-- Care relationships. Note the last two: staff who are also patients.
-- pp-06 is the departed doctor — employment ended, the person did not.
-- -----------------------------------------------------------------------------
INSERT INTO patient_profile (id, user_id, emergency_contact, referral_source, created_by, created_at) VALUES
('pp-01', 'u-pat01', 'Hoàng Thị Yến — 0912000102',  'Google search',      'u-rec01', '2026-03-02 09:15:00'),
('pp-02', 'u-pat02', 'Nguyễn Văn Bảo — 0912000202', 'Referral — patient', 'u-rec01', '2026-01-12 10:00:00'),
('pp-03', 'u-pat03', 'Phạm Văn Sơn — 0912000402',   'Facebook ad',        'u-rec01', '2026-07-06 11:20:00'),
('pp-04', 'u-pat04', NULL,                          'Walk-in',            'u-rec01', '2026-08-03 15:40:00'),
('pp-05', 'u-doc01', 'Trần Thị Hoa — 0901234599',   'Staff — self',       'u-rec01', '2026-05-20 08:00:00'),
('pp-06', 'u-doc03', 'Ngô Thị Bình — 0901234598',   'Staff — former',     'u-rec01', '2026-04-11 09:30:00');

COMMIT;
