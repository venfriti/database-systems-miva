-- =====================================================================
-- Portfolio 3 — Demo 1: COMMIT
-- Taking an order touches six tables. Either all six changes are saved
-- together (COMMIT) or none are. Run with:
--   psql -d stitchline -e -f sql/01-commit.sql
-- =====================================================================

SET search_path TO stitchline;
\set QUIET on

\echo '--- BEFORE: stock of the two materials this order uses ---'
SELECT material_id, name, stock_qty FROM material WHERE material_id IN (1, 7) ORDER BY 1;

\echo '--- The transaction: Bayside Primary School orders 40 white shirts (size M) ---'
BEGIN;

INSERT INTO sales_order (order_number, customer_id, taken_by, due_date, notes)
VALUES ('SL-2026-DEMO01', 94, 2, CURRENT_DATE + 21, 'P3-TEST')
RETURNING order_id AS new_order_id \gset

INSERT INTO order_item (order_id, line_no, variant_id, quantity, unit_price)
VALUES (:new_order_id, 1, 2, 40, 20.00);

INSERT INTO order_item_design (order_id, line_no, design_id, placement, thread_colour)
VALUES (:new_order_id, 1,
        (SELECT min(design_id) FROM embroidery_design WHERE customer_id = 94),
        'left_chest', 'Gold');

-- shirt M uses 1.4 m poplin and 0.07 packs of buttons per unit
UPDATE material SET stock_qty = stock_qty - 56.00 WHERE material_id = 1;
UPDATE material SET stock_qty = stock_qty - 2.80  WHERE material_id = 7;

INSERT INTO stock_movement (material_id, order_id, staff_id, change_qty, reason) VALUES
  (1, :new_order_id, 2, -56.00, 'order_usage'),
  (7, :new_order_id, 2,  -2.80, 'order_usage');

INSERT INTO order_stage_history (order_id, from_stage, to_stage, changed_by)
VALUES (:new_order_id, NULL, 'received', 2);

INSERT INTO invoice (invoice_number, order_id, due_date, total_amount)
VALUES ('INV-2026-DEMO01', :new_order_id, CURRENT_DATE + 30, 800.00);

COMMIT;

\echo '--- AFTER COMMIT: every part of the order exists ---'
SELECT o.order_number, o.status,
       (SELECT COUNT(*) FROM order_item          WHERE order_id = o.order_id) AS lines,
       (SELECT COUNT(*) FROM order_item_design   WHERE order_id = o.order_id) AS designs,
       (SELECT COUNT(*) FROM stock_movement      WHERE order_id = o.order_id) AS stock_moves,
       (SELECT COUNT(*) FROM order_stage_history WHERE order_id = o.order_id) AS history,
       i.invoice_number, i.total_amount
FROM sales_order o JOIN invoice i USING (order_id)
WHERE o.order_number = 'SL-2026-DEMO01';

\echo '--- AFTER COMMIT: stock reduced, and still equal to the ledger total ---'
SELECT m.material_id, m.name, m.stock_qty,
       m.stock_qty = (SELECT SUM(change_qty) FROM stock_movement s WHERE s.material_id = m.material_id) AS matches_ledger
FROM material m WHERE material_id IN (1, 7) ORDER BY 1;

\echo '--- The same order through place_order(): one call, one transaction ---'
SELECT place_order(94, 2, CURRENT_DATE + 21, '[{"variant_id": 2, "quantity": 40}]', 'P3-TEST') AS order_id;

\echo '--- Durability check: a NEW connection sees the committed orders ---'
\connect
SET search_path TO stitchline;
SELECT order_number, status FROM sales_order WHERE notes = 'P3-TEST' ORDER BY order_id;

\echo '--- Clean up demo data ---'
SELECT p3_reset();
