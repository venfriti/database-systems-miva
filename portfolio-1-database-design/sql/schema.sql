-- =====================================================================
-- StitchLine Uniforms & Embroidery — Relational Schema
-- Portfolio 1: Database Design and Modelling
-- DBMS: PostgreSQL 16
--
-- Run on an empty database:
--   psql -d stitchline -f schema.sql
--
-- Notes
--   * Surrogate keys use GENERATED ALWAYS AS IDENTITY.
--   * Money is NUMERIC(12,2) — never FLOAT (rounding errors).
--   * Foreign-key columns are NOT indexed here on purpose. Index design
--     is evaluated with before/after evidence in Portfolio 2.
-- =====================================================================

DROP SCHEMA IF EXISTS stitchline CASCADE;
CREATE SCHEMA stitchline;
SET search_path TO stitchline;

-- ---------------------------------------------------------------------
-- 1. CUSTOMERS  (supertype / subtype — disjoint, total)
-- ---------------------------------------------------------------------

CREATE TABLE customer (
    customer_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_type  VARCHAR(10)  NOT NULL
                   CHECK (customer_type IN ('school', 'individual')),
    phone          VARCHAR(20)  NOT NULL UNIQUE,
    email          VARCHAR(120),
    address        TEXT,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- Needed so subtypes can reference (id, type) together.
    -- This is what makes the specialisation DISJOINT.
    UNIQUE (customer_id, customer_type)
);

CREATE TABLE school (
    customer_id     INT          PRIMARY KEY,
    customer_type   VARCHAR(10)  NOT NULL DEFAULT 'school'
                    CHECK (customer_type = 'school'),
    school_name     VARCHAR(150) NOT NULL UNIQUE,
    contact_person  VARCHAR(100) NOT NULL,
    contact_phone   VARCHAR(20),
    FOREIGN KEY (customer_id, customer_type)
        REFERENCES customer (customer_id, customer_type)
        ON DELETE CASCADE
);

CREATE TABLE individual_customer (
    customer_id    INT          PRIMARY KEY,
    customer_type  VARCHAR(10)  NOT NULL DEFAULT 'individual'
                   CHECK (customer_type = 'individual'),
    first_name     VARCHAR(60)  NOT NULL,
    last_name      VARCHAR(60)  NOT NULL,
    FOREIGN KEY (customer_id, customer_type)
        REFERENCES customer (customer_id, customer_type)
        ON DELETE CASCADE
);

-- Body measurements for custom (Ankara) garments.
-- Stored as name/value rows: flexible but weakly typed.
-- This limitation is revisited in Portfolio 4 (NoSQL).
CREATE TABLE customer_measurement (
    customer_id   INT           NOT NULL
                  REFERENCES individual_customer (customer_id) ON DELETE CASCADE,
    measure_name  VARCHAR(40)   NOT NULL,
    value_cm      NUMERIC(5,1)  NOT NULL CHECK (value_cm > 0),
    recorded_at   DATE          NOT NULL DEFAULT CURRENT_DATE,
    PRIMARY KEY (customer_id, measure_name)
);

-- ---------------------------------------------------------------------
-- 2. STAFF
-- ---------------------------------------------------------------------

CREATE TABLE staff (
    staff_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name  VARCHAR(100) NOT NULL,
    role       VARCHAR(20)  NOT NULL
               CHECK (role IN ('admin', 'front_desk', 'production', 'accounts')),
    email      VARCHAR(120) NOT NULL UNIQUE,
    is_active  BOOLEAN      NOT NULL DEFAULT TRUE
);

-- ---------------------------------------------------------------------
-- 3. PRODUCTS, MATERIALS, BILL OF MATERIALS
-- ---------------------------------------------------------------------

CREATE TABLE supplier (
    supplier_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         VARCHAR(120) NOT NULL UNIQUE,
    phone        VARCHAR(20)
);

CREATE TABLE product (
    product_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(100) NOT NULL UNIQUE,
    category    VARCHAR(20)  NOT NULL
                CHECK (category IN ('uniform', 'sportswear', 'badge', 'accessory', 'ankara_custom'))
);

-- Products are made to order, so stock is held as raw MATERIAL,
-- not as finished variants.
CREATE TABLE product_variant (
    variant_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id  INT           NOT NULL REFERENCES product (product_id) ON DELETE RESTRICT,
    size        VARCHAR(10)   NOT NULL,
    colour      VARCHAR(30)   NOT NULL,
    list_price  NUMERIC(12,2) NOT NULL CHECK (list_price >= 0),   -- current catalogue price
    UNIQUE (product_id, size, colour)            -- natural candidate key
);

CREATE TABLE material (
    material_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_id    INT           REFERENCES supplier (supplier_id) ON DELETE SET NULL,
    name           VARCHAR(100)  NOT NULL UNIQUE,
    unit           VARCHAR(10)   NOT NULL CHECK (unit IN ('metre', 'cone', 'piece', 'kg')),
    stock_qty      NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
    reorder_level  NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (reorder_level >= 0)
);

-- M:N between variant and material, with its own attribute.
CREATE TABLE product_material (
    variant_id    INT           NOT NULL REFERENCES product_variant (variant_id) ON DELETE CASCADE,
    material_id   INT           NOT NULL REFERENCES material (material_id) ON DELETE RESTRICT,
    qty_per_unit  NUMERIC(8,3)  NOT NULL CHECK (qty_per_unit > 0),
    PRIMARY KEY (variant_id, material_id)
);

-- ---------------------------------------------------------------------
-- 4. EMBROIDERY DESIGNS
-- ---------------------------------------------------------------------

-- customer_id NULL = an in-house design available to anyone.
CREATE TABLE embroidery_design (
    design_id     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id   INT          REFERENCES customer (customer_id) ON DELETE RESTRICT,
    name          VARCHAR(100) NOT NULL,
    file_url      TEXT         NOT NULL,
    stitch_count  INT          CHECK (stitch_count > 0),
    UNIQUE (customer_id, name)
);

-- ---------------------------------------------------------------------
-- 5. ORDERS
-- ---------------------------------------------------------------------

CREATE TABLE sales_order (
    order_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_number  VARCHAR(20)  NOT NULL UNIQUE,
    customer_id   INT          NOT NULL REFERENCES customer (customer_id) ON DELETE RESTRICT,
    taken_by      INT          NOT NULL REFERENCES staff (staff_id) ON DELETE RESTRICT,
    order_date    DATE         NOT NULL DEFAULT CURRENT_DATE,
    due_date      DATE         NOT NULL,
    status        VARCHAR(12)  NOT NULL DEFAULT 'received'
                  CHECK (status IN ('received', 'cutting', 'sewing', 'embroidery',
                                    'ready', 'delivered', 'cancelled')),
    notes         TEXT,
    CONSTRAINT chk_order_due_after_order CHECK (due_date >= order_date)
);

-- Weak entity: identified by its order + line number.
CREATE TABLE order_item (
    order_id    INT           NOT NULL REFERENCES sales_order (order_id) ON DELETE CASCADE,
    line_no     SMALLINT      NOT NULL CHECK (line_no > 0),
    variant_id  INT           NOT NULL REFERENCES product_variant (variant_id) ON DELETE RESTRICT,
    quantity    INT           NOT NULL CHECK (quantity > 0),
    unit_price  NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),   -- price AT TIME OF ORDER
    PRIMARY KEY (order_id, line_no)
);

-- M:N between order item and design, with placement attributes.
CREATE TABLE order_item_design (
    order_id       INT          NOT NULL,
    line_no        SMALLINT     NOT NULL,
    design_id      INT          NOT NULL REFERENCES embroidery_design (design_id) ON DELETE RESTRICT,
    placement      VARCHAR(15)  NOT NULL
                   CHECK (placement IN ('left_chest', 'right_chest', 'back', 'left_sleeve',
                                        'right_sleeve', 'collar', 'pocket', 'cap_front')),
    custom_text    VARCHAR(60),
    thread_colour  VARCHAR(30)  NOT NULL,
    PRIMARY KEY (order_id, line_no, design_id, placement),
    FOREIGN KEY (order_id, line_no)
        REFERENCES order_item (order_id, line_no) ON DELETE CASCADE
);

-- Audit trail: any staff member may move an order between stages.
CREATE TABLE order_stage_history (
    history_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id    INT          NOT NULL REFERENCES sales_order (order_id) ON DELETE RESTRICT,
    from_stage  VARCHAR(12),                 -- NULL for the first entry
    to_stage    VARCHAR(12)  NOT NULL,
    changed_by  INT          NOT NULL REFERENCES staff (staff_id) ON DELETE RESTRICT,
    changed_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_stage_changes CHECK (from_stage IS DISTINCT FROM to_stage)
);

-- ---------------------------------------------------------------------
-- 6. INVOICES AND PAYMENTS
-- ---------------------------------------------------------------------

-- 1:1 with sales_order, enforced by UNIQUE (order_id).
-- total_amount is stored deliberately: an issued invoice is a fixed
-- legal document and must not change if order lines are edited later.
CREATE TABLE invoice (
    invoice_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_number  VARCHAR(20)   NOT NULL UNIQUE,
    order_id        INT           NOT NULL UNIQUE REFERENCES sales_order (order_id) ON DELETE RESTRICT,
    issue_date      DATE          NOT NULL DEFAULT CURRENT_DATE,
    due_date        DATE          NOT NULL,
    total_amount    NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0),
    CONSTRAINT chk_invoice_due_after_issue CHECK (due_date >= issue_date)
);

CREATE TABLE payment (
    payment_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id   INT           NOT NULL REFERENCES invoice (invoice_id) ON DELETE RESTRICT,
    amount       NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    method       VARCHAR(15)   NOT NULL CHECK (method IN ('cash', 'bank_transfer', 'card', 'pos')),
    reference    VARCHAR(50),
    paid_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    received_by  INT           NOT NULL REFERENCES staff (staff_id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- 7. STOCK MOVEMENTS (material ledger)
-- ---------------------------------------------------------------------

CREATE TABLE stock_movement (
    movement_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    material_id  INT           NOT NULL REFERENCES material (material_id) ON DELETE RESTRICT,
    order_id     INT           REFERENCES sales_order (order_id) ON DELETE RESTRICT,
    staff_id     INT           NOT NULL REFERENCES staff (staff_id) ON DELETE RESTRICT,
    change_qty   NUMERIC(10,2) NOT NULL CHECK (change_qty <> 0),   -- +in / -out
    reason       VARCHAR(12)   NOT NULL
                 CHECK (reason IN ('purchase', 'order_usage', 'adjustment', 'return')),
    moved_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    -- Usage must always be traceable to an order.
    CONSTRAINT chk_usage_has_order CHECK (reason <> 'order_usage' OR order_id IS NOT NULL)
);

-- ---------------------------------------------------------------------
-- 8. BUSINESS RULE THAT A CHECK CANNOT EXPRESS
-- ---------------------------------------------------------------------
-- "Total payments on an invoice must not exceed the invoice total."
-- A CHECK constraint only sees one row, so this needs a trigger.
-- Known weakness: two payments inserted at the same moment can both
-- pass this check. That race condition is tested in Portfolio 3.

CREATE FUNCTION trg_prevent_overpayment() RETURNS trigger AS $$
DECLARE
    v_total NUMERIC(12,2);
    v_paid  NUMERIC(12,2);
BEGIN
    SELECT total_amount INTO v_total FROM invoice WHERE invoice_id = NEW.invoice_id;

    SELECT COALESCE(SUM(amount), 0) INTO v_paid
    FROM payment
    WHERE invoice_id = NEW.invoice_id
      AND payment_id IS DISTINCT FROM NEW.payment_id;

    IF v_paid + NEW.amount > v_total THEN
        RAISE EXCEPTION 'Payment of % exceeds outstanding balance of % on invoice %',
            NEW.amount, v_total - v_paid, NEW.invoice_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_overpayment
BEFORE INSERT OR UPDATE OF amount, invoice_id ON payment
FOR EACH ROW EXECUTE FUNCTION trg_prevent_overpayment();

-- ---------------------------------------------------------------------
-- 9. DERIVED DATA AS A VIEW (computed, not stored)
-- ---------------------------------------------------------------------
-- Powers the app's "Outstanding" tab. amount_paid and balance are
-- derived from payment rows, so they can never go out of sync.

CREATE VIEW v_invoice_balance AS
SELECT  i.invoice_id,
        i.invoice_number,
        o.order_number,
        o.customer_id,
        i.total_amount,
        COALESCE(SUM(p.amount), 0)                  AS amount_paid,
        i.total_amount - COALESCE(SUM(p.amount), 0) AS balance,
        i.due_date
FROM invoice i
JOIN sales_order o  ON o.order_id = i.order_id
LEFT JOIN payment p ON p.invoice_id = i.invoice_id
GROUP BY i.invoice_id, o.order_number, o.customer_id;
