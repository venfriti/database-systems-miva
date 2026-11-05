-- TITLE: Deadlock prevention — place_order() always locks materials in material_id order
-- LEVEL: READ COMMITTED
-- EXPECT: A orders [shirts, blazers]; B orders [blazers, shirts]. Both need poplin (1), buttons (7) and wool (8). Both lock in the order 1 → 7 → 8, so B simply waits behind A. There is no deadlock and both orders succeed.
-- @A
BEGIN;
-- @A
SELECT place_order(4, 2, CURRENT_DATE + 21, '[{"variant_id": 2, "quantity": 10}, {"variant_id": 106, "quantity": 5}]', 'P3-TEST') AS order_id;
-- @B
BEGIN;
-- @B
SELECT place_order(5, 6, CURRENT_DATE + 21, '[{"variant_id": 106, "quantity": 5}, {"variant_id": 2, "quantity": 10}]', 'P3-TEST') AS order_id;
-- @A
COMMIT;
-- @B
COMMIT;
-- @CHECK
SELECT m.material_id, m.name, m.stock_qty, m.stock_qty = (SELECT SUM(change_qty) FROM stock_movement s WHERE s.material_id = m.material_id) AS matches_ledger FROM material m WHERE m.material_id IN (1, 7, 8) ORDER BY 1;
-- @TEARDOWN
SELECT p3_reset();
