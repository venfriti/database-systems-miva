-- TITLE: Fix 3 — REPEATABLE READ detects the conflict; the application retries
-- LEVEL: REPEATABLE READ
-- EXPECT: B's write fails with SQLSTATE 40001 (could not serialize access due to concurrent update). B retries in a new transaction, sees 20, and declines the order.
-- @SETUP
UPDATE material SET stock_qty = 50 WHERE material_id = 4;
-- @A
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- @A
SELECT stock_qty FROM material WHERE material_id = 4;
-- @B
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- @B
SELECT stock_qty FROM material WHERE material_id = 4;
-- @A
UPDATE material SET stock_qty = 20 WHERE material_id = 4;
-- @A
COMMIT;
-- @B
UPDATE material SET stock_qty = 10 WHERE material_id = 4;
-- @B
ROLLBACK;
-- @B
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- @B
SELECT stock_qty AS stock_on_retry FROM material WHERE material_id = 4;
-- @B
ROLLBACK;
-- @CHECK
SELECT stock_qty AS final_stock FROM material WHERE material_id = 4;
-- @TEARDOWN
SELECT p3_reset();
