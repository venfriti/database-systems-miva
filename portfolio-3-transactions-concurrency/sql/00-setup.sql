-- =====================================================================
-- StitchLine — Portfolio 3 setup: transactional business routines
-- Run on the database as left by Portfolio 2 (data + indexes + redesign):
--   psql -d stitchline -f sql/00-setup.sql
--
-- Adds:
--   * school.credit_limit                — a business rule that spans many rows
--   * place_order()                      — order entry as ONE atomic unit, with
--                                          row locking in a fixed order
--   * move_order_stage()                 — optimistic concurrency for the
--                                          "anyone can move an order" feature
--   * p3_reset()                         — removes test data between scenarios
-- =====================================================================

SET search_path TO stitchline;

-- ---------------------------------------------------------------------
-- 1. Credit limit for schools
--    Rule: a school's unpaid balance plus a new order must not exceed its
--    credit limit. The rule reads MANY invoice rows, so no CHECK
--    constraint can enforce it (see scenarios s10–s12).
-- ---------------------------------------------------------------------
ALTER TABLE school
    ADD COLUMN credit_limit NUMERIC(12,2) NOT NULL DEFAULT 20000
    CHECK (credit_limit >= 0);

-- Starting limits: each school's current unpaid balance plus 20,000,
-- rounded up to the next thousand.
UPDATE school s
SET credit_limit = ceil((COALESCE(b.outstanding, 0) + 20000) / 1000) * 1000
FROM (SELECT o.customer_id, SUM(i.total_amount - i.amount_paid) AS outstanding
      FROM invoice i JOIN sales_order o USING (order_id)
      GROUP BY o.customer_id) b
WHERE b.customer_id = s.customer_id;

CREATE SEQUENCE IF NOT EXISTS order_number_seq;
CREATE SEQUENCE IF NOT EXISTS invoice_number_seq;

-- ---------------------------------------------------------------------
-- 2. place_order(): the "take an order" operation as one transaction
--
--    p_items is a JSON array, e.g. '[{"variant_id": 2, "quantity": 30}]'
--
--    Everything below happens inside the caller's transaction. If ANY step
--    fails (not enough fabric, credit limit exceeded, a constraint), the
--    whole order disappears: no order row, no lines, no stock change.
--
--    Concurrency controls used:
--      a) the school row is locked (FOR UPDATE) before the credit check,
--         so two orders for the same school are checked one after another;
--      b) material rows are locked (FOR UPDATE) in material_id order, so
--         two orders needing the same materials can never deadlock;
--      c) stock is checked AFTER the lock, so the value cannot be stale.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION place_order(
    p_customer_id INT,
    p_staff_id    INT,
    p_due_date    DATE,
    p_items       JSONB,
    p_notes       TEXT DEFAULT NULL
) RETURNS INT AS $$
DECLARE
    v_order_id    INT;
    v_total       NUMERIC(12,2);
    v_limit       NUMERIC(12,2);
    v_outstanding NUMERIC(12,2);
    v_short       RECORD;
BEGIN
    -- (a) credit check for schools, serialised per school by a row lock
    SELECT credit_limit INTO v_limit
    FROM school WHERE customer_id = p_customer_id
    FOR UPDATE;

    -- order header
    INSERT INTO sales_order (order_number, customer_id, taken_by, due_date, status, notes)
    VALUES ('SL-' || to_char(CURRENT_DATE, 'YYYY') || '-W' || lpad(nextval('order_number_seq')::text, 6, '0'),
            p_customer_id, p_staff_id, p_due_date, 'received', p_notes)
    RETURNING order_id INTO v_order_id;

    -- order lines at today's list price
    INSERT INTO order_item (order_id, line_no, variant_id, quantity, unit_price)
    SELECT v_order_id, item.ord, (item.j->>'variant_id')::int, (item.j->>'quantity')::int, v.list_price
    FROM jsonb_array_elements(p_items) WITH ORDINALITY AS item(j, ord)
    JOIN product_variant v ON v.variant_id = (item.j->>'variant_id')::int;

    SELECT SUM(quantity * unit_price) INTO v_total FROM order_item WHERE order_id = v_order_id;

    IF v_limit IS NOT NULL THEN
        SELECT COALESCE(SUM(i.total_amount - i.amount_paid), 0) INTO v_outstanding
        FROM invoice i JOIN sales_order o ON o.order_id = i.order_id
        WHERE o.customer_id = p_customer_id;

        IF v_outstanding + v_total > v_limit THEN
            RAISE EXCEPTION 'Credit limit exceeded: outstanding % + order % > limit %',
                v_outstanding, v_total, v_limit
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- (b) lock every material this order needs, always in material_id order
    CREATE TEMP TABLE IF NOT EXISTS _need (material_id INT PRIMARY KEY, qty NUMERIC) ON COMMIT DROP;
    TRUNCATE _need;
    INSERT INTO _need
    SELECT pm.material_id, SUM(oi.quantity * pm.qty_per_unit)
    FROM order_item oi
    JOIN product_material pm ON pm.variant_id = oi.variant_id
    WHERE oi.order_id = v_order_id
    GROUP BY pm.material_id;

    PERFORM 1 FROM material m
    WHERE m.material_id IN (SELECT material_id FROM _need)
    ORDER BY m.material_id
    FOR UPDATE;

    -- (c) check stock now that nobody else can change it
    SELECT m.name, m.stock_qty, n.qty INTO v_short
    FROM material m JOIN _need n USING (material_id)
    WHERE m.stock_qty < n.qty
    ORDER BY m.material_id LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'Not enough %: % in stock, % needed', v_short.name, v_short.stock_qty, round(v_short.qty, 2)
            USING ERRCODE = 'check_violation';
    END IF;

    UPDATE material m SET stock_qty = m.stock_qty - n.qty
    FROM _need n WHERE n.material_id = m.material_id;

    INSERT INTO stock_movement (material_id, order_id, staff_id, change_qty, reason)
    SELECT material_id, v_order_id, p_staff_id, -round(qty, 2), 'order_usage' FROM _need;

    INSERT INTO order_stage_history (order_id, from_stage, to_stage, changed_by)
    VALUES (v_order_id, NULL, 'received', p_staff_id);

    INSERT INTO invoice (invoice_number, order_id, due_date, total_amount)
    VALUES ('INV-' || to_char(CURRENT_DATE, 'YYYY') || '-W' || lpad(nextval('invoice_number_seq')::text, 6, '0'),
            v_order_id, CURRENT_DATE + 30, v_total);

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- 3. move_order_stage(): optimistic concurrency control
--    Any staff member may move an order. The UPDATE only succeeds if the
--    order is still at the stage the user saw on screen (compare-and-set).
--    If someone else moved it first, zero rows match and the move is
--    refused instead of silently overwriting their change.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION move_order_stage(
    p_order_id INT, p_expected_stage TEXT, p_new_stage TEXT, p_staff_id INT
) RETURNS VOID AS $$
BEGIN
    UPDATE sales_order SET status = p_new_stage
    WHERE order_id = p_order_id AND status = p_expected_stage;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order % is no longer at stage "%": it was moved by someone else. Refresh and try again.',
            p_order_id, p_expected_stage
            USING ERRCODE = 'serialization_failure';
    END IF;

    INSERT INTO order_stage_history (order_id, from_stage, to_stage, changed_by)
    VALUES (p_order_id, p_expected_stage, p_new_stage, p_staff_id);
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- 4. p3_reset(): remove everything the tests create
--    Test rows are tagged: orders with notes = 'P3-TEST', payments with
--    reference = 'P3-TEST'. Stock is restored to its ledger total.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION p3_reset() RETURNS TEXT AS $$
DECLARE
    v_orders INT;
BEGIN
    DELETE FROM payment WHERE reference = 'P3-TEST'
       OR invoice_id IN (SELECT i.invoice_id FROM invoice i JOIN sales_order o USING (order_id) WHERE o.notes = 'P3-TEST');
    DELETE FROM invoice        WHERE order_id IN (SELECT order_id FROM sales_order WHERE notes = 'P3-TEST');
    DELETE FROM stock_movement WHERE order_id IN (SELECT order_id FROM sales_order WHERE notes = 'P3-TEST');
    DELETE FROM order_stage_history WHERE order_id IN (SELECT order_id FROM sales_order WHERE notes = 'P3-TEST');
    DELETE FROM sales_order WHERE notes = 'P3-TEST';
    GET DIAGNOSTICS v_orders = ROW_COUNT;

    UPDATE material m
    SET stock_qty = (SELECT SUM(change_qty) FROM stock_movement s WHERE s.material_id = m.material_id)
    WHERE stock_qty <> (SELECT SUM(change_qty) FROM stock_movement s WHERE s.material_id = m.material_id);

    -- credit limits back to the starting rule (scenarios s10–s12 change them)
    UPDATE school s
    SET credit_limit = ceil((COALESCE(b.outstanding, 0) + 20000) / 1000) * 1000
    FROM (SELECT o.customer_id, SUM(i.total_amount - i.amount_paid) AS outstanding
          FROM invoice i JOIN sales_order o USING (order_id)
          GROUP BY o.customer_id) b
    WHERE b.customer_id = s.customer_id
      AND s.credit_limit <> ceil((COALESCE(b.outstanding, 0) + 20000) / 1000) * 1000;

    RETURN 'reset: ' || v_orders || ' test orders removed';
END;
$$ LANGUAGE plpgsql;
