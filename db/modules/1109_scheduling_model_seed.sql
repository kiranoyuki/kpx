-- =============================================================================
-- KPX — MODULE 11 SEED: the scheduling model
--
-- Configures the two services Phase B1 builds first — Initial consultation and
-- Cleaning — plus enough of the rest to prove the model holds. The interesting
-- rows are the OR (a consultation fits a consult room or an ordinary chair), the
-- capability one doctor has and another does not, and a Tết closure.
-- =============================================================================

-- Durations and who may book. A service the public may book must state a
-- duration, or availability has nothing to slice the day into.
UPDATE service_category SET default_duration_minutes = 30, booking_policy = 'PatientBookable' WHERE id = 'sc-01'; -- Consultation
UPDATE service_category SET default_duration_minutes = 45, booking_policy = 'PatientBookable' WHERE id = 'sc-02'; -- Scaling & Polishing
UPDATE service_category SET default_duration_minutes = 45, booking_policy = 'StaffBookable'   WHERE id = 'sc-03'; -- Composite Filling
UPDATE service_category SET default_duration_minutes = 30, booking_policy = 'StaffBookable'   WHERE id = 'sc-04'; -- Tooth Extraction
UPDATE service_category SET default_duration_minutes = 60, booking_policy = 'StaffBookable'   WHERE id = 'sc-05'; -- Root Canal
UPDATE service_category SET default_duration_minutes = 60, booking_policy = 'StaffBookable'   WHERE id = 'sc-06'; -- Porcelain Crown
UPDATE service_category SET default_duration_minutes = 90, booking_policy = 'StaffOnly'       WHERE id = 'sc-07'; -- Dental Implant
UPDATE service_category SET default_duration_minutes = 45, booking_policy = 'StaffOnly'       WHERE id = 'sc-08'; -- Orthodontic Braces
UPDATE service_category SET default_duration_minutes = 45, booking_policy = 'PatientBookable' WHERE id = 'sc-09'; -- Teeth Whitening


-- What each service may be performed in. Note sc-01: a consultation fits a
-- standard chair OR the imaging room — the OR that required_chair_type_id could
-- not express.
INSERT INTO service_resource_requirement (id, service_category_id, chair_type_id, quantity, display_order) VALUES
('srr-01a', 'sc-01', 'ct-std',  1, 0),
('srr-01b', 'sc-01', 'ct-img',  1, 1),
('srr-02',  'sc-02', 'ct-std',  1, 0),
('srr-03',  'sc-03', 'ct-std',  1, 0),
('srr-04',  'sc-04', 'ct-surg', 1, 0),
('srr-05',  'sc-05', 'ct-std',  1, 0),
('srr-06',  'sc-06', 'ct-std',  1, 0),
('srr-07',  'sc-07', 'ct-surg', 1, 0),
('srr-08',  'sc-08', 'ct-orth', 1, 0),
('srr-09',  'sc-09', 'ct-std',  1, 0);


-- Who may perform what. Trần Văn Minh does general work; Lâm Thị Quỳnh also
-- places implants and fits braces — the distinction `role` cannot express, since
-- both are Doctors.
INSERT INTO provider_service_capability (id, staff_id, service_category_id, is_enabled, note) VALUES
('psc-01', 'st-doc01', 'sc-01', 1, NULL),
('psc-02', 'st-doc01', 'sc-02', 1, NULL),
('psc-03', 'st-doc01', 'sc-03', 1, NULL),
('psc-04', 'st-doc01', 'sc-04', 1, NULL),
('psc-05', 'st-doc01', 'sc-05', 1, NULL),
('psc-06', 'st-doc01', 'sc-06', 1, NULL),
('psc-07', 'st-doc01', 'sc-07', 0, 'not implant-certified'),
('psc-08', 'st-doc04', 'sc-01', 1, NULL),
('psc-09', 'st-doc04', 'sc-02', 1, NULL),
('psc-10', 'st-doc04', 'sc-03', 1, NULL),
('psc-11', 'st-doc04', 'sc-07', 1, 'implant-certified 2025'),
('psc-12', 'st-doc04', 'sc-08', 1, NULL),
('psc-13', 'st-doc04', 'sc-09', 1, NULL),
-- The hygienist-equivalent: an assistant who may scale, but not treat.
('psc-14', 'st-ast01', 'sc-02', 1, 'scaling only');


-- When the clinic is open. Monday to Saturday, closed Sunday, with a Tết
-- closure and a half-day as dated exceptions.
INSERT INTO clinic_hours (id, day_of_week, date, opens_at, closes_at, is_open, note) VALUES
('ch-sun', 0, NULL, NULL,    NULL,    0, 'closed Sundays'),
('ch-mon', 1, NULL, '08:00', '17:00', 1, NULL),
('ch-tue', 2, NULL, '08:00', '17:00', 1, NULL),
('ch-wed', 3, NULL, '08:00', '17:00', 1, NULL),
('ch-thu', 4, NULL, '08:00', '17:00', 1, NULL),
('ch-fri', 5, NULL, '08:00', '17:00', 1, NULL),
('ch-sat', 6, NULL, '08:00', '12:00', 1, 'Saturday mornings only'),
('ch-tet1', NULL, '2027-02-06', NULL, NULL, 0, 'Tết'),
('ch-tet2', NULL, '2027-02-07', NULL, NULL, 0, 'Tết'),
('ch-eve',  NULL, '2026-12-24', '08:00', '12:00', 1, 'Christmas Eve, half day');
