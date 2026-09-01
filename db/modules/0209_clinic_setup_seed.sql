-- =============================================================================
-- KPX — MODULE 2 seed: Clinic Setup
--
-- Reference and configuration data for a single clinic.
--   52 teeth · 4 chair types · 5 chairs · 9 services · 11 materials
--   17 prices · 4 voucher codes
--
-- Deliberate edge cases:
--   · Porcelain Crown carries a SUPERSEDED base price (2025) and a current one
--   · Zirconia and PFM are priced apart; E-max has NO price of its own and
--     must fall back to the category base
--   · Teeth Whitening is the only VAT-bearing service — cosmetic, not medical
--   · One chair is under Maintenance and must not be bookable
--   · One voucher has expired, one has a redemption cap
-- =============================================================================

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- ---------------------------------------------------------------- FDI teeth --
INSERT INTO tooth (code,quadrant,position,dentition,arch,side,tooth_type,is_anterior,valid_surfaces,name,name_vi,universal_code) VALUES
('11',1,1,'Permanent','Upper','Right','Incisor',1,'MIDBL','Upper right central incisor','Răng cửa giữa hàm trên bên phải','8'),
('12',1,2,'Permanent','Upper','Right','Incisor',1,'MIDBL','Upper right lateral incisor','Răng cửa bên hàm trên bên phải','7'),
('13',1,3,'Permanent','Upper','Right','Canine',1,'MIDBL','Upper right canine','Răng nanh hàm trên bên phải','6'),
('14',1,4,'Permanent','Upper','Right','Premolar',0,'MODBL','Upper right first premolar','Răng hàm nhỏ thứ nhất hàm trên bên phải','5'),
('15',1,5,'Permanent','Upper','Right','Premolar',0,'MODBL','Upper right second premolar','Răng hàm nhỏ thứ hai hàm trên bên phải','4'),
('16',1,6,'Permanent','Upper','Right','Molar',0,'MODBL','Upper right first molar','Răng hàm lớn thứ nhất hàm trên bên phải','3'),
('17',1,7,'Permanent','Upper','Right','Molar',0,'MODBL','Upper right second molar','Răng hàm lớn thứ hai hàm trên bên phải','2'),
('18',1,8,'Permanent','Upper','Right','Molar',0,'MODBL','Upper right third molar','Răng khôn hàm trên bên phải','1'),
('21',2,1,'Permanent','Upper','Left','Incisor',1,'MIDBL','Upper left central incisor','Răng cửa giữa hàm trên bên trái','9'),
('22',2,2,'Permanent','Upper','Left','Incisor',1,'MIDBL','Upper left lateral incisor','Răng cửa bên hàm trên bên trái','10'),
('23',2,3,'Permanent','Upper','Left','Canine',1,'MIDBL','Upper left canine','Răng nanh hàm trên bên trái','11'),
('24',2,4,'Permanent','Upper','Left','Premolar',0,'MODBL','Upper left first premolar','Răng hàm nhỏ thứ nhất hàm trên bên trái','12'),
('25',2,5,'Permanent','Upper','Left','Premolar',0,'MODBL','Upper left second premolar','Răng hàm nhỏ thứ hai hàm trên bên trái','13'),
('26',2,6,'Permanent','Upper','Left','Molar',0,'MODBL','Upper left first molar','Răng hàm lớn thứ nhất hàm trên bên trái','14'),
('27',2,7,'Permanent','Upper','Left','Molar',0,'MODBL','Upper left second molar','Răng hàm lớn thứ hai hàm trên bên trái','15'),
('28',2,8,'Permanent','Upper','Left','Molar',0,'MODBL','Upper left third molar','Răng khôn hàm trên bên trái','16'),
('31',3,1,'Permanent','Lower','Left','Incisor',1,'MIDBL','Lower left central incisor','Răng cửa giữa hàm dưới bên trái','24'),
('32',3,2,'Permanent','Lower','Left','Incisor',1,'MIDBL','Lower left lateral incisor','Răng cửa bên hàm dưới bên trái','23'),
('33',3,3,'Permanent','Lower','Left','Canine',1,'MIDBL','Lower left canine','Răng nanh hàm dưới bên trái','22'),
('34',3,4,'Permanent','Lower','Left','Premolar',0,'MODBL','Lower left first premolar','Răng hàm nhỏ thứ nhất hàm dưới bên trái','21'),
('35',3,5,'Permanent','Lower','Left','Premolar',0,'MODBL','Lower left second premolar','Răng hàm nhỏ thứ hai hàm dưới bên trái','20'),
('36',3,6,'Permanent','Lower','Left','Molar',0,'MODBL','Lower left first molar','Răng hàm lớn thứ nhất hàm dưới bên trái','19'),
('37',3,7,'Permanent','Lower','Left','Molar',0,'MODBL','Lower left second molar','Răng hàm lớn thứ hai hàm dưới bên trái','18'),
('38',3,8,'Permanent','Lower','Left','Molar',0,'MODBL','Lower left third molar','Răng khôn hàm dưới bên trái','17'),
('41',4,1,'Permanent','Lower','Right','Incisor',1,'MIDBL','Lower right central incisor','Răng cửa giữa hàm dưới bên phải','25'),
('42',4,2,'Permanent','Lower','Right','Incisor',1,'MIDBL','Lower right lateral incisor','Răng cửa bên hàm dưới bên phải','26'),
('43',4,3,'Permanent','Lower','Right','Canine',1,'MIDBL','Lower right canine','Răng nanh hàm dưới bên phải','27'),
('44',4,4,'Permanent','Lower','Right','Premolar',0,'MODBL','Lower right first premolar','Răng hàm nhỏ thứ nhất hàm dưới bên phải','28'),
('45',4,5,'Permanent','Lower','Right','Premolar',0,'MODBL','Lower right second premolar','Răng hàm nhỏ thứ hai hàm dưới bên phải','29'),
('46',4,6,'Permanent','Lower','Right','Molar',0,'MODBL','Lower right first molar','Răng hàm lớn thứ nhất hàm dưới bên phải','30'),
('47',4,7,'Permanent','Lower','Right','Molar',0,'MODBL','Lower right second molar','Răng hàm lớn thứ hai hàm dưới bên phải','31'),
('48',4,8,'Permanent','Lower','Right','Molar',0,'MODBL','Lower right third molar','Răng khôn hàm dưới bên phải','32'),
('51',5,1,'Primary','Upper','Right','Incisor',1,'MIDBL','Upper right central incisor','Răng cửa giữa sữa hàm trên bên phải','E'),
('52',5,2,'Primary','Upper','Right','Incisor',1,'MIDBL','Upper right lateral incisor','Răng cửa bên sữa hàm trên bên phải','D'),
('53',5,3,'Primary','Upper','Right','Canine',1,'MIDBL','Upper right canine','Răng nanh sữa hàm trên bên phải','C'),
('54',5,4,'Primary','Upper','Right','Molar',0,'MODBL','Upper right first molar','Răng hàm sữa thứ nhất hàm trên bên phải','B'),
('55',5,5,'Primary','Upper','Right','Molar',0,'MODBL','Upper right second molar','Răng hàm sữa thứ hai hàm trên bên phải','A'),
('61',6,1,'Primary','Upper','Left','Incisor',1,'MIDBL','Upper left central incisor','Răng cửa giữa sữa hàm trên bên trái','F'),
('62',6,2,'Primary','Upper','Left','Incisor',1,'MIDBL','Upper left lateral incisor','Răng cửa bên sữa hàm trên bên trái','G'),
('63',6,3,'Primary','Upper','Left','Canine',1,'MIDBL','Upper left canine','Răng nanh sữa hàm trên bên trái','H'),
('64',6,4,'Primary','Upper','Left','Molar',0,'MODBL','Upper left first molar','Răng hàm sữa thứ nhất hàm trên bên trái','I'),
('65',6,5,'Primary','Upper','Left','Molar',0,'MODBL','Upper left second molar','Răng hàm sữa thứ hai hàm trên bên trái','J'),
('71',7,1,'Primary','Lower','Left','Incisor',1,'MIDBL','Lower left central incisor','Răng cửa giữa sữa hàm dưới bên trái','O'),
('72',7,2,'Primary','Lower','Left','Incisor',1,'MIDBL','Lower left lateral incisor','Răng cửa bên sữa hàm dưới bên trái','N'),
('73',7,3,'Primary','Lower','Left','Canine',1,'MIDBL','Lower left canine','Răng nanh sữa hàm dưới bên trái','M'),
('74',7,4,'Primary','Lower','Left','Molar',0,'MODBL','Lower left first molar','Răng hàm sữa thứ nhất hàm dưới bên trái','L'),
('75',7,5,'Primary','Lower','Left','Molar',0,'MODBL','Lower left second molar','Răng hàm sữa thứ hai hàm dưới bên trái','K'),
('81',8,1,'Primary','Lower','Right','Incisor',1,'MIDBL','Lower right central incisor','Răng cửa giữa sữa hàm dưới bên phải','P'),
('82',8,2,'Primary','Lower','Right','Incisor',1,'MIDBL','Lower right lateral incisor','Răng cửa bên sữa hàm dưới bên phải','Q'),
('83',8,3,'Primary','Lower','Right','Canine',1,'MIDBL','Lower right canine','Răng nanh sữa hàm dưới bên phải','R'),
('84',8,4,'Primary','Lower','Right','Molar',0,'MODBL','Lower right first molar','Răng hàm sữa thứ nhất hàm dưới bên phải','S'),
('85',8,5,'Primary','Lower','Right','Molar',0,'MODBL','Lower right second molar','Răng hàm sữa thứ hai hàm dưới bên phải','T');

-- ------------------------------------------------------------- chair types --
INSERT INTO chair_type (id, name, description) VALUES
('ct-std',  'Standard',    'General treatment position: exams, hygiene, restorative work.'),
('ct-surg', 'Surgical',    'Sterile field, surgical suction, implant motor. Extractions and implants.'),
('ct-orth', 'Orthodontic', 'Extended headrest and bracket tray for appliance work.'),
('ct-img',  'Imaging',     'CBCT and panoramic unit. Not a treatment position.');

-- ------------------------------------------------------------------ chairs --
INSERT INTO chair (id, code, chair_type_id, status, notes, display_order) VALUES
('ch-01', 'Ghế 1',              'ct-std',  'Available',   NULL, 1),
('ch-02', 'Ghế 2',              'ct-std',  'Available',   NULL, 2),
('ch-03', 'Phòng phẫu thuật',   'ct-surg', 'Available',   'Implant and surgical extractions.', 3),
('ch-04', 'Ghế chỉnh nha',      'ct-orth', 'Maintenance', 'Chair motor under repair, due back 2026-09-15.', 4),
('ch-05', 'Phòng X-quang',      'ct-img',  'Available',   'CBCT. Imaging only, no treatment.', 5);

-- -------------------------------------------------------- service catalogue --
-- vat_rate is per service: medical treatment and cosmetic work are not taxed
-- alike, so only whitening carries VAT here. Confirm rates with the accountant.
INSERT INTO service_category
    (id, name, description, is_special, tooth_scope, pricing_basis, vat_rate,
     requires_material_choice, required_chair_type_id, warranty_days,
     resulting_condition_type, is_active, display_order) VALUES
('sc-01','Consultation',        'Khám và tư vấn — examination, diagnosis and treatment planning.', 0,'None',       'PerProcedure', 0, 0, NULL,      NULL, NULL,               1,1),
('sc-02','Scaling & Polishing', 'Cạo vôi răng — plaque and tartar removal with polish.',            0,'FullMouth',  'PerProcedure', 0, 0, NULL,      NULL, NULL,               1,2),
('sc-03','Composite Filling',   'Trám răng — tooth-coloured composite restoration.',                0,'SingleTooth','PerSurface',   0, 1, NULL,       365, 'Filling',          1,3),
('sc-04','Tooth Extraction',    'Nhổ răng — simple or surgical extraction.',                        0,'SingleTooth','PerTooth',     0, 0, 'ct-surg', NULL, 'Missing',          1,4),
('sc-05','Root Canal Therapy',  'Điều trị tủy — endodontic treatment, per tooth.',                  0,'SingleTooth','PerTooth',     0, 0, NULL,       730, 'RootCanalTreated', 1,5),
('sc-06','Porcelain Crown',     'Bọc răng sứ — full-coverage porcelain crown.',                     0,'SingleTooth','PerTooth',     0, 1, NULL,      1825, 'Crown',            1,6),
('sc-07','Dental Implant',      'Cấy ghép Implant — titanium fixture with abutment.',               1,'SingleTooth','PerTooth',     0, 1, 'ct-surg',3650, 'Implant',          1,7),
('sc-08','Orthodontic Braces',  'Niềng răng — full fixed appliance course, 18–24 months.',          1,'FullMouth',  'PerProcedure', 0, 1, 'ct-orth', NULL, NULL,               1,8),
('sc-09','Teeth Whitening',     'Tẩy trắng răng — in-clinic LED whitening session.',                0,'FullMouth',  'PerProcedure',10, 0, NULL,      NULL, NULL,               1,9);

-- --------------------------------------------------------- material options --
INSERT INTO material_option (id, service_category_id, name, description, is_active, display_order) VALUES
('mo-fill-std',  'sc-03','Standard composite',   'Everyday tooth-coloured filling material.',                    1,1),
('mo-fill-prem', 'sc-03','Premium nano-composite','Higher polish and wear resistance; better for front teeth.',  1,2),
('mo-crown-pfm', 'sc-06','Porcelain-fused-metal', 'Metal substructure with a porcelain facing. Most economical.',1,1),
('mo-crown-zir', 'sc-06','Zirconia',              'All-ceramic, metal-free, high strength.',                     1,2),
('mo-crown-emax','sc-06','E-max',                 'Lithium disilicate. Best aesthetics for visible teeth.',      1,3),
('mo-impl-oss',  'sc-07','Osstem',                'Korean fixture. Widely used, strong evidence base.',           1,1),
('mo-impl-den',  'sc-07','Dentium',               'Korean fixture, alternative surface treatment.',               1,2),
('mo-impl-str',  'sc-07','Straumann',             'Swiss fixture. Premium option with the longest track record.', 1,3),
('mo-orth-metal','sc-08','Metal brackets',        'Stainless steel. Most economical and most robust.',            1,1),
('mo-orth-cer',  'sc-08','Ceramic brackets',      'Tooth-coloured, far less visible.',                            1,2),
('mo-orth-align','sc-08','Clear aligner',         'Removable transparent trays. No fixed appliance.',             1,3);

-- ----------------------------------------------------------------- prices --
-- material_option_id NULL is the category's base price.
INSERT INTO price_list (id, service_category_id, material_option_id, unit_price, currency, effective_from, set_by, notes) VALUES
('pl-01','sc-01',NULL,             200000,'VND','2025-01-01','u-mgr01','Opening price list'),
('pl-02','sc-02',NULL,             500000,'VND','2025-01-01','u-mgr01','Opening price list'),
('pl-03','sc-03',NULL,             800000,'VND','2025-01-01','u-mgr01','Base: standard composite, per surface'),
('pl-04','sc-03','mo-fill-prem',  1200000,'VND','2025-01-01','u-mgr01','Premium nano-composite, per surface'),
('pl-05','sc-04',NULL,            1200000,'VND','2025-01-01','u-mgr01','Opening price list'),
('pl-06','sc-05',NULL,            3500000,'VND','2025-01-01','u-mgr01','Opening price list'),
-- Crown: base price superseded on 2026-01-01. Both rows must survive, so that
-- a 2025 invoice still reprices correctly.
('pl-07','sc-06',NULL,            5500000,'VND','2025-01-01','u-mgr01','Opening base crown price'),
('pl-08','sc-06',NULL,            6000000,'VND','2026-01-01','u-mgr01','Lab cost increase — supersedes pl-07'),
('pl-09','sc-06','mo-crown-pfm',  5000000,'VND','2025-01-01','u-mgr01','PFM crown'),
('pl-10','sc-06','mo-crown-zir',  8000000,'VND','2025-01-01','u-mgr01','Zirconia crown'),
('pl-11','sc-06','mo-crown-zir',  8500000,'VND','2026-01-01','u-mgr01','Zirconia — supersedes pl-10'),
-- E-max has NO row of its own: it must fall back to the category base price.
('pl-12','sc-07',NULL,           25000000,'VND','2025-01-01','u-mgr01','Base implant price'),
('pl-13','sc-07','mo-impl-oss',  25000000,'VND','2025-01-01','u-mgr01','Osstem fixture'),
('pl-14','sc-07','mo-impl-str',  38000000,'VND','2025-01-01','u-mgr01','Straumann fixture'),
('pl-15','sc-08',NULL,           45000000,'VND','2025-01-01','u-mgr01','Base course price, payable in instalments'),
('pl-16','sc-08','mo-orth-align',80000000,'VND','2025-01-01','u-mgr01','Clear aligner course'),
('pl-17','sc-09',NULL,            3000000,'VND','2025-01-01','u-mgr01','Opening price list');

-- -------------------------------------------------------------- promotions --
INSERT INTO promotion (id, code, name, discount_type, discount_value, start_date, end_date, max_redemptions, is_active, created_by, notes) VALUES
('pr-01','XASH',   'Autumn 10% off',        'Percentage',   10,'2026-08-01','2026-12-31',NULL,1,'u-mgr01','General campaign, no cap.'),
('pr-02','ISHD',   'Referral 15% off',      'Percentage',   15,'2026-09-01','2026-11-30', 100,1,'u-mgr01','For patients referred by an existing patient.'),
('pr-03','TET2026','Tết new year 20% off',  'Percentage',   20,'2026-01-20','2026-02-20',NULL,1,'u-mgr01','EXPIRED — kept so past invoices still resolve their code.'),
('pr-04','WELCOME','New patient 500k off',  'FixedAmount',500000,'2026-06-01','2026-12-31',50,1,'u-mgr01','Capped at 50 redemptions.');

COMMIT;
