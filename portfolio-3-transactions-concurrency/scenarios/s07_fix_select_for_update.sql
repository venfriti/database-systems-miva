-- TITLE: Fix 1 — pessimistic locking with SELECT ... FOR UPDATE
-- LEVEL: READ COMMITTED
-- EXPECT: B's read WAITS until A commits, then sees 20. The application sees 20 < 40 and refuses B's order. Stock stays correct.
-- @SETUP
UPDATE material SET stock_qty = 50 WHERE material_id = 4;
-- @A
BEGIN;
-- @A
SELECT stock_qty FROM material WHERE material_id = 4 FOR UPDATE;
-- @B
BEGIN;
-- @B
SELECT stock_qty FROM material WHERE material_id = 4 FOR UPDATE;
-- @A
UPDATE material SET stock_qty = 20 WHERE material_id = 4;
-- @A
COMMIT;
-- @B
ROLLBACK;
-- @CHECK
SELECT stock_qty AS final_stock FROM material WHERE material_id = 4;
-- @TEARDOWN
SELECT p3_reset();
