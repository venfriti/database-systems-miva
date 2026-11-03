-- =====================================================================
-- Portfolio 3 — Demo 2: ROLLBACK
--   Part A  explicit ROLLBACK      (staff abandons an order half-way)
--   Part B  automatic rollback     (an error inside the transaction)
--   Part C  SAVEPOINT              (undo one mistake, keep the rest)
--   Part D  sequences are not rolled back
-- Run with:
--   psql -d stitchline -e -f sql/02-rollback.sql
-- =====================================================================

SET search_path TO stitchline;
\set QUIET on

-- ---------------------------------------------------------------------
\echo '=== PART A: explicit ROLLBACK ==='
-- ---------------------------------------------------------------------
SELECT stock_qty AS poplin_before FROM material WHERE material_id = 1;

BEGIN;
INSERT INTO sales_order (order_number, customer_id, taken_by, due_date, notes)
VALUES ('SL-2026-DEMO02', 94, 2, CURRENT_DATE + 21, 'P3-TEST')
RETURNING order_id AS demo_order \gset
INSERT INTO order_item (order_id, line_no, variant_id, quantity, unit_price)
VALUES (:demo_order, 1, 2, 25, 20.00);
UPDATE material SET stock_qty = stock_qty - 35 WHERE material_id = 1;

\echo '--- inside the transaction the changes are visible ---'
SELECT (SELECT COUNT(*) FROM sales_order WHERE order_number = 'SL-2026-DEMO02') AS order_rows,
       (SELECT stock_qty FROM material WHERE material_id = 1)                AS poplin_now;

ROLLBACK;

\echo '--- after ROLLBACK: the order and the stock change are gone ---'
SELECT (SELECT COUNT(*) FROM sales_order WHERE order_number = 'SL-2026-DEMO02') AS order_rows,
       (SELECT stock_qty FROM material WHERE material_id = 1)                AS poplin_now;

-- ---------------------------------------------------------------------
\echo '=== PART B: automatic rollback on error (atomicity) ==='
-- ---------------------------------------------------------------------
\echo '--- a club orders 900 blazers through an individual account: far more wool than is in stock ---'
SELECT stock_qty AS wool_before FROM material WHERE name = 'Blazer wool blend';
SELECT COUNT(*) AS test_orders_before FROM sales_order WHERE notes = 'P3-TEST';

BEGIN;
-- place_order inserts the order header and lines BEFORE it checks stock.
-- The stock check fails, so everything it had already written is undone.
SELECT place_order(4, 2, CURRENT_DATE + 30,
  (SELECT jsonb_build_array(jsonb_build_object('variant_id', variant_id, 'quantity', 900))
   FROM product_variant v JOIN product p USING (product_id)
   WHERE p.name = 'Blazer' AND v.size = 'M' AND v.colour = 'Navy'),
  'P3-TEST');

\echo '--- the transaction is now aborted: even a harmless query is refused ---'
SELECT 1;
ROLLBACK;

\echo '--- nothing was saved: no order header, no lines, stock unchanged ---'
SELECT stock_qty AS wool_after FROM material WHERE name = 'Blazer wool blend';
SELECT COUNT(*) AS test_orders_after FROM sales_order WHERE notes = 'P3-TEST';

-- ---------------------------------------------------------------------
\echo '=== PART C: SAVEPOINT — undo one step, keep the rest ==='
-- ---------------------------------------------------------------------
BEGIN;
INSERT INTO sales_order (order_number, customer_id, taken_by, due_date, notes)
VALUES ('SL-2026-DEMO03', 94, 2, CURRENT_DATE + 21, 'P3-TEST')
RETURNING order_id AS demo_order \gset
INSERT INTO order_item (order_id, line_no, variant_id, quantity, unit_price)
VALUES (:demo_order, 1, 2, 30, 20.00);

SAVEPOINT before_design;

\echo '--- staff picks a placement the workshop does not support ---'
INSERT INTO order_item_design (order_id, line_no, design_id, placement, thread_colour)
VALUES (:demo_order, 1, (SELECT min(design_id) FROM embroidery_design WHERE customer_id = 94),
        'trouser_leg', 'Gold');

ROLLBACK TO SAVEPOINT before_design;

\echo '--- corrected placement; the order header and line were kept ---'
INSERT INTO order_item_design (order_id, line_no, design_id, placement, thread_colour)
VALUES (:demo_order, 1, (SELECT min(design_id) FROM embroidery_design WHERE customer_id = 94),
        'left_chest', 'Gold');
COMMIT;

SELECT o.order_number, oi.quantity, d.placement, d.thread_colour
FROM sales_order o
JOIN order_item oi USING (order_id)
JOIN order_item_design d USING (order_id, line_no)
WHERE o.order_number = 'SL-2026-DEMO03';

-- ---------------------------------------------------------------------
\echo '=== PART D: sequences ignore ROLLBACK ==='
-- ---------------------------------------------------------------------
SELECT last_value AS seq_before FROM order_number_seq;
BEGIN;
SELECT nextval('order_number_seq') AS taken_inside_txn;
ROLLBACK;
SELECT last_value AS seq_after_rollback FROM order_number_seq;
\echo '--- the number was used up anyway: order numbers can have gaps by design ---'

\echo '--- Clean up demo data ---'
SELECT p3_reset();
