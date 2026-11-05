-- TITLE: Two payments at once — the Portfolio 2 design (stored amount_paid + CHECK)
-- LEVEL: READ COMMITTED
-- EXPECT: Prevented. A's payment updates the invoice row and holds its lock. B's payment waits, then re-reads amount_paid = 110. 110 + 50 > 120 breaks chk_invoice_not_overpaid, so B fails.
-- @A
BEGIN;
-- @A
INSERT INTO payment (invoice_id, amount, method, reference, received_by) VALUES (4, 50.00, 'cash', 'P3-TEST', 2);
-- @B
BEGIN;
-- @B
INSERT INTO payment (invoice_id, amount, method, reference, received_by) VALUES (4, 50.00, 'pos', 'P3-TEST', 5);
-- @A
COMMIT;
-- @B
ROLLBACK;
-- @CHECK
SELECT invoice_number, total_amount, amount_paid FROM invoice WHERE invoice_id = 4;
-- @TEARDOWN
SELECT p3_reset();
