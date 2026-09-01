-- =============================================================================
-- KPX — MODULE 2: Clinic Setup
-- tooth · chair_type · chair · service_category · material_option
-- price_list · promotion
--
-- Source of truth: Design/core-entities/entities.md
-- Build order:     Design/build-plan.md  (module 2 of 9; depends on module 1)
--
-- Reference and configuration data. Seeded once, written rarely thereafter.
-- =============================================================================

PRAGMA foreign_keys = ON;


-- -----------------------------------------------------------------------------
-- FDI / ISO 3950 notation. 52 static rows: 32 permanent + 20 primary.
-- Two digits: quadrant, then position from the midline. 46 = lower right first
-- molar. Left and right are always the PATIENT'S — the commonest charting error.
--
-- A table rather than a bare CHECK, because these rows carry information the
-- rest of the system needs: valid_surfaces validates a filling, is_anterior
-- drives clinical and pricing rules, and the names let a record read as words.
-- -----------------------------------------------------------------------------
CREATE TABLE tooth (
    code            TEXT PRIMARY KEY,
    quadrant        INTEGER NOT NULL CHECK (quadrant BETWEEN 1 AND 8),
    position        INTEGER NOT NULL CHECK (position BETWEEN 1 AND 8),
    dentition       TEXT NOT NULL CHECK (dentition IN ('Permanent', 'Primary')),
    arch            TEXT NOT NULL CHECK (arch IN ('Upper', 'Lower')),
    side            TEXT NOT NULL CHECK (side IN ('Right', 'Left')),
    tooth_type      TEXT NOT NULL CHECK (tooth_type IN ('Incisor','Canine','Premolar','Molar')),
    is_anterior     INTEGER NOT NULL CHECK (is_anterior IN (0,1)),
    -- MIDBL anterior (incisal edge) · MODBL posterior (occlusal surface)
    valid_surfaces  TEXT NOT NULL CHECK (valid_surfaces IN ('MIDBL', 'MODBL')),
    name            TEXT NOT NULL,
    name_vi         TEXT NOT NULL,
    universal_code  TEXT,                  -- US 1–32 / A–T, for imaging software

    CONSTRAINT ck_tooth_code_matches_parts CHECK (code = quadrant || position),
    CONSTRAINT ck_tooth_dentition_quadrant CHECK (
        (dentition = 'Permanent') = (quadrant BETWEEN 1 AND 4)),
    CONSTRAINT ck_tooth_primary_position CHECK (
        dentition = 'Permanent' OR position BETWEEN 1 AND 5),
    CONSTRAINT ck_tooth_anterior_matches_position CHECK (
        is_anterior = (position <= 3)),
    CONSTRAINT ck_tooth_surfaces_match_anterior CHECK (
        valid_surfaces = CASE WHEN position <= 3 THEN 'MIDBL' ELSE 'MODBL' END)
);


-- -----------------------------------------------------------------------------
-- What a chair is equipped to do, and the physical positions themselves.
-- Chairs, not doctors, cap the clinic's throughput.
-- -----------------------------------------------------------------------------
-- Just a name and a description. No is_active and no display_order: `chair`
-- answers both one level down and answers them better. Retiring a type and
-- retiring its chairs are not two decisions — if the clinic stops doing
-- orthodontics, the orthodontic chairs are retired, and that is the observable
-- fact. A type-level flag adds nothing actionable, and nothing would keep the
-- two levels coherent: an Available chair of an inactive type is a state the
-- schema would hold and no query would catch.
CREATE TABLE chair_type (
    id            TEXT PRIMARY KEY,
    name          TEXT NOT NULL UNIQUE,
    description   TEXT
);

CREATE TABLE chair (
    id            TEXT PRIMARY KEY,
    code          TEXT NOT NULL UNIQUE,          -- "Ghế 1", "Phòng phẫu thuật"
    chair_type_id TEXT NOT NULL REFERENCES chair_type(id),
    status        TEXT NOT NULL DEFAULT 'Available'
                      CHECK (status IN ('Available', 'Maintenance', 'Retired')),
    notes         TEXT,
    display_order INTEGER NOT NULL DEFAULT 0
);
-- NOTE: there is deliberately no 'InUse' status. Available/Maintenance/Retired
-- are configuration, set by a human and changing rarely. Occupancy is derived
-- state: an appointment with status = InProgress and this chair_id already says
-- a patient is in the chair. Module 3 adds v_chair_occupancy over that, rather
-- than a column someone has to remember to unset.


-- -----------------------------------------------------------------------------
-- The service catalogue. tooth_scope validates; pricing_basis bills; vat_rate
-- is PER SERVICE because Vietnamese VAT treats medical and cosmetic dentistry
-- differently.
-- -----------------------------------------------------------------------------
CREATE TABLE service_category (
    id                        TEXT PRIMARY KEY,
    name                      TEXT NOT NULL UNIQUE,
    description               TEXT,                       -- patient-facing
    is_special                INTEGER NOT NULL DEFAULT 0 CHECK (is_special IN (0,1)),
    tooth_scope               TEXT NOT NULL DEFAULT 'None' CHECK (tooth_scope IN (
                                  'None','SingleTooth','MultiTooth','Quadrant','Arch','FullMouth')),
    pricing_basis             TEXT NOT NULL DEFAULT 'PerProcedure' CHECK (pricing_basis IN (
                                  'PerProcedure','PerTooth','PerSurface','PerQuadrant')),
    vat_rate                  NUMERIC NOT NULL DEFAULT 0 CHECK (vat_rate BETWEEN 0 AND 100),
    requires_material_choice  INTEGER NOT NULL DEFAULT 0 CHECK (requires_material_choice IN (0,1)),
    -- null means any chair will do; set only where the work needs the equipment
    required_chair_type_id    TEXT REFERENCES chair_type(id),
    warranty_days             INTEGER CHECK (warranty_days IS NULL OR warranty_days > 0),
    -- what this service leaves on the chart once completed
    resulting_condition_type  TEXT CHECK (resulting_condition_type IS NULL OR resulting_condition_type IN (
                                  'Filling','Crown','Veneer','BridgeAbutment','BridgePontic',
                                  'Implant','RootCanalTreated','Denture','Missing')),
    is_active                 INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    display_order             INTEGER NOT NULL DEFAULT 0,

    -- a service that touches no teeth cannot be priced per tooth or per surface
    CONSTRAINT ck_service_scope_vs_basis CHECK (
        tooth_scope <> 'None' OR pricing_basis IN ('PerProcedure','PerQuadrant')),
    CONSTRAINT ck_service_none_leaves_nothing CHECK (
        tooth_scope <> 'None' OR resulting_condition_type IS NULL)
);


-- A material choice within a service, priced separately. A crown is one
-- clinical service, but zirconia and PFM are not the same money.
CREATE TABLE material_option (
    id                  TEXT PRIMARY KEY,
    service_category_id TEXT NOT NULL REFERENCES service_category(id) ON DELETE CASCADE,
    name                TEXT NOT NULL,
    description         TEXT,
    is_active           INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    display_order       INTEGER NOT NULL DEFAULT 0,
    UNIQUE (service_category_id, name)
);


-- Time-versioned price per service AND material.
CREATE TABLE price_list (
    id                  TEXT PRIMARY KEY,
    service_category_id TEXT NOT NULL REFERENCES service_category(id) ON DELETE CASCADE,
    -- NULL is the category's base price; a value prices that specific material
    material_option_id  TEXT REFERENCES material_option(id) ON DELETE CASCADE,
    unit_price          NUMERIC NOT NULL CHECK (unit_price >= 0),
    currency            TEXT NOT NULL DEFAULT 'VND',
    effective_from      TEXT NOT NULL,
    set_by              TEXT NOT NULL REFERENCES app_user(id),
    notes               TEXT
);

-- A plain UNIQUE(service, material, date) does NOT work here: SQL treats NULLs
-- as distinct, so two base-price rows for the same service and date would both
-- be accepted. Two partial indexes close that hole.
CREATE UNIQUE INDEX uq_price_base     ON price_list(service_category_id, effective_from)
    WHERE material_option_id IS NULL;
CREATE UNIQUE INDEX uq_price_material ON price_list(service_category_id, material_option_id, effective_from)
    WHERE material_option_id IS NOT NULL;


-- A voucher code the manager creates and the patient presents at billing.
-- One code, one percentage or amount, off the whole invoice.
CREATE TABLE promotion (
    id              TEXT PRIMARY KEY,
    code            TEXT NOT NULL,
    name            TEXT NOT NULL,
    discount_type   TEXT NOT NULL CHECK (discount_type IN ('Percentage','FixedAmount')),
    discount_value  NUMERIC NOT NULL CHECK (discount_value > 0),
    start_date      TEXT NOT NULL,
    end_date        TEXT NOT NULL,
    max_redemptions INTEGER CHECK (max_redemptions IS NULL OR max_redemptions > 0),
    is_active       INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_by      TEXT NOT NULL REFERENCES app_user(id),
    notes           TEXT,

    CONSTRAINT ck_promo_percentage_max_100 CHECK (
        discount_type <> 'Percentage' OR discount_value <= 100),
    CONSTRAINT ck_promo_window CHECK (end_date >= start_date)
);

-- Codes are matched case-insensitively: a patient reading one off a leaflet
-- will not reproduce its capitalisation.
CREATE UNIQUE INDEX uq_promotion_code ON promotion(UPPER(code));


CREATE INDEX idx_tooth_dentition   ON tooth(dentition, quadrant, position);
CREATE INDEX idx_chair_type        ON chair(chair_type_id);
CREATE INDEX idx_chair_status      ON chair(status);
CREATE INDEX idx_service_chairtype ON service_category(required_chair_type_id);
CREATE INDEX idx_material_service  ON material_option(service_category_id);
CREATE INDEX idx_price_lookup      ON price_list(service_category_id, effective_from DESC);
CREATE INDEX idx_price_setter      ON price_list(set_by);
CREATE INDEX idx_promo_window      ON promotion(start_date, end_date) WHERE is_active = 1;


-- =============================================================================
-- VIEWS
-- =============================================================================

-- The price in force today for every service and material, with the base-price
-- fallback applied: a material with no price of its own costs the base price.
CREATE VIEW v_current_price AS
SELECT sc.id            AS service_category_id,
       sc.name          AS service,
       mo.id            AS material_option_id,
       COALESCE(mo.name, '— base —') AS material,
       sc.is_special,
       sc.vat_rate,
       p.unit_price,
       p.effective_from,
       CASE WHEN p.material_option_id IS NULL AND mo.id IS NOT NULL
            THEN 'fallback to base' ELSE 'own price' END AS price_source
FROM service_category sc
LEFT JOIN material_option mo ON mo.service_category_id = sc.id AND mo.is_active = 1
JOIN price_list p ON p.id = (
    SELECT id FROM price_list x
    WHERE x.service_category_id = sc.id
      AND (x.material_option_id IS mo.id OR x.material_option_id IS NULL)
      AND x.effective_from <= date('now')
    ORDER BY (x.material_option_id IS NOT NULL) DESC, x.effective_from DESC
    LIMIT 1);

-- Voucher codes and whether they may be redeemed today.
CREATE VIEW v_promotion_status AS
SELECT code, name, discount_type, discount_value, start_date, end_date, max_redemptions,
       CASE WHEN is_active = 0                THEN 'inactive'
            WHEN date('now') < start_date     THEN 'not yet open'
            WHEN date('now') > end_date       THEN 'expired'
            ELSE 'redeemable' END AS state
FROM promotion;

-- The chair list a booking screen works from.
CREATE VIEW v_bookable_chair AS
SELECT c.id, c.code, ct.name AS chair_type, c.status,
       CASE WHEN c.status = 'Available' THEN 'yes' ELSE 'no' END AS bookable
FROM chair c JOIN chair_type ct ON ct.id = c.chair_type_id
ORDER BY c.display_order;
