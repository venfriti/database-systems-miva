-- TITLE: Dirty read — can B see A's uncommitted change?
-- LEVEL: A = READ COMMITTED, B = READ UNCOMMITTED (the weakest level)
-- EXPECT: No. PostgreSQL treats READ UNCOMMITTED as READ COMMITTED, so B only ever sees committed data (50).
-- STORY: a production worker starts writing off all gold thread by mistake; the front desk checks stock meanwhile.
-- @SETUP
UPDATE material SET stock_qty = 50 WHERE material_id = 4;
-- @A
BEGIN;
-- @A
UPDATE material SET stock_qty = 0 WHERE material_id = 4;
-- @B
BEGIN ISOLATION LEVEL READ UNCOMMITTED;
-- @B
SELECT stock_qty AS gold_thread_seen_by_B FROM material WHERE material_id = 4;
-- @A
ROLLBACK;
-- @B
SELECT stock_qty AS gold_thread_seen_by_B FROM material WHERE material_id = 4;
-- @B
COMMIT;
-- @TEARDOWN
SELECT p3_reset();
