-- TITLE: Deadlock — two staff update the same two materials in opposite order
-- LEVEL: READ COMMITTED
-- EXPECT: A holds poplin and waits for buttons; B holds buttons and waits for poplin. PostgreSQL detects the cycle (after deadlock_timeout, 1 s), aborts B with SQLSTATE 40P01, and A carries on.
-- @A
BEGIN;
-- @A
UPDATE material SET stock_qty = stock_qty - 1 WHERE material_id = 1;
-- @B
BEGIN;
-- @B
UPDATE material SET stock_qty = stock_qty - 1 WHERE material_id = 7;
-- @A
UPDATE material SET stock_qty = stock_qty - 1 WHERE material_id = 7;
-- @B
UPDATE material SET stock_qty = stock_qty - 1 WHERE material_id = 1;
-- @B
ROLLBACK;
-- @A
COMMIT;
-- @TEARDOWN
SELECT p3_reset();
