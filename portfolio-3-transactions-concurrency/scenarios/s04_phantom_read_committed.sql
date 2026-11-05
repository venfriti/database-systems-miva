-- TITLE: Phantom read — the production board counts open orders twice
-- LEVEL: B = READ COMMITTED
-- EXPECT: Anomaly. B's second count is one higher: a new 'phantom' row matching its WHERE clause appeared.
-- @B
BEGIN ISOLATION LEVEL READ COMMITTED;
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
