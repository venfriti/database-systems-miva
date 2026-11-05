-- TITLE: Fix for write skew at READ COMMITTED — place_order() locks the school row first
-- LEVEL: READ COMMITTED
-- EXPECT: B's place_order() waits on A's lock on the school row. Once A commits, B's credit check sees A's new invoice and rejects the order. Same safety as SERIALIZABLE, with no retries.
-- @SETUP
UPDATE school SET credit_limit = (SELECT SUM(i.total_amount - i.amount_paid) FROM invoice i JOIN sales_order o USING (order_id) WHERE o.customer_id = 94) + 5000 WHERE customer_id = 94;
-- @A
BEGIN;
-- @A
SELECT place_order(94, 2, CURRENT_DATE + 21, '[{"variant_id": 2, "quantity": 150}]', 'P3-TEST') AS order_id;
-- @B
BEGIN;
-- @B
SELECT place_order(94, 6, CURRENT_DATE + 21, '[{"variant_id": 2, "quantity": 150}]', 'P3-TEST') AS order_id;
-- @A
COMMIT;
-- @B
ROLLBACK;
-- @CHECK
SELECT credit_limit - (SELECT SUM(i.total_amount - i.amount_paid) FROM invoice i JOIN sales_order o USING (order_id) WHERE o.customer_id = 94) AS final_headroom FROM school WHERE customer_id = 94;
-- @TEARDOWN
SELECT p3_reset();
