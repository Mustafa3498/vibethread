-- Paste at the END of the Step 4 migration.sql (see README "Step 4 migration").
-- Hard guarantees at the database level: stock can never go negative and
-- reservations can never exceed physical stock, even if application code has a bug.

ALTER TABLE "Inventory"
  ADD CONSTRAINT "Inventory_stock_sane_chk"
  CHECK ("quantity" >= 0 AND "reserved" >= 0 AND "reserved" <= "quantity");

ALTER TABLE "StockReservation"
  ADD CONSTRAINT "StockReservation_quantity_pos_chk"
  CHECK ("quantity" > 0);
