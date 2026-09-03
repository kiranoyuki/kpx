-- =============================================================================
-- KPX — MODULE 7: Inventory
-- vendor · inventory_item · inventory_batch · inventory_log · procedure_supply_list
--
-- Source of truth: Design/core-entities/entities.md
-- Build order:     Design/build-plan.md  (module 7 of 9; depends on 1 and 4)
--
-- Two parallel tracks meeting at the item: procedure_supply_list says what a
-- procedure SHOULD need, inventory_log records what it actually consumed.
-- Comparing them is what makes variance visible.
--
-- Expiry belongs to the BATCH, not the item: ten boxes bought on two dates
-- expire on two dates, and only a batch can say which. That is also what gives
-- unit cost somewhere to live, and therefore what makes cost of goods
-- answerable at all.
-- =============================================================================

PRAGMA foreign_keys = ON;


CREATE TABLE vendor (
    id             TEXT PRIMARY KEY,
    name           TEXT NOT NULL UNIQUE,
    contact_person TEXT,
    phone          TEXT,
    email          TEXT,
    address        TEXT,
    notes          TEXT,
    is_active      INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1))
);


CREATE TABLE inventory_item (
    id                TEXT PRIMARY KEY,
    name              TEXT NOT NULL UNIQUE,
    unit              TEXT NOT NULL,              -- box, piece, ml, cartridge
    -- for a tracked item this is the sum of its batches, maintained by trigger
    quantity_on_hand  NUMERIC NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
    reorder_threshold NUMERIC NOT NULL DEFAULT 0 CHECK (reorder_threshold >= 0),
    -- true for perishables: composite, anaesthetic, sutures. False for a mirror
    -- or a handpiece, which never expire and need no batches.
    tracks_expiry     INTEGER NOT NULL DEFAULT 0 CHECK (tracks_expiry IN (0,1)),
    vendor_id         TEXT REFERENCES vendor(id),
    category          TEXT NOT NULL DEFAULT 'Consumable'
                          CHECK (category IN ('Consumable','Equipment','Medication','Lab')),
    last_restocked_at TEXT
);


-- One delivery of one item, with its own lot number, expiry and cost.
CREATE TABLE inventory_batch (
    id                TEXT PRIMARY KEY,
    inventory_item_id TEXT NOT NULL REFERENCES inventory_item(id) ON DELETE CASCADE,
    lot_number        TEXT NOT NULL,              -- as printed on the box
    expiry_date       TEXT NOT NULL,
    vendor_id         TEXT REFERENCES vendor(id), -- who supplied THIS batch
    quantity_received NUMERIC NOT NULL CHECK (quantity_received > 0),
    quantity_remaining NUMERIC NOT NULL CHECK (quantity_remaining >= 0),
    -- what this batch cost per unit: the basis for cost of goods. The same
    -- composite bought at two prices is two batches, and a procedure's real
    -- material cost depends on which one was opened.
    unit_cost         NUMERIC NOT NULL CHECK (unit_cost >= 0),
    received_at       TEXT NOT NULL DEFAULT (datetime('now')),

    UNIQUE (inventory_item_id, lot_number),
    CONSTRAINT ck_batch_remaining_within CHECK (quantity_remaining <= quantity_received)
);


-- Every stock movement. The source of truth: batch and item quantities are
-- maintained from here by trigger, never written directly.
CREATE TABLE inventory_log (
    id                   TEXT PRIMARY KEY,
    inventory_item_id    TEXT NOT NULL REFERENCES inventory_item(id) ON DELETE CASCADE,
    -- required for items that track expiry, so consumption and write-offs name
    -- the lot they came from
    batch_id             TEXT REFERENCES inventory_batch(id),
    change_type          TEXT NOT NULL CHECK (change_type IN ('Consumed','Restocked','Adjusted','Expired')),
    quantity_delta       NUMERIC NOT NULL CHECK (quantity_delta <> 0),   -- + added, - removed
    quantity_after       NUMERIC NOT NULL CHECK (quantity_after >= 0),   -- snapshot
    related_procedure_id TEXT REFERENCES treatment_procedure(id) ON DELETE SET NULL,
    logged_by            TEXT NOT NULL REFERENCES app_user(id),
    logged_at            TEXT NOT NULL DEFAULT (datetime('now')),
    notes                TEXT,

    -- only a restock adds stock; consumption and write-offs remove it
    CONSTRAINT ck_log_sign_matches_type CHECK (
        CASE change_type
             WHEN 'Restocked' THEN quantity_delta > 0
             WHEN 'Consumed'  THEN quantity_delta < 0
             WHEN 'Expired'   THEN quantity_delta < 0
             ELSE 1 END)      -- Adjusted may go either way
);


-- Expected supplies: attached either to a reusable instruction template, or to
-- one specific procedure instance. Never both.
CREATE TABLE procedure_supply_list (
    id                 TEXT PRIMARY KEY,
    procedure_id       TEXT REFERENCES treatment_procedure(id) ON DELETE CASCADE,
    instruction_set_id TEXT REFERENCES procedure_instruction(id) ON DELETE CASCADE,
    inventory_item_id  TEXT NOT NULL REFERENCES inventory_item(id) ON DELETE CASCADE,
    quantity_required  NUMERIC NOT NULL CHECK (quantity_required > 0),
    notes              TEXT,

    CONSTRAINT ck_supply_one_owner CHECK (
        (procedure_id IS NULL) <> (instruction_set_id IS NULL))
);

CREATE UNIQUE INDEX uq_supply_template ON procedure_supply_list(instruction_set_id, inventory_item_id)
    WHERE instruction_set_id IS NOT NULL;
CREATE UNIQUE INDEX uq_supply_procedure ON procedure_supply_list(procedure_id, inventory_item_id)
    WHERE procedure_id IS NOT NULL;


CREATE INDEX idx_item_vendor      ON inventory_item(vendor_id);
CREATE INDEX idx_item_low         ON inventory_item(quantity_on_hand, reorder_threshold);
CREATE INDEX idx_batch_item       ON inventory_batch(inventory_item_id, expiry_date);
CREATE INDEX idx_batch_expiry     ON inventory_batch(expiry_date) WHERE quantity_remaining > 0;
CREATE INDEX idx_log_item         ON inventory_log(inventory_item_id, logged_at DESC);
CREATE INDEX idx_log_batch        ON inventory_log(batch_id);
CREATE INDEX idx_log_procedure    ON inventory_log(related_procedure_id);
CREATE INDEX idx_supply_item      ON procedure_supply_list(inventory_item_id);


-- =============================================================================
-- TRIGGERS
-- =============================================================================

-- A tracked item must name its lot; an untracked one has none to name.
CREATE TRIGGER trg_log_batch_required BEFORE INSERT ON inventory_log
BEGIN
    SELECT RAISE(ABORT, 'this item tracks expiry: the movement must name a batch')
    WHERE NEW.batch_id IS NULL
      AND (SELECT tracks_expiry FROM inventory_item WHERE id = NEW.inventory_item_id) = 1;

    SELECT RAISE(ABORT, 'this item does not track expiry: it has no batches')
    WHERE NEW.batch_id IS NOT NULL
      AND (SELECT tracks_expiry FROM inventory_item WHERE id = NEW.inventory_item_id) = 0;

    SELECT RAISE(ABORT, 'that batch belongs to a different item')
    WHERE NEW.batch_id IS NOT NULL
      AND (SELECT inventory_item_id FROM inventory_batch WHERE id = NEW.batch_id)
          <> NEW.inventory_item_id;

    -- the snapshot must be what the movement actually leaves behind
    SELECT RAISE(ABORT, 'quantity_after does not match quantity_on_hand + quantity_delta')
    WHERE NEW.quantity_after
       <> (SELECT quantity_on_hand FROM inventory_item WHERE id = NEW.inventory_item_id) + NEW.quantity_delta;
END;

-- The log drives the stock levels. Nothing writes them directly.
CREATE TRIGGER trg_log_applies AFTER INSERT ON inventory_log
BEGIN
    UPDATE inventory_batch
       SET quantity_remaining = quantity_remaining + NEW.quantity_delta
     WHERE id = NEW.batch_id;

    UPDATE inventory_item
       SET quantity_on_hand  = quantity_on_hand + NEW.quantity_delta,
           last_restocked_at = CASE WHEN NEW.change_type = 'Restocked'
                                    THEN NEW.logged_at ELSE last_restocked_at END
     WHERE id = NEW.inventory_item_id;
END;

-- A new batch is stock arriving, so it must be logged like any other movement.
-- Creating one does NOT itself change quantity_on_hand; the Restocked log does.
CREATE TRIGGER trg_batch_starts_empty BEFORE INSERT ON inventory_batch
BEGIN
    SELECT RAISE(ABORT, 'a new batch starts with quantity_remaining = 0; record a Restocked log to fill it')
    WHERE NEW.quantity_remaining <> 0;
END;


-- =============================================================================
-- VIEWS
-- =============================================================================

-- What to reorder, and who to call.
CREATE VIEW v_low_stock AS
SELECT i.name AS item, i.quantity_on_hand AS on_hand, i.unit, i.reorder_threshold AS reorder_at,
       v.name AS vendor, v.contact_person, v.phone,
       CASE WHEN i.quantity_on_hand = 0 THEN 'OUT OF STOCK' ELSE 'low' END AS state
FROM inventory_item i
LEFT JOIN vendor v ON v.id = i.vendor_id
WHERE i.quantity_on_hand <= i.reorder_threshold
ORDER BY i.quantity_on_hand, i.name;

-- FEFO: the order stock should be picked in — earliest expiry first. This is
-- what stops usable stock quietly expiring behind newer stock.
CREATE VIEW v_pick_order AS
SELECT i.name AS item, b.lot_number, b.expiry_date, b.quantity_remaining AS remaining, b.unit_cost,
       CAST(julianday(b.expiry_date) - julianday('now') AS INTEGER) AS days_to_expiry,
       CASE WHEN b.expiry_date < date('now') THEN 'EXPIRED — write off'
            WHEN julianday(b.expiry_date) - julianday('now') <= 30 THEN 'expiring soon'
            ELSE 'ok' END AS state,
       ROW_NUMBER() OVER (PARTITION BY i.id ORDER BY b.expiry_date, b.received_at) AS pick_next
FROM inventory_batch b
JOIN inventory_item i ON i.id = b.inventory_item_id
WHERE b.quantity_remaining > 0
ORDER BY i.name, b.expiry_date;

-- Batches past their date that still hold stock: the write-off list.
CREATE VIEW v_expired_stock AS
SELECT i.name AS item, b.lot_number, b.expiry_date, b.quantity_remaining AS remaining, i.unit,
       b.quantity_remaining * b.unit_cost AS value_at_risk,
       CAST(julianday('now') - julianday(b.expiry_date) AS INTEGER) AS days_overdue
FROM inventory_batch b
JOIN inventory_item i ON i.id = b.inventory_item_id
WHERE b.quantity_remaining > 0 AND b.expiry_date < date('now')
ORDER BY b.expiry_date;

-- Expected versus actual: the whole point of keeping the two tracks apart.
CREATE VIEW v_supply_variance AS
SELECT sc.name AS service, i.name AS item, i.unit,
       SUM(sl.quantity_required) AS expected_per_procedure,
       COALESCE((SELECT SUM(-l.quantity_delta) FROM inventory_log l
                 WHERE l.inventory_item_id = i.id AND l.change_type = 'Consumed'
                   AND l.related_procedure_id IN (
                       SELECT pr.id FROM treatment_procedure pr
                       WHERE pr.instruction_set_id = sl.instruction_set_id)),0) AS actually_consumed
FROM procedure_supply_list sl
JOIN inventory_item i        ON i.id = sl.inventory_item_id
JOIN procedure_instruction pi ON pi.id = sl.instruction_set_id
JOIN service_category sc     ON sc.id = pi.service_category_id
WHERE sl.instruction_set_id IS NOT NULL
GROUP BY sc.name, i.name, i.unit, sl.instruction_set_id
ORDER BY sc.name, i.name;

-- What a procedure actually cost in materials, from the batches opened for it.
CREATE VIEW v_procedure_material_cost AS
SELECT pu.full_name AS patient, sc.name AS service, l.related_procedure_id AS procedure_id,
       i.name AS item, -l.quantity_delta AS used, i.unit, b.unit_cost,
       (-l.quantity_delta) * b.unit_cost AS cost
FROM inventory_log l
JOIN inventory_item i        ON i.id = l.inventory_item_id
LEFT JOIN inventory_batch b  ON b.id = l.batch_id
JOIN treatment_procedure pr  ON pr.id = l.related_procedure_id
JOIN treatment_plan tp       ON tp.id = pr.treatment_plan_id
JOIN patient_profile pp      ON pp.id = tp.patient_id
JOIN app_user pu             ON pu.id = pp.user_id
JOIN service_category sc     ON sc.id = pr.service_category_id
WHERE l.change_type = 'Consumed'
ORDER BY l.related_procedure_id, i.name;
