-- TITLE: Two staff move the same order at once — move_order_stage() (optimistic check)
-- LEVEL: READ COMMITTED
-- EXPECT: Prevented. The UPDATE only applies WHERE status = the stage the user saw. B waits for A, then finds the order no longer at 'cutting'. Zero rows match and B's move is refused with a clear message.
-- @SETUP
SELECT place_order(6, 2, CURRENT_DATE + 14, '[{"variant_id": 2, "quantity": 1}]', 'P3-TEST');
SELECT move_order_stage((SELECT max(order_id) FROM sales_order WHERE notes = 'P3-TEST'), 'received', 'cutting', 3);
-- @A
BEGIN;
-- @A
SELECT move_order_stage((SELECT max(order_id) FROM sales_order WHERE notes = 'P3-TEST'), 'cutting', 'sewing', 3);
-- @B
BEGIN;
-- @B
SELECT move_order_stage((SELECT max(order_id) FROM sales_order WHERE notes = 'P3-TEST'), 'cutting', 'cancelled', 4);
-- @A
COMMIT;
-- @B
ROLLBACK;
-- @CHECK
SELECT o.status AS final_status, string_agg(COALESCE(h.from_stage, '∅') || '→' || h.to_stage, ', ' ORDER BY h.history_id) AS history FROM sales_order o JOIN order_stage_history h USING (order_id) WHERE o.order_id = (SELECT max(order_id) FROM sales_order WHERE notes = 'P3-TEST') GROUP BY o.status;
-- @TEARDOWN
SELECT p3_reset();
