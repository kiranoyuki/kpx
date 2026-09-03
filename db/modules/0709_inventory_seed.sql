-- =============================================================================
-- KPX — MODULE 7 seed: Inventory
--
-- 3 vendors, 8 items, 9 batches, supply templates, and the movement log that
-- drives every stock level.
--
-- Deliberate edge cases:
--   · Composite A2 has TWO batches — different expiry AND different unit cost,
--     so FEFO picking and cost-of-goods both have something to bite on
--   · one batch EXPIRES with its full 50 units unused: the write-off list.
--     Note it is never consumed after expiry — a trigger forbids that outright
--   · one batch expires within 30 days: the early warning
--   · equipment is a SEPARATE table with its own lifecycle: in service, under
--     maintenance, retired — plus a service history and an overdue check
--   · one item is below its reorder threshold, one is at zero
-- =============================================================================

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- ---------------------------------------------------------------- vendors --
INSERT INTO vendor (id, name, contact_person, phone, email, address, notes, is_active) VALUES
('v-01','Nha Khoa Việt',    'Nguyễn Văn Bình','0283822100','sales@nhakhoaviet.vn','45 Lý Thường Kiệt, Quận 10, TP.HCM','General consumables. Next-day delivery.',1),
('v-02','Osstem Vietnam',   'Kim Min-Jae',    '0283910455','vn.order@osstem.com', '12 Nguyễn Văn Trỗi, Phú Nhuận, TP.HCM','Implant fixtures and surgical kit. Lead time 5 days.',1),
('v-03','Dentsply Sirona',  'Trần Thị Mỹ',    '0283776201','vn.care@dentsply.com','88 Điện Biên Phủ, Bình Thạnh, TP.HCM','Restorative materials and endodontic files.',1);

-- ------------------------------------------------------------------ items --
-- quantity_on_hand starts at 0 everywhere: stock arrives through the log.
-- MATERIALS: consumed, batched, and they expire. Every one has a cost, because
-- every one has batches.
INSERT INTO inventory_item (id, name, unit, quantity_on_hand, reorder_threshold, vendor_id, category) VALUES
('it-comp-a2','Composite A2',              'syringe',  0, 5,'v-03','Consumable'),
('it-comp-a3','Composite A3',              'syringe',  0, 5,'v-03','Consumable'),
('it-lido',   'Lidocaine 2% w/ adrenaline','cartridge',0,20,'v-01','Medication'),
('it-fixture','Osstem TS III 4.0x10',      'piece',    0, 2,'v-02','Consumable'),
('it-suture', 'Suture 4-0 silk',           'pack',     0, 3,'v-01','Consumable'),
('it-zir',    'Zirconia blank 98mm',       'disc',     0, 1,'v-03','Lab'),
-- a prophy cup is single-use and sterile: a material, not equipment. It was
-- mislabelled before, which is what left it with no cost basis.
('it-prophy', 'Prophy cup, soft',          'piece',    0,20,'v-01','Consumable');

-- EQUIPMENT: reused, serviced, retired. Cost sits on the asset itself.
INSERT INTO equipment (id, name, serial_number, vendor_id, purchase_date, purchase_cost, status, retired_on, location, notes) VALUES
('eq-mirror','Dental mirror set #4', NULL,        'v-01','2026-05-12',   540000,'InService',       NULL,        'Ghế 1','Set of twelve.'),
('eq-hp-01', 'High-speed handpiece', 'NSK-884120','v-01','2025-03-04',  8500000,'InService',       NULL,        'Ghế 1','Serviced every 6 months.'),
('eq-hp-02', 'High-speed handpiece', 'NSK-884121','v-01','2025-03-04',  8500000,'UnderMaintenance',NULL,        'Workshop','Bearing noise; away for repair.'),
('eq-auto',  'Autoclave 23L',        'MEL-2201',  'v-01','2024-11-20', 42000000,'InService',       NULL,        'Sterile room','Annual validation required.'),
('eq-scaler','Ultrasonic scaler',    'EMS-5510',  'v-03','2023-06-15', 19000000,'Retired',         '2026-06-30','Store room','Replaced 2026-06; kept for parts.');

INSERT INTO equipment_maintenance (id, equipment_id, type, performed_at, performed_by, vendor_id, cost, next_due_date, notes) VALUES
('em-01','eq-hp-01','Routine',   '2026-03-04',NULL,      'v-01', 450000,'2026-09-04','Lubrication and turbine check.'),
('em-02','eq-hp-02','Repair',    '2026-08-28',NULL,      'v-01',1800000,NULL,        'Bearing replacement, in progress.'),
('em-03','eq-auto', 'Inspection','2026-01-15',NULL,      'v-01',2200000,'2027-01-15','Annual pressure-vessel validation.'),
('em-04','eq-auto', 'Routine',   '2026-07-01','u-ast01', NULL,        0,'2026-10-01','Gasket and filter check, done in house.');

-- ---------------------------------------------------------------- batches --
-- Every batch starts empty; the Restocked log below fills it.
INSERT INTO inventory_batch (id, inventory_item_id, lot_number, expiry_date, vendor_id, quantity_received, quantity_remaining, unit_cost, received_at) VALUES
-- Composite A2: two deliveries, two expiries, two COSTS
('b-a2-old','it-comp-a2','CA2-2405','2026-11-30','v-03',10,0,180000,'2026-05-12 09:00:00'),
('b-a2-new','it-comp-a2','CA2-2508','2027-06-30','v-03',20,0,210000,'2026-08-14 09:00:00'),
('b-a3',    'it-comp-a3','CA3-2506','2027-04-30','v-03',12,0,195000,'2026-06-20 09:00:00'),
-- Lidocaine: an EXPIRED lot still on the shelf, plus one expiring within 30 days
('b-lido-x','it-lido',  'LD-2401','2026-07-31','v-01',50,0, 22000,'2026-02-10 09:00:00'),
('b-lido-s','it-lido',  'LD-2503','2026-09-20','v-01',100,0,23500,'2026-06-05 09:00:00'),
('b-lido-n','it-lido',  'LD-2601','2027-08-31','v-01',100,0,24000,'2026-08-20 09:00:00'),
('b-fix',   'it-fixture','OS-TS3-2604','2029-04-30','v-02',4,0,4200000,'2026-07-01 09:00:00'),
('b-sut',   'it-suture','SU-2502','2027-02-28','v-01',10,0,85000,'2026-05-12 09:00:00'),
('b-zir',   'it-zir',   'ZR-2507','2028-07-31','v-03',3,0,2800000,'2026-07-18 09:00:00'),
-- a prophy cup is sterile single-use: it has a lot and a shelf life like any other material
('b-prophy','it-prophy','PC-2504','2028-04-30','v-01',100,0,3500,'2026-05-12 09:00:00');

-- ------------------------------------------------------- stock arriving in --
INSERT INTO inventory_log (id, inventory_item_id, batch_id, change_type, quantity_delta, quantity_after, logged_by, logged_at, notes) VALUES
('lg-01','it-comp-a2','b-a2-old','Restocked', 10, 10,'u-ast01','2026-05-12 09:10:00','Delivery from Dentsply.'),
('lg-02','it-comp-a2','b-a2-new','Restocked', 20, 30,'u-ast01','2026-08-14 09:10:00','Second delivery, higher price.'),
('lg-03','it-comp-a3','b-a3',    'Restocked', 12, 12,'u-ast01','2026-06-20 09:10:00',NULL),
('lg-04','it-lido',   'b-lido-x','Restocked', 50, 50,'u-ast01','2026-02-10 09:10:00',NULL),
('lg-05','it-lido',   'b-lido-s','Restocked',100,150,'u-ast01','2026-06-05 09:10:00',NULL),
('lg-06','it-lido',   'b-lido-n','Restocked',100,250,'u-ast01','2026-08-20 09:10:00',NULL),
('lg-07','it-fixture','b-fix',   'Restocked',  4,  4,'u-ast01','2026-07-01 09:10:00','Four fixtures, one size.'),
('lg-08','it-suture', 'b-sut',   'Restocked', 10, 10,'u-ast01','2026-05-12 09:10:00',NULL),
('lg-09','it-zir',    'b-zir',   'Restocked',  3,  3,'u-ast01','2026-07-18 09:10:00',NULL),
('lg-11','it-prophy','b-prophy','Restocked',100,100,'u-ast01','2026-05-12 09:10:00','Mirrors are equipment now, not stock.');

-- ------------------------------------------------- what procedures consumed --
-- FEFO in practice: the extraction drew lidocaine from the OLDEST usable lot.
INSERT INTO inventory_log (id, inventory_item_id, batch_id, change_type, quantity_delta, quantity_after, related_procedure_id, logged_by, logged_at, notes) VALUES
('lg-12','it-lido',   'b-lido-s','Consumed', -2,248,'pr-02','u-ast01','2026-08-28 14:20:00','Extraction #46, two cartridges. LD-2401 was already expired, so drawn from LD-2503.'),
('lg-13','it-suture', 'b-sut',   'Consumed', -1,  9,'pr-02','u-ast01','2026-08-28 14:50:00','Socket closure.'),
('lg-14','it-prophy','b-prophy','Consumed', -1, 99,'pr-10','u-ast01','2026-09-02 14:30:00','Scale and polish.'),
('lg-15','it-prophy','b-prophy','Consumed', -1, 98,'pr-12','u-ast01','2026-09-01 16:25:00','Staff scale and polish.'),
-- the three-surface filling: two syringes from the OLDER composite lot
('lg-16','it-comp-a2','b-a2-old','Consumed', -2, 28,'pr-09','u-ast01','2026-09-03 10:30:00','MOD composite on 37, shade A2.'),
('lg-17','it-lido',   'b-lido-s','Consumed', -1,247,'pr-09','u-ast01','2026-09-03 10:05:00','Local anaesthetic.');

-- ----------------------------------------------------- the expired write-off --
-- b-lido-x is past its date with 48 cartridges left. This is the movement the
-- 'Expired' change type existed for, and could not previously be recorded.
INSERT INTO inventory_log (id, inventory_item_id, batch_id, change_type, quantity_delta, quantity_after, logged_by, logged_at, notes) VALUES
('lg-18','it-lido','b-lido-x','Expired',-50,197,'u-ast01','2026-08-01 08:00:00','Lot LD-2401 past expiry 2026-07-31. All 50 cartridges written off — none were used after expiry.');

-- ---------------------------------------- what procedures are SUPPOSED to use --
-- Attached to the reusable instruction templates from module 4.
INSERT INTO procedure_supply_list (id, instruction_set_id, inventory_item_id, quantity_required, notes) VALUES
('sl-01','pi-01','it-fixture',1,'One fixture per implant.'),
('sl-02','pi-01','it-lido',   3,'Infiltration and block.'),
('sl-03','pi-01','it-suture', 1,'Flap closure.'),
('sl-04','pi-02','it-lido',   2,'Single-visit endodontics.'),
('sl-05','pi-03','it-prophy', 1,'One cup per patient.');

-- a one-off addition to a specific procedure, not the template
INSERT INTO procedure_supply_list (id, procedure_id, inventory_item_id, quantity_required, notes) VALUES
('sl-06','pr-09','it-comp-a2',2,'Three-surface restoration needs two syringes.');

-- ----------------------------------------------- deliberately run two low --
INSERT INTO inventory_log (id, inventory_item_id, batch_id, change_type, quantity_delta, quantity_after, logged_by, logged_at, notes) VALUES
('lg-19','it-fixture','b-fix','Consumed',-3,1,'u-ast01','2026-08-30 09:00:00','Three fixtures used on other cases.'),
('lg-20','it-zir',    'b-zir','Consumed',-3,0,'u-ast01','2026-08-31 09:00:00','All three discs milled.');

COMMIT;
