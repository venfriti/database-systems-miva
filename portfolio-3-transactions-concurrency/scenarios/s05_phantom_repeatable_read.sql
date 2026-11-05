-- TITLE: Phantom read — the production board counts open orders twice
-- LEVEL: B = REPEATABLE READ
-- EXPECT: Prevented. B's count does not change. (PostgreSQL's REPEATABLE READ also stops phantoms, which the SQL standard does not require.)
-- @B
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- @B
SELECT COUNT(*) AS open_orders FROM sales_order WHERE status IN ('received', 'cutting', 'sewing', 'embroidery', 'ready');
-- @A
INSERT INTO sales_order (order_number, customer_id, taken_by, due_date, notes) VALUES ('SL-2026-PHANTOM', 94, 2, CURRENT_DATE + 14, 'P3-TEST');
-- @B
SELECT COUNT(*) AS open_orders FROM sales_order WHERE status IN ('received', 'cutting', 'sewing', 'embroidery', 'ready');
-- @B
COMMIT;
-- @TEARDOWN
SELECT p3_reset();
