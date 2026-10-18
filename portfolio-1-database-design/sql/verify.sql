-- =====================================================================
-- StitchLine — Verification Queries
-- Evidence that the schema loads, data is consistent, and derived
-- values match stored ones. Run after schema.sql and seed.sql.
-- =====================================================================

SET search_path TO stitchline;

\echo '--- 1. Row counts per table ---'
SELECT 'customer' AS table_name, COUNT(*) FROM customer
UNION ALL SELECT 'school',              COUNT(*) FROM school
UNION ALL SELECT 'individual_customer', COUNT(*) FROM individual_customer
UNION ALL SELECT 'staff',               COUNT(*) FROM staff
UNION ALL SELECT 'product_variant',     COUNT(*) FROM product_variant
UNION ALL SELECT 'material',            COUNT(*) FROM material
UNION ALL SELECT 'sales_order',         COUNT(*) FROM sales_order
UNION ALL SELECT 'order_item',          COUNT(*) FROM order_item
UNION ALL SELECT 'invoice',             COUNT(*) FROM invoice
UNION ALL SELECT 'payment',             COUNT(*) FROM payment
UNION ALL SELECT 'stock_movement',      COUNT(*) FROM stock_movement;

\echo '--- 2. Every customer has exactly one subtype (total + disjoint) ---'
SELECT c.customer_id, c.customer_type,
       (s.customer_id IS NOT NULL)::int + (i.customer_id IS NOT NULL)::int AS subtype_rows
FROM customer c
LEFT JOIN school s              ON s.customer_id = c.customer_id
LEFT JOIN individual_customer i ON i.customer_id = c.customer_id
ORDER BY c.customer_id;

\echo '--- 3. Invoice totals match the sum of order lines ---'
SELECT i.invoice_number, i.total_amount,
       SUM(oi.quantity * oi.unit_price) AS lines_total,
       i.total_amount = SUM(oi.quantity * oi.unit_price) AS matches
FROM invoice i
JOIN order_item oi ON oi.order_id = i.order_id
GROUP BY i.invoice_id
ORDER BY i.invoice_number;

\echo '--- 4. Outstanding balances (the app''s "Outstanding" tab) ---'
SELECT invoice_number, order_number, total_amount, amount_paid, balance, due_date
FROM v_invoice_balance
WHERE balance > 0
ORDER BY due_date;

\echo '--- 5. Material stock reconciles with the movement ledger ---'
SELECT m.name, m.stock_qty,
       SUM(sm.change_qty) AS ledger_total,
       m.stock_qty = SUM(sm.change_qty) AS reconciles
FROM material m
JOIN stock_movement sm ON sm.material_id = m.material_id
GROUP BY m.material_id
ORDER BY m.material_id;

\echo '--- 6. Full order view: customer, items and designs ---'
SELECT o.order_number,
       COALESCE(s.school_name, ic.first_name || ' ' || ic.last_name) AS customer,
       p.name AS product, v.size, oi.quantity,
       d.name AS design, oid.placement, oid.thread_colour
FROM sales_order o
JOIN customer c                 ON c.customer_id = o.customer_id
LEFT JOIN school s              ON s.customer_id = c.customer_id
LEFT JOIN individual_customer ic ON ic.customer_id = c.customer_id
JOIN order_item oi              ON oi.order_id = o.order_id
JOIN product_variant v          ON v.variant_id = oi.variant_id
JOIN product p                  ON p.product_id = v.product_id
LEFT JOIN order_item_design oid ON oid.order_id = oi.order_id AND oid.line_no = oi.line_no
LEFT JOIN embroidery_design d   ON d.design_id = oid.design_id
ORDER BY o.order_number, oi.line_no;
