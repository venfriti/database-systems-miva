-- TITLE: Write skew — two staff take orders for the same school against its credit limit
-- LEVEL: REPEATABLE READ
-- EXPECT: PROBLEM (write skew). Each session sees 5,000 headroom and adds a 3,000 order. They write DIFFERENT rows, so nothing conflicts and both commit. The school ends 1,000 over its limit.
-- RULE: unpaid balance + new order must not exceed the school's credit_limit.
-- @SETUP
UPDATE school SET credit_limit = (SELECT SUM(i.total_amount - i.amount_paid) FROM invoice i JOIN sales_order o USING (order_id) WHERE o.customer_id = 94) + 5000 WHERE customer_id = 94;
-- @A
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- @A
SELECT credit_limit - (SELECT SUM(i.total_amount - i.amount_paid) FROM invoice i JOIN sales_order o USING (order_id) WHERE o.customer_id = 94) AS headroom FROM school WHERE customer_id = 94;
-- @B
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- @B
SELECT credit_limit - (SELECT SUM(i.total_amount - i.amount_paid) FROM invoice i JOIN sales_order o USING (order_id) WHERE o.customer_id = 94) AS headroom FROM school WHERE customer_id = 94;
-- @A
WITH o AS (INSERT INTO sales_order (order_number, customer_id, taken_by, due_date, notes)
           VALUES ('SL-SKEW-A', 94, 2, CURRENT_DATE + 21, 'P3-TEST') RETURNING order_id)
INSERT INTO invoice (invoice_number, order_id, due_date, total_amount)
SELECT 'INV-SKEW-A', order_id, CURRENT_DATE + 30, 3000 FROM o;
-- @B
WITH o AS (INSERT INTO sales_order (order_number, customer_id, taken_by, due_date, notes)
           VALUES ('SL-SKEW-B', 94, 6, CURRENT_DATE + 21, 'P3-TEST') RETURNING order_id)
INSERT INTO invoice (invoice_number, order_id, due_date, total_amount)
SELECT 'INV-SKEW-B', order_id, CURRENT_DATE + 30, 3000 FROM o;
-- @A
COMMIT;
-- @B
COMMIT;
-- @CHECK
SELECT credit_limit - (SELECT SUM(i.total_amount - i.amount_paid) FROM invoice i JOIN sales_order o USING (order_id) WHERE o.customer_id = 94) AS final_headroom FROM school WHERE customer_id = 94;
-- @TEARDOWN
SELECT p3_reset();
