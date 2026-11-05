-- TITLE: Two staff move the same order at once — plain UPDATE (no check)
-- LEVEL: READ COMMITTED
-- EXPECT: PROBLEM. Both see the order at 'cutting'. A moves it to 'sewing'. B, who still sees 'cutting', cancels it. B's update waits for A's lock and then overwrites A's move. The history now claims the order left 'cutting' twice.
-- @SETUP
SELECT place_order(6, 2, CURRENT_DATE + 14, '[{"variant_id": 2, "quantity": 1}]', 'P3-TEST');
SELECT move_order_stage((SELECT max(order_id) FROM sales_order WHERE notes = 'P3-TEST'), 'received', 'cutting', 3);
-- @A
BEGIN;
-- @A
UPDATE sales_order SET status = 'sewing' WHERE order_id = (SELECT max(order_id) FROM sales_order WHERE notes = 'P3-TEST');
-- @A
INSERT INTO order_stage_history (order_id, from_stage, to_stage, changed_by) VALUES ((SELECT max(order_id) FROM sales_order WHERE notes = 'P3-TEST'), 'cutting', 'sewing', 3);
-- @B
BEGIN;
-- @B
UPDATE sales_order SET status = 'cancelled' WHERE order_id = (SELECT max(order_id) FROM sales_order WHERE notes = 'P3-TEST');
-- @A
COMMIT;
-- @B
INSERT INTO order_stage_history (order_id, from_stage, to_stage, changed_by) VALUES ((SELECT max(order_id) FROM sales_order WHERE notes = 'P3-TEST'), 'cutting', 'cancelled', 4);
-- @B
COMMIT;
-- @CHECK
SELECT o.status AS final_status, string_agg(COALESCE(h.from_stage, '∅') || '→' || h.to_stage, ', ' ORDER BY h.history_id) AS history FROM sales_order o JOIN order_stage_history h USING (order_id) WHERE o.order_id = (SELECT max(order_id) FROM sales_order WHERE notes = 'P3-TEST') GROUP BY o.status;
-- @TEARDOWN
SELECT p3_reset();
