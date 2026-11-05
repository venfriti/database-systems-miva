-- TITLE: Non-repeatable read — accounts reads the same invoice twice
-- LEVEL: B = READ COMMITTED
-- EXPECT: Anomaly. B reads amount_paid = 60, then 90 inside the same transaction, because A committed a payment in between.
-- STORY: accounts (B) is preparing a customer statement while the front desk (A) records a payment.
-- @B
BEGIN ISOLATION LEVEL READ COMMITTED;
-- @B
SELECT invoice_number, total_amount, amount_paid FROM invoice WHERE invoice_id = 4;
-- @A
BEGIN;
-- @A
INSERT INTO payment (invoice_id, amount, method, reference, received_by) VALUES (4, 30.00, 'cash', 'P3-TEST', 2);
-- @A
COMMIT;
-- @B
SELECT invoice_number, total_amount, amount_paid FROM invoice WHERE invoice_id = 4;
-- @B
COMMIT;
-- @B
SELECT invoice_number, total_amount, amount_paid AS amount_paid_new_txn FROM invoice WHERE invoice_id = 4;
-- @TEARDOWN
SELECT p3_reset();
