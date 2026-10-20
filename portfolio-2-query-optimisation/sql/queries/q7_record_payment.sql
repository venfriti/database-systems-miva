-- WRITE
-- Q7  Record a payment (write path)
-- Business use: accounts records a part-payment. The prevent_overpayment
-- trigger sums existing payments for the invoice before allowing it.
-- Run inside BEGIN ... ROLLBACK so the data is not changed.
INSERT INTO payment (invoice_id, amount, method, received_by)
VALUES (97084, 100.00, 'bank_transfer', 5)
