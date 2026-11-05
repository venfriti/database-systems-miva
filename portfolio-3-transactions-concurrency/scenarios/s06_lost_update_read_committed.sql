-- TITLE: Lost update — two orders draw on the same thread (read, calculate, write back)
-- LEVEL: READ COMMITTED (PostgreSQL default), no locking
-- EXPECT: PROBLEM. 50 cones in stock; A uses 30 and B uses 40, so 70 cones are promised from 50. Final stock shows 10 because B overwrote A's update. The CHECK (stock_qty >= 0) cannot catch it: every value written is positive.
-- @SETUP
UPDATE material SET stock_qty = 50 WHERE material_id = 4;
-- @A
BEGIN;
-- @A
SELECT stock_qty FROM material WHERE material_id = 4;
-- @B
BEGIN;
-- @B
SELECT stock_qty FROM material WHERE material_id = 4;
-- @A
UPDATE material SET stock_qty = 20 WHERE material_id = 4;
-- @A
COMMIT;
-- @B
UPDATE material SET stock_qty = 10 WHERE material_id = 4;
-- @B
COMMIT;
-- @CHECK
SELECT stock_qty AS final_stock, 50 - 30 - 40 AS true_stock FROM material WHERE material_id = 4;
-- @TEARDOWN
SELECT p3_reset();
