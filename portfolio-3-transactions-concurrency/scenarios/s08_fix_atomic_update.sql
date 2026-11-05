-- TITLE: Fix 2 — atomic update (stock_qty = stock_qty - n) plus the CHECK constraint
-- LEVEL: READ COMMITTED
-- EXPECT: B's UPDATE waits for A's row lock, then re-reads the committed value (20). 20 - 40 = -20 breaks CHECK (stock_qty >= 0), so B fails. No read-calculate-write gap exists.
-- @SETUP
UPDATE material SET stock_qty = 50 WHERE material_id = 4;
-- @A
BEGIN;
-- @A
UPDATE material SET stock_qty = stock_qty - 30 WHERE material_id = 4 RETURNING stock_qty;
-- @B
BEGIN;
-- @B
UPDATE material SET stock_qty = stock_qty - 40 WHERE material_id = 4 RETURNING stock_qty;
-- @A
COMMIT;
-- @B
ROLLBACK;
-- @CHECK
SELECT stock_qty AS final_stock FROM material WHERE material_id = 4;
-- @TEARDOWN
SELECT p3_reset();
